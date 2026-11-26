# CLAUDE.md

Guia para Claude Code trabalhar neste repo. Este arquivo descreve o estado atual do código. Se algo aqui divergir do fonte, o fonte vence e este arquivo é corrigido antes de qualquer outra mudança.

## Projeto

**LiveGrid** transforma um celular em câmera para gravação dupla e câmera IP de baixa latência para o OBS (estilo DroidCam).

- **Modo `recording`:** grava dois MP4 simultâneos a partir da câmera traseira, um 16:9 e um crop 9:16, e publica ambos na galeria.
- **Modo `live`:** o celular abre um listener TCP na rede local e entrega um feed 16:9 em MPEG-TS. O OBS consome esse feed como Media Source.

Stack: Flutter (UI/controle), iOS nativo (Swift/AVFoundation/VideoToolbox) e Android nativo (Kotlin/Camera2/MediaCodec/OpenGL). SDK Dart `^3.11.5`. iOS e Android têm paridade funcional, com as exceções listadas em "Dívidas".

## Escopo da UI

- A UI Flutter atende **story makers**: só grava 16:9 + 9:16 no celular.
- O perfil sempre inicia em `CaptureMode.recording`.
- A UI não tem seletor de modo nem tela de Rede.
- O modo `live` está implementado no nativo (Swift/Kotlin) e oculto na UI. **Não remover o código nativo de streaming.**

## Estado do sistema

| Tema | Comportamento |
|---|---|
| Transporte | TCP plano + MPEG-TS H.264 AnnexB. Mux próprio (PAT/PMT/PES + CRC32, pacotes de 188 bytes). Celular é listener, OBS é cliente. Sem SRT, RTMP, libsrt ou FFmpeg. |
| Bridge | `MethodChannel('livegrid/control')` + `EventChannel('livegrid/stats')` a 2 Hz. Preview via `Texture(textureId)`. |
| Gravação | Dois MP4 locais (H + crop 9:16), publicados na galeria via PHPhotoLibrary (iOS) / MediaStore (Android). |
| Encoder | H.264 por hardware (VideoToolbox / MediaCodec). B-frames=0, GOP=fps (1 s). Android gravação: High → Main → Baseline → default, VBR se suportado, sem `KEY_LATENCY`, sem `KEY_LEVEL` fixo. Android live: Main, CBR, `KEY_LATENCY=1`. iOS: `RealTime=true`, Baseline (live) / High (recording). |
| Câmera Android | Open gate: `OpenGateCamera.pickSize` abre sempre 4:3 (sensor inteiro, ≥30 fps). Tier `quality` usa o maior 4:3; os outros usam o menor 4:3 com altura ≥ `tier.height * 16/9`. Crops 16:9 e 9:16 no shader do `GlRenderer`, com downscale de 4 amostras (`uStep`). Fps validado contra `CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES`. |
| Câmera iOS | Preset 16:9 (`CameraPreview.presetFor`). Crop vertical no tamanho do crop (ignora dimensões do perfil vertical). |
| Áudio Android | `AudioRecord` (CAMCORDER → MIC; 48 → 44,1 kHz) PCM mono → `MediaCodec` AAC-LC 128 kbps (`encoder/AudioEncoder.kt`). Só no caminho de gravação. A trilha entra no muxer na criação, com `AudioEncoder.trackFormat()` (csd-0 montado à mão), sem espera nem timeout. PTS de áudio e vídeo em `System.nanoTime`; `GlRenderer.toMonotonicNanos` converte câmeras com timestamp BOOTTIME (Samsung). RMS (0..1) sai em `audioLevel`. Se o mic falha, grava mudo. |
| Áudio iOS | Ausente. Gravações iOS saem mudas (Dívida #9). |
| Estabilização | Desligada (`preferredVideoStabilizationMode = .off` no iOS; nenhuma flag no Android). |
| Foreground service | Android: `LiveGridForegroundService` inicia em `start` e para em `stop`. Conferir os tipos no manifest ao alterar. |
| Política térmica | `SessionController._applyThermalPolicy` reduz bitrate/fps e corta o vertical conforme `ThermalStatus`. |

## Comandos

O projeto usa **FVM** (Flutter 3.41.8, ver `.fvmrc`). Sempre `fvm flutter` / `fvm dart`: o `flutter` do PATH é outra versão e não compila Dart ^3.11.5. Um hook bloqueia a forma sem `fvm`.

| Ação | Comando |
|---|---|
| Deps | `fvm flutter pub get` |
| Run | `fvm flutter run -d <device>` (`fvm flutter devices` lista) |
| Lint | `fvm flutter analyze` |
| Format | `fvm dart format lib test` |
| Tests | `fvm flutter test` |
| Build | `fvm flutter build apk [--release]` / `fvm flutter build ios --no-codesign` |

## Harness do Claude (`.claude/`)

| Tipo | Item | Uso |
|---|---|---|
| Hook | `hooks/require-fvm.sh` | Bloqueia `flutter`/`dart` sem `fvm`. |
| Hook | `hooks/format-dart.sh` | `fvm dart format` em cada `.dart` editado. |
| Rule | `rules/android-media.md` | Invariantes de relógio, muxer, áudio, câmera e encoder (carrega em `android/**/*.kt`). |
| Rule | `rules/ios-native.md` | Limites do iOS (carrega em `ios/Runner/*.swift`). |
| Rule | `rules/flutter-dart.md` | Bridge, perfis e testes (carrega em `lib/`, `test/`). |
| Rule | `rules/platform-channels.md` | Contrato entre Dart, Swift e Kotlin (carrega nos bridges). |
| Skill | `add-channel-method` | Passo a passo para método novo nos 3 lados + teste + tabela. |
| Skill | `device-debug` | Logcat, puxar MP4, `ffprobe`/volume. Para bugs que só aparecem no aparelho. |
| Skill | `release-check` | Gate completo antes de commit ou release. |
| Agente | `parity-reviewer` | Revisão read-only de paridade iOS/Android/Dart. |
| Agente | `media-reviewer` | Revisão read-only do pipeline de câmera, encoder, muxer e áudio. |

Chaves de assinatura (`android/key.properties`, `*.jks`, `*.keystore`) estão bloqueadas para leitura.

## Arquitetura

```
┌──────────────── NATIVE (Swift / Kotlin) ──────────────────┐
│  Camera (AVCaptureSession / Camera2)                       │
│       │                                                    │
│       ├─► Preview Texture (Flutter)                        │
│       ├─► Horizontal encoder (HW H.264) ──► MpegTsMuxer ──►│
│       │                                       TcpPublisher │
│       │                                       :9000 listen │
│       └─► (recording) Vertical crop 9:16 ──► encoder       │
│                                         ──► .mp4           │
└────────────────────────────────────────────────────────────┘
                       │ MethodChannel + EventChannel
                       ▼
┌──────────────────── FLUTTER ──────────────────────────────┐
│  LivePage (preview + record button + QuickControls)        │
│  SettingsPage (bitrate H/V + FPS)                          │
│  SessionController (estado, thermal policy)                │
└────────────────────────────────────────────────────────────┘
```

### Estrutura de arquivos

```
lib/
  main.dart                         # LiveGridApp + SessionController + LivePage
  app/
    constants/crop.dart
    controllers/session_controller.dart
    models/
      camera_info.dart              # CameraInfo + CameraLens
      network_profile.dart          # NetworkProfile (host, portas H/V) + WifiBand
      resolution_profile.dart       # CaptureResolution {economic|balanced|quality},
                                    # EncoderProfile, SessionProfile, CaptureMode {live|recording}
      session_state.dart
      stream_stats.dart
      thermal_status.dart
    pages/
      live_page.dart                # tela principal full-screen; QuickControls (lente,
                                    # resolução) visíveis só em SessionState.idle;
                                    # torch + ExposureControl (Android)
      settings_page.dart            # tela única: bitrate H/V + FPS da câmera
    services/native_bridge.dart     # wrapper tipado do MethodChannel
    theme/{app_theme,page_routes}.dart
    widgets/
      atoms/{blur_icon_button,blur_pill,separator_dot,status_dot}.dart
      live/{crop_panel,draggable_pip,error_bubble,exposure_control,
            fullscreen_preview,quick_controls,record_button,test_pattern,
            top_chrome}.dart
      settings/slider_row.dart
      settings/{resolution_row,url_preview}.dart   # sem imports (Dívida #10)

ios/Runner/
  AppDelegate.swift / SceneDelegate.swift
  FlutterBridge.swift               # MethodCallHandler + EventSink
  CameraPreview.swift               # AVCaptureSession + FlutterTexture + crop NV12 em CPU
  VideoEncoder.swift                # VTCompressionSession (H.264 AnnexB)
  MpegTsMuxer.swift                 # mux MPEG-TS próprio
  UdpPublisher.swift                # contém class TcpPublisher (Dívida #8)
  FileRecorder.swift                # AVAssetWriter para MP4

android/app/src/main/kotlin/br/com/wanmind/livegrid/
  MainActivity.kt
  FlutterBridge.kt
  camera/{OpenGateCamera,CapturePipeline,GlRenderer,GlCore,WindowSurface,GlUtils}.kt
  encoder/{HardwareEncoder,EncoderPool,MpegTsMuxer,BitrateMeter,AudioEncoder}.kt
  stream/TcpPublisher.kt
  service/LiveGridForegroundService.kt
```

## Contrato dos platform channels

### `MethodChannel('livegrid/control')`

| Método | Args | Retorno | Plataformas |
|---|---|---|---|
| `init` | — | `int` (textureId) | iOS, Android |
| `listCameras` | — | `List<{id,lens,label,maxWidth,maxHeight}>` | iOS, Android |
| `startCapture` | `{profile, network}` | live: `{horizontalUrl}` · recording: `{horizontalFile, verticalFile}` | iOS, Android |
| `stop` | — | `null` | iOS, Android |
| `switchResolution` | `{width,height}` | `null`. Reconfigura a sessão: para os encoders se `live` e reinicia o preview. | iOS, Android |
| `switchCamera` | `{cameraId}` | `null`. Troca a lente reiniciando o preview e preserva captureWidth/Height. | Android |
| `setBitrate` | `{horizontalBps?, verticalBps?}` | `null` | iOS, Android |
| `setFrameRate` | `{fps}` | `null`. Android: encoder + `CONTROL_AE_TARGET_FPS_RANGE` (range validado; fps sem range suportado é ignorado com log). iOS: só o encoder. | iOS, Android |
| `requestKeyframe` | — | `null` | iOS, Android |
| `setVerticalCrop` | `{centerX: 0..1}` | `null` | iOS, Android |
| `setTorch` | `{enabled: bool}` | `null` (`OpenGateCamera.setTorch`) | Android |
| `setExposure` | `{value: int}` | `null`. Passos de `CONTROL_AE_EXPOSURE_COMPENSATION`. | Android |
| `cameraCapabilities` | — | `{hasFlash, exposureMin, exposureMax, exposureStepEv}` | Android |
| `wifiBand` | — | `"2.4"` \| `"5"` \| `"unknown"` | iOS, Android |
| `deviceIp` | — | `String?` (IP local da Wi-Fi) | iOS, Android |

Métodos só do Android lançam `MissingPluginException` no iOS. O Dart engole essa exceção. `cameraCapabilities` no iOS resulta em tudo zerado/false.

### `EventChannel('livegrid/stats')` — 500 ms (2 Hz)

```
{ bitrateA, bitrateB, fps, droppedFrames, thermalStatus,
  srtRtt, srtLoss,                                    // sempre 0 (campos legados)
  txDatagramsA, txBytesA, txErrorsA,                  // só Android
  txDatagramsB, txBytesB, txErrorsB,                  // só Android
  audioLevel,                                         // 0..1 RMS; só Android, iOS = 0
  timestampMs }
```

URL do modo live: `tcp://<deviceIp>:<horizontalPort>` (padrão 9000), retornada por `startCapture` em `horizontalUrl`.

## OBS (modo live)

Passo a passo de Media Source, cena 9:16 e câmera virtual: [`docs/obs-setup.md`](docs/obs-setup.md).

## Dívidas e bugs

Cada item foi confirmado no código. Antes de corrigir, releia o arquivo apontado.

| # | Onde | Problema | Efeito |
|---|---|---|---|
| 1 | `ios/Runner/FlutterBridge.swift:handleStartLive`, `android/.../FlutterBridge.kt` (`wantsVertical=isRecording`) | No modo live, só o horizontal é publicado. | Invisível enquanto o live estiver oculto na UI. |
| 2 | `ios/Runner/CameraPreview.swift:makeVerticalCrop` | Crop vertical por `memcpy` linha a linha em CPU sobre NV12. Android usa shader GL. | Aquecimento e frames dropados em "Qualidade" (4K). |
| 3 | `ios/Runner/FlutterBridge.swift:currentThermalStatus` | iOS mapeia `.fair=1` e `.serious=3`; não existe `moderate=2`. | No iOS, a política térmica nunca aplica o nível `moderate`. |
| 5 | `ios/Runner/*` | iOS não implementa `setTorch`, `setExposure`, `cameraCapabilities` nem `switchCamera`. | No iOS, a LivePage não mostra flash/exposição, e a troca de lente só vale no próximo `start()`. |
| 7 | `ios/Runner/FlutterBridge.swift:emitStats` | Não emite `txBytes*/txDatagrams*/txErrors*`. | Stats de tx zerados no iOS. |
| 8 | `ios/Runner/UdpPublisher.swift` | O nome do arquivo não bate com a classe `TcpPublisher`. | Renomear para `TcpPublisher.swift`. |
| 9 | `ios/Runner/FileRecorder.swift`, `CameraPreview.swift` | Sem `AVCaptureAudioDataOutput`; `FileRecorder` só tem input de vídeo. `Info.plist` declara captura de áudio. | Gravações iOS mudas. |
| 10 | `lib/app/widgets/settings/{resolution_row,url_preview}.dart` | Arquivos sem imports. | Código morto. |
| 11 | iOS `CameraPreview.swift` | Sem open gate: usa preset 16:9, então o vertical sai do crop de 1080 de altura (606×1080) no tier `balanced`. | Vertical iOS com menos detalhe que o Android. |

## Decisões fixas (não reverter sem motivo forte)

| Tema | Decisão | Motivo |
|---|---|---|
| Transporte | TCP plano + MPEG-TS próprio | OBS abre como Media Source direto; zero deps nativas. |
| Encoder | Hardware (VideoToolbox / MediaCodec) | Dual-encode 4K em software derrete o aparelho. |
| B-frames | 0 | Latência + compatibilidade com OBS. |
| GOP | = fps (1 s) | Recuperação rápida após perda. |
| Bitrate | CBR no live, VBR na gravação (Android) | CBR: previsibilidade na LAN. VBR: qualidade no arquivo. |
| Captura Android | 4:3 open gate + crop no shader | Vertical 9:16 sem upscale; mesmo sensor para H e V. |
| PTS | `System.nanoTime` em todas as trilhas | Samsung descarta/desloca áudio com trilhas em bases diferentes. |
| Estabilização | OFF | EIS cropa o sensor. |
| FFmpeg | Não usar | Mux próprio basta. |
| libsrt | Não usar | TCP cru atende. |
| Plugin `camera` do Flutter | Não usar | Não expõe os controles necessários. |
| Crop vertical Android | Shader GL (`GlRenderer`) | Zero cópia. |
| Crop vertical iOS | NV12 memcpy em CPU | Provisório; migrar para Metal quando for gargalo. |

## Perfis de encoder (defaults)

Definidos em `lib/app/models/resolution_profile.dart`. `CaptureResolution.width/height` é o tier 16:9 pedido ao nativo (ver "Câmera Android/iOS").

| Tier | Horizontal | Vertical (Android) | Bitrate H / V |
|---|---|---|---|
| `economic` | 1280×720 | 720×1280 | 6 / 5 Mbps |
| `balanced` (padrão) | 1920×1080 | 1080×1920 | 12 / 10 Mbps |
| `quality` | 1920×1080 | 1080×1920 (sensor inteiro) | 16 / 14 Mbps |

- 30 fps e GOP = fps (1 s) em todos.
- Sliders: 2 a `kHorizontalMaxKbps` (24 Mbps) para H e 2 a `kVerticalMaxKbps` (20 Mbps) para V.
- FPS selecionável: 24/30/60. `SettingsPage._save` mantém `gop = fps`.

## Política térmica

`SessionController._applyThermalPolicy`:

| Status | Ação |
|---|---|
| `none` / `light` | mantém |
| `moderate` | -10% bitrate, fps base |
| `severe` | -25% bitrate, 24 fps, marca `degraded` |
| `critical` | -40% bitrate horizontal, vertical = 0, 24 fps, `degraded` |
| `emergency` / `shutdown` | `stop()` |

No iOS, `moderate` nunca dispara (Dívida #3).

## Permissões

- **iOS:** `NSCameraUsageDescription`, `NSMicrophoneUsageDescription` (declarada, sem uso real: Dívida #9), `NSPhotoLibraryAddUsageDescription`.
- **Android:** `CAMERA`, `RECORD_AUDIO`, `POST_NOTIFICATIONS`, `FOREGROUND_SERVICE_MICROPHONE` (Android 14+), `WRITE_EXTERNAL_STORAGE` (pré-Q).
- **Flutter:** `permission_handler`, via `SessionController._defaultPermissionGate`.

## Limitações do iOS

Sem execução em background. Live e gravação exigem a tela ligada.

## Convenções

- Sem comentários no código, exceto o porquê não óbvio.
- Este arquivo descreve o estado atual: sem histórico, datas ou "antes/depois". Ao alterar o código, atualize a seção correspondente.
- `flutter analyze` passa antes de todo commit.
- Commits em inglês, com prefixos `feat:` / `fix:` / `refactor:`.