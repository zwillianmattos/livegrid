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
- `LivePage` tem quatro estados de tela (landscape, referência 844×390):
  - **02 Câmera (hub, idle):** guia 9:16 sempre visível no crop atual; pills PRONTO + formato (abre `showQualitySheet`); linha inferior: lente, NITIDEZ PADRÃO/ALTA (`switchCapture` balanced↔quality), FPS (abre o sheet), ENQUADRAR; rail direito de 96 px com flash/exposição (só se `capabilities` permitir), gravar e grade; miniatura da última gravação abre 05.
  - **03 Enquadrar:** só em `idle`. Arrastar no preview ou o slider move `verticalCropCenterX`; CENTRALIZAR, OK sai. Sem rail nem botão gravar.
  - **04 Gravando:** pill REC + mm:ss (derivado de `_liveStartedAt`), nível de mic + entrada ativa (INTERNO / USB / FIO + nome; SEM ÁUDIO em `none`), AQUECENDO · 24 FPS em `degraded`/térmica ≥ `severe`, PiP 9:16 72×128, chips de bitrate H/V, botão parar.
  - **05 Salvo:** overlay após `stop()` com arquivos: SALVO NA GALERIA, duração · data, miniaturas 16:9/9:16 com nome e tamanho, COMPARTILHAR 9:16 (`shareFile` do vertical), ABRIR GALERIA (`openGallery`), NOVA GRAVAÇÃO.
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
| Áudio Android | `AudioRecord` (CAMCORDER → MIC; 48 → 44,1 kHz) PCM → `MediaCodec` AAC-LC (`encoder/AudioEncoder.kt`). Só no caminho de gravação. Entrada automática via `AudioManager.getDevices(GET_DEVICES_INPUTS)` + `setPreferredDevice`: USB > com fio/line > `BUILTIN_MIC`; Bluetooth nunca. Formato (taxa/canais) decidido no `start()` sem esperar; a verificação de rota roda na thread `audio-enc`. Se o externo não for o `routedDevice` (Samsung + CAMCORDER), solta o CAMCORDER e testa MIC → VOICE_RECOGNITION um por vez no mesmo formato; se nenhum rotear, recria o CAMCORDER no mic interno. `AudioDeviceCallback` reaplica o preferido no hot-plug sem mudar o formato. Limitação: em Samsung com CAMCORDER, plugar USB no meio da gravação não troca a entrada (só vale na próxima gravação). PTS = âncora de `getTimestamp(MONOTONIC)` + amostras lidas, ressincronizado (só para frente, >20 ms) a cada ~1 s e após hot-plug. `ERROR_DEAD_OBJECT` repetido recria o `AudioRecord`; se falhar, a trilha segue com silêncio. Estéreo 192 kbps se o device aceita 2 canais (built-in: se `CHANNEL_IN_STEREO` inicializa), senão mono 128 kbps; formato fixo no start. Stats `audioInputType` (`builtin`\|`usb`\|`wired`\|`bluetooth`\|`none`) e `audioInputName` (`productName`, `none` sem gravação) vêm do `routedDevice`. A trilha entra no muxer na criação, com `AudioEncoder.trackFormat()` (csd-0 montado à mão), sem espera nem timeout. PTS de áudio e vídeo em `System.nanoTime`; `GlRenderer.toMonotonicNanos` converte câmeras com timestamp BOOTTIME (Samsung). RMS (0..1) sai em `audioLevel`. Se o mic não abre no `start()`, grava sem trilha de áudio. |
| Áudio iOS | `AVCaptureDeviceInput(audio)` + `AVCaptureAudioDataOutput` na mesma `AVCaptureSession` (`CameraPreview.attachAudioLocked`), só com permissão de mic; sem permissão grava mudo. `automaticallyConfiguresApplicationAudioSession = true`: mic USB/Lightning/P2 entra sozinho quando plugado, senão o embutido; Bluetooth HFP não é usado. Canais seguem o formato do input (embutido mono, interface USB estéreo). `FileRecorder` adiciona AAC-LC 48 kHz (128 kbps mono / 192 kbps estéreo) aos dois writers, com os mesmos sample buffers; sessão começa no primeiro PTS de vídeo e áudio anterior é descartado. PTS da captura sem conversão. Só gravação; live segue só vídeo. Stats: `audioLevel`, `audioInputType`, `audioInputName`. |
| Estabilização | Desligada (`preferredVideoStabilizationMode = .off` no iOS; nenhuma flag no Android). |
| Foreground service | Android: `LiveGridForegroundService` inicia em `start` e para em `stop`. Conferir os tipos no manifest ao alterar. |
| Política térmica | `SessionController._applyThermalPolicy` reduz bitrate/fps e corta o vertical conforme `ThermalStatus`. |
| Inicialização | Sem splash: LaunchScreen iOS preto sem imagem; Android `LaunchTheme`/`NormalTheme` pretos e, no API 31+ (`values-v31`), SplashScreen com fundo preto e ícone transparente. `LaunchGate` checa permissões (em paralelo) e, com câmera liberada, dispara `SessionController.initialize()` antes de montar a `LivePage`. `initialize()` é idempotente (Future em cache, zerado em erro): `init` → notifica com `textureId` → `listCameras` + `cameraCapabilities` em paralelo. `wifiBand`/`deviceIp` só rodam em `start()` no modo `live`. O `init` nativo responde o `textureId` antes de abrir a câmera: Android posta `startPreview` no main looper; iOS configura e chama `startRunning` em `sessionQueue` (`CameraPreview.startInBackground`). Android `cameraCapabilities` lê as `CameraCharacteristics` enquanto a câmera não abriu. |

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
│  LivePage (hub 02 · enquadrar 03 · gravando 04 · salvo 05) │
│  QualitySheet (nitidez 9:16 + FPS + bitrate H/V)           │
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
      live_page.dart                # tela principal full-screen: hub, enquadrar,
                                    # gravando e overlay Salvo (ver "Escopo da UI")
      permission_page.dart          # 01 · Permissões (landscape, 2 colunas): câmera,
                                    # microfone, galeria; PERMITIR ACESSOS / ABRIR AJUSTES
    services/native_bridge.dart     # wrapper tipado do MethodChannel
    services/permission_probe.dart  # PermissionProbe (check/request/openSettings),
                                    # SystemPermissionProbe via permission_handler
    theme/{app_theme,page_routes}.dart
    widgets/
      atoms/{blur_icon_button,blur_pill,pill_button,status_dot}.dart
      live/
        fullscreen_preview.dart     # preview 16:9 + guia 9:16 por PreviewMode
                                    # {hub|framing|recording}; arraste no framing
        hub_chrome.dart             # StatusPill, FormatPill, LastRecordingThumb
        right_rail.dart             # rail direito 96 px (topo / centro / base)
        record_button.dart
        crop_panel.dart             # barra do Enquadrar: CENTRO, slider, %, OK
        exposure_control.dart       # popover −/+ ao lado do rail (Android)
        recording_hud.dart          # RecTimerPill, MicLevelPill, ThermalPill, BitrateChip
        crop_pip.dart               # PiP 9:16 fixo (crop da mesma Texture)
        saved_review.dart           # overlay 05 Salvo + SavedRecording
        error_bubble.dart / test_pattern.dart
      quality/quality_sheet.dart    # showQualitySheet: side sheet 480 px à direita sobre
                                    # o preview; tier PADRÃO/ALTA, FPS, bitrate avançado
      settings/slider_row.dart

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
| `shareFile` | `{path: String}` (caminho devolvido por `startCapture`) | `null`. Abre o share sheet (`video/mp4`). Espera a publicação/finalização pendente do `stop`. Android: espera a thread de publicação daquele path (15 s) e, se ainda rodar, erro `publish_pending`; compartilha a URI do MediaStore (mapa path→URI de `publishRecording`, últimas 20, senão busca por `DISPLAY_NAME`); se a publicação falhou e o arquivo privado existe, compartilha via `FileProvider` (`${applicationId}.fileprovider`, `res/xml/file_paths.xml`); `ACTION_SEND` + chooser. iOS: `UIActivityViewController` com o arquivo em `Documents/recordings` (mantido após salvar na fototeca). Erro `file_not_found` se não achar. | iOS, Android |
| `openGallery` | — | `null`. Android: `ACTION_VIEW` em `MediaStore.Video.Media.EXTERNAL_CONTENT_URI` (`video/*`), fallback `CATEGORY_APP_GALLERY`. iOS: abre `photos-redirect://`. Erro `no_gallery` se falhar. | iOS, Android |

Métodos só do Android lançam `MissingPluginException` no iOS. O Dart engole essa exceção. `cameraCapabilities` no iOS resulta em tudo zerado/false.

### `EventChannel('livegrid/stats')` — 500 ms (2 Hz)

```
{ bitrateA, bitrateB, fps, droppedFrames, thermalStatus,
  srtRtt, srtLoss,                                    // sempre 0 (campos legados)
  txDatagramsA, txBytesA, txErrorsA,                  // só Android
  txDatagramsB, txBytesB, txErrorsB,                  // só Android
  audioLevel,                                         // 0..1 RMS; iOS, Android
  audioInputType, audioInputName,                     // iOS, Android
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
- Sliders (seção "Bitrate · avançado" do `QualitySheet`): 2 a `kHorizontalMaxKbps` (24 Mbps) para H e 2 a `kVerticalMaxKbps` (20 Mbps) para V, passo de 1 Mbps. Ao trocar o tier sem mexer nos sliders, valem os bitrates padrão do novo tier.
- Tier no `QualitySheet`: PADRÃO = `balanced`, ALTA = `quality`. `economic` não aparece; se o perfil estiver nele, nenhuma opção fica marcada e salvar sem escolher mantém `economic`.
- FPS selecionável: 24/30/60 (sem consulta de capacidade nativa; 60 sempre habilitado). `QualitySheet._save` chama `switchCapture` se o tier mudou, depois `updateProfile` com `gop = fps` e `mode = recording`, e reinicia a sessão se estiver ativa.

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

- **iOS:** `NSCameraUsageDescription`, `NSMicrophoneUsageDescription` (áudio das gravações), `NSPhotoLibraryAddUsageDescription`.
- **Android:** `CAMERA`, `RECORD_AUDIO`, `POST_NOTIFICATIONS`, `FOREGROUND_SERVICE_MICROPHONE` (Android 14+), `WRITE_EXTERNAL_STORAGE` (pré-Q).
- **Flutter:** `permission_handler`, atrás de `PermissionProbe` (`services/permission_probe.dart`, injetável em `SessionController(permissionProbe:)`). Status por permissão: `granted` / `pending` / `permanentlyDenied` (`restricted` conta como negado).
  - `LaunchGate` (`main.dart`) roda `checkPermissions()` no launch: câmera concedida abre a `LivePage`; senão, a `PermissionPage`. Ao conceder, `fadeRoute` troca para a `LivePage`.
  - `PermissionPage` pede câmera + microfone (+ notificação no Android, sem linha na UI) e galeria. Galeria: `Permission.photosAddOnly` no iOS; no Android conta como concedida (MediaStore no Q+). Com alguma permissão negada de vez, o botão vira "ABRIR AJUSTES" (`openAppSettings`) e o status é relido ao voltar para o app.
  - `permissionsReady` = câmera concedida. Microfone é opcional: sem ele o app grava mudo.
  - `start()` usa `_defaultPermissionGate`: relê os status, pede de novo só se a câmera não estiver concedida e falha só sem câmera.
  - iOS: o `Podfile` define `PERMISSION_PHOTOS=1` para o `permission_handler` resolver `photosAddOnly` (linha Galeria). Exige `pod install` após mudança.

## Limitações do iOS

Sem execução em background. Live e gravação exigem a tela ligada.

## Convenções

- Sem comentários no código, exceto o porquê não óbvio.
- Este arquivo descreve o estado atual: sem histórico, datas ou "antes/depois". Ao alterar o código, atualize a seção correspondente.
- `flutter analyze` passa antes de todo commit.
- Commits em inglês, com prefixos `feat:` / `fix:` / `refactor:`.