# CLAUDE.md

Guia pra Claude Code trabalhar nesse repo. **Reflete o estado real do código** — se você (Claude) achar que algo aqui não bate com o que tá no fonte, atualize este arquivo antes de fazer qualquer outra coisa.

## Projeto

**LiveGrid** transforma um celular em câmera IP de baixa latência pro OBS, no estilo **DroidCam**: o app abre um listener na rede local, OBS conecta via "Media Source" e consome o vídeo.

Objetivo de produto: a partir de uma única câmera traseira, entregar **um feed horizontal 16:9 ao vivo** pro OBS via TCP+MPEG-TS, e (em modo gravação) **dois MP4 simultâneos** (16:9 + crop 9:16) salvos na galeria do celular.

**Foco atual (Set/2026):** a UI foi redirecionada pra **story makers** — usuários que só querem gravar 16:9 + 9:16 pro celular, sem OBS. O modo `live`/OBS continua implementado no nativo (Swift/Kotlin) mas **está oculto na UI Flutter**: sem seletor de modo, sem aba "Rede", perfil sempre inicia em `CaptureMode.recording`. É feature futura hibernada, não removida — não apagar o código nativo de streaming ao reativar isso.

Stack: Flutter (UI/controle) + iOS nativo (Swift/AVFoundation/VideoToolbox) + Android nativo (Kotlin/Camera2/MediaCodec/OpenGL). SDK Dart `^3.11.5`. iOS e Android estão **ambos implementados** com paridade funcional.

## Estado atual (real)

- **Transporte:** TCP plano + MPEG-TS H.264 AnnexB. **NÃO usa SRT, NÃO usa RTMP, NÃO usa libsrt, NÃO usa FFmpeg.** O mux MPEG-TS é implementação própria (PAT/PMT/PES + CRC32, 188-byte packets). Celular é listener, OBS é cliente.
- **Bridge:** `MethodChannel('livegrid/control')` + `EventChannel('livegrid/stats')`. Stats a 2 Hz. Preview por `Texture(textureId)`.
- **Modos:** `live` (TCP horizontal) e `recording` (dois MP4 locais — horizontal + crop 9:16 — auto-publicados na galeria via PHPhotoLibrary / MediaStore).
- **Encoder:** H.264 hardware (VideoToolbox no iOS, MediaCodec no Android). CBR, B-frames=0, GOP=fps (1s), `KEY_LATENCY=1` no Android, `RealTime=true` no iOS. iOS usa Baseline (live) / High (recording); Android usa Main com fallback Baseline.
- **Áudio:** implementado **só no Android**, só no caminho de gravação MP4 (`AudioRecord` PCM 44.1kHz mono → `MediaCodec` AAC-LC 128kbps → `MediaMuxer.addTrack` nos dois arquivos, H e V, via `encoder/AudioEncoder.kt`). Nível RMS (0..1) sai em `audioLevel` no stats channel. Se o mic falhar ao iniciar, grava mudo sem travar (fallback silencioso); se o formato AAC demorar mais que 1.5s pra chegar, o muxer arranca sem áudio (`HardwareEncoder.AUDIO_WAIT_TIMEOUT_MS`). **iOS não captura áudio** — `FileRecorder.swift` só tem um `AVAssetWriterInput` de vídeo; gravações iOS continuam mudas (dívida, ver tabela de bugs).
- **Estabilização:** desligada em ambas as plataformas (`preferredVideoStabilizationMode = .off` no iOS, sem flag no Android).
- **Foreground service Android:** `LiveGridForegroundService` é iniciado/parado em `start`/`stop`. Tipos no manifest precisam ser checados se for mexer.
- **Política térmica:** `SessionController._applyThermalPolicy` reduz bitrate / fps / corta vertical conforme `ThermalStatus`.

## Comandos

- Deps: `flutter pub get`
- Run: `flutter run` (use `-d <device>`; `flutter devices` lista) — projeto usa **FVM**, ver `.fvmrc`.
- Lint: `flutter analyze`
- Format: `dart format .`
- Tests: `flutter test`
- Build: `flutter build apk` / `flutter build ios`

## Arquitetura real

```
┌──────────────── NATIVE (Swift / Kotlin) ──────────────────┐
│  Camera (AVCaptureSession / Camera2)                       │
│       │                                                    │
│       ├─► Preview Texture (Flutter)                        │
│       ├─► Horizontal encoder (HW H.264) ──► MpegTsMuxer ──►│
│       │                                       TcpPublisher │
│       │                                       :9000 listen │
│       └─► (recording only) Vertical crop 9:16 ──► encoder  │
│                                              ──► .mp4      │
└────────────────────────────────────────────────────────────┘
                       │ MethodChannel + EventChannel
                       ▼
┌──────────────────── FLUTTER ──────────────────────────────┐
│  LivePage (preview + record button + chrome)               │
│  SettingsPage (Câmera | Captura | Rede | Qualidade)        │
│  SessionController (estado, thermal policy)                │
└────────────────────────────────────────────────────────────┘
```

### Estrutura real

```
lib/
  main.dart                         # LiveGridApp + SessionController + LivePage
  app/
    constants/crop.dart
    controllers/session_controller.dart
    models/
      camera_info.dart              # CameraInfo + CameraLens
      network_profile.dart          # NetworkProfile (host, ports H/V) + WifiBand
      resolution_profile.dart       # CaptureResolution {economic|balanced|quality}
                                    # EncoderProfile, SessionProfile, CaptureMode {live|recording}
      session_state.dart
      stream_stats.dart
      thermal_status.dart
    pages/
      live_page.dart                # tela principal full-screen. Câmera (lente) e
                                    # Resolução viraram chips rápidos (QuickControls)
                                    # aqui, visíveis só em SessionState.idle. Também
                                    # tem torch (flash) + ExposureControl (Android).
      settings_page.dart            # sem abas — só corpo de "Qualidade":
                                    # bitrate H/V + FPS da câmera. Câmera/Captura/Rede
                                    # e seletor LIVE/GRAVAÇÃO saíram daqui (ver acima
                                    # e "Foco atual" — Rede/modo são feature hibernada,
                                    # Câmera/Captura viraram QuickControls no LivePage).
    services/native_bridge.dart     # MethodChannel typed wrapper
    theme/{app_theme,page_routes}.dart
    widgets/
      atoms/{blur_icon_button,blur_pill,separator_dot,status_dot}.dart
      live/{crop_panel,draggable_pip,error_bubble,exposure_control,
            fullscreen_preview,quick_controls,record_button,test_pattern,
            top_chrome}.dart
      settings/{slider_row}.dart     # resolution_row.dart e url_preview.dart ainda
                                    # existem no disco mas não são mais importados
                                    # em lugar nenhum (dívida de Rede/Captura hibernadas)

ios/Runner/
  AppDelegate.swift / SceneDelegate.swift
  FlutterBridge.swift               # MethodCallHandler + EventSink
  CameraPreview.swift               # AVCaptureSession + FlutterTexture + crop NV12 CPU
  VideoEncoder.swift                # VTCompressionSession (H.264 AnnexB)
  MpegTsMuxer.swift                 # mux MPEG-TS próprio
  UdpPublisher.swift                # contém class TcpPublisher (nome do arquivo é histórico)
  FileRecorder.swift                # AVAssetWriter pra MP4

android/app/src/main/kotlin/br/com/wanmind/livegrid/
  MainActivity.kt
  FlutterBridge.kt
  camera/{OpenGateCamera,CapturePipeline,GlRenderer,GlCore,
          WindowSurface,GlUtils}.kt
  encoder/{HardwareEncoder,EncoderPool,MpegTsMuxer,BitrateMeter,AudioEncoder}.kt
  stream/TcpPublisher.kt
  service/LiveGridForegroundService.kt
```

## Platform channels — contrato real

`MethodChannel('livegrid/control')`:

| método | args | retorno |
|---|---|---|
| `init` | — | `int` (textureId) |
| `listCameras` | — | `List<{id,lens,label,maxWidth,maxHeight}>` |
| `startCapture` | `{profile, network}` | `{horizontalUrl}` (live) ou `{horizontalFile, verticalFile}` (recording) |
| `stop` | — | `null` |
| `switchResolution` | `{width,height}` | `null` — iOS e Android reconfiguram sessão (para encoders se `live`, reinicia preview) |
| `switchCamera` | `{cameraId}` | `null` — **só Android** (`FlutterBridge.handleSwitchCamera`); troca lente em runtime reiniciando preview, preserva captureWidth/Height atual. iOS não implementa. |
| `setBitrate` | `{horizontalBps?, verticalBps?}` | `null` |
| `setFrameRate` | `{fps}` | `null` — **Android também aplica ao `CONTROL_AE_TARGET_FPS_RANGE` da câmera**, não só ao encoder. iOS só ajusta encoder. |
| `requestKeyframe` | — | `null` |
| `setVerticalCrop` | `{centerX: 0..1}` | `null` |
| `setTorch` | `{enabled: bool}` | `null` — **só Android** (`OpenGateCamera.setTorch`); iOS não implementa (MissingPluginException engolida no Dart). |
| `setExposure` | `{value: int}` | `null` — **só Android**, valor em passos de `CONTROL_AE_EXPOSURE_COMPENSATION` (ver `cameraCapabilities` pro range). iOS não implementa. |
| `cameraCapabilities` | — | `{hasFlash, exposureMin, exposureMax, exposureStepEv}` — **só Android**; iOS sempre volta tudo zerado/false (MissingPluginException). |
| `wifiBand` | — | `"2.4"` \| `"5"` \| `"unknown"` |
| `deviceIp` | — | `String?` (IP local da Wi-Fi) |

`EventChannel('livegrid/stats')` — emite a 500 ms (Android) / 500 ms (iOS):
```
{ bitrateA, bitrateB, fps, droppedFrames, thermalStatus,
  srtRtt, srtLoss,                                    // sempre 0 (legado)
  txDatagramsA, txBytesA, txErrorsA,                  // só Android — iOS não emite
  txDatagramsB, txBytesB, txErrorsB,
  audioLevel,                                         // 0..1 RMS. Só Android — iOS sempre 0 (sem captura de áudio)
  timestampMs }
```

URL final pro OBS: `tcp://<deviceIp>:<horizontalPort>` (default 9000). É retornado por `startCapture` em `horizontalUrl`.

## Como configurar o OBS (Media Source)

**Filosofia:** modo live entrega **uma única fonte horizontal** pro OBS (jeito DroidCam). Vertical 9:16 é feito como cena/filtro de crop **dentro do OBS**.

`TcpPublisher` (iOS+Android) faz **broadcast** do mesmo MPEG-TS pra **múltiplos clientes** simultâneos na mesma porta — você pode criar duas Media Sources apontando pra `tcp://IP:9000` (uma cena horizontal e uma vertical com crop) sem derrubar uma a outra. Mas o jeito **mais leve** é uma fonte só + Source Mirror, ver abaixo.

### Fonte única (horizontal)

1. Add Source → **Media Source** (NÃO "Browser", NÃO "Stream").
2. Desmarcar "Local File".
3. **Input:** `tcp://IP_DO_CELULAR:9000` (mesmo IP mostrado em Configurações → Rede).
4. **Input Format:** `mpegts`.
5. ☑ Reiniciar reprodução quando ativa.
6. ☑ Usar decodificação por hardware quando disponível.
7. **Argumentos avançados de entrada** (Advanced — clicar no botão):
   ```
   fflags=nobuffer+discardcorrupt
   flags=low_delay
   probesize=32
   analyzeduration=0
   ```
8. Reconnect Delay: 1s.

Sem essas flags o OBS buferiza ~1s e parece "cortar" em rajadas. **TCP plano não tem ARQ**, perda de Wi-Fi vira stall — Wi-Fi 5 GHz é obrigatório, mesmo SSID, mesmo AP.

### Cena vertical 9:16 (crop dentro do OBS)

Não criar segunda Media Source. Use a mesma fonte em duas cenas:

**Opção A — Filter Crop/Pad (mais leve):**
1. Crie uma cena nova (ex: "Vertical 9:16"), canvas configurado como 1080×1920.
2. Adicione a fonte da Media Source horizontal **como Source Mirror** (Add → Source Mirror, escolha o Media Source que já existe).
3. Botão direito no source mirror → Filters → + → **Crop/Pad**:
   - Left: 656, Right: 656 (1920 - 608 = 1312, dividido em 2 lados → corta `(W - 9*H/16)/2` de cada lado).
4. Posicionar/escalar pra preencher 1080×1920.

Pra ajustar o "centro" do crop em vez do meio, use `Left` ≠ `Right`.

**Opção B — Transform/Crop direto na fonte:**
1. Cena vertical com canvas 1080×1920.
2. Adicione Source Mirror da Media Source horizontal.
3. Botão direito → Transform → Edit Transform → Crop: `Left=656, Right=656`.
4. Position 0,0 e Bounding Box 1080×1920 fit.

Pré-defina canvas de saída por cena: Settings → Video → Output Resolution muda quando você troca de cena (com plugin "Auto Resolution") ou exporte 1080×1920 separadamente.

### Câmera virtual no Windows / macOS (sem driver custom)

**Não precisa de driver de câmera.** O OBS já tem **Virtual Camera** embutido. Basta:

1. OBS → menu **Iniciar Câmera Virtual** (ou botão "Start Virtual Camera").
2. No Zoom/Teams/Meet/etc. selecionar **OBS Virtual Camera** como webcam.

A câmera virtual mostra a cena ativa do OBS — então pode ser a horizontal, ou trocar pra cena vertical 9:16, ou qualquer composição. No macOS instala um plugin de DAL automaticamente na primeira vez (pede senha).

Diferença de DroidCam: DroidCam vira câmera virtual diretamente no SO (precisa instalar driver). LiveGrid vira **fonte de OBS**, e o OBS faz o passo da câmera virtual. Vantagem: você ganha cenas, filtros, gravação, transmissão, tudo de graça.

## Bugs conhecidos e dívidas (Abr/2026)

Cada bug abaixo foi confirmado lendo o código. Antes de "corrigir" qualquer um, releia o arquivo apontado: o código pode ter mudado.

| # | Onde | Bug | Sintoma |
|---|---|---|---|
| 1 | `ios/Runner/FlutterBridge.swift:handleStartLive` & `android/.../FlutterBridge.kt:wantsVertical=isRecording` | Em modo **live**, vertical **não é publicado**, só horizontal. Modo live está oculto na UI (ver "Foco atual"), então isso não aparece mais pro usuário — só importa se live for reativado. | Silencioso hoje; reaparece se alguém reativar o seletor de modo. |
| 2 | `ios/Runner/CameraPreview.swift:makeVerticalCrop` | Crop vertical é `memcpy` linha-a-linha em CPU sobre NV12. CLAUDE.md original prometia shader GL/Metal — só Android tem GL renderer real. | Aquece e dropa frames em "Qualidade" (4K). |
| 3 | `ios/Runner/FlutterBridge.swift:currentThermalStatus` | iOS não tem `moderate`; mapeia `.fair=1` e pula pra `.serious=3`. `_applyThermalPolicy` no controller espera `moderate=2` e nunca aciona o degraded leve no iOS. | Política térmica do iOS pula direto pra `severe`. |
| 4 | `lib/app/models/resolution_profile.dart:154` | `EncoderProfile.horizontal1080p`/`vertical1080p` são constantes **mortas** — nada as referencia. A troca real de resolução usa `CaptureResolution.defaultHorizontalEncoder`/`defaultVerticalEncoder` via `SessionController.switchCapture`, que já deriva width/height corretos por perfil. | Nenhum (código morto); remover quando mexer no arquivo. |
| 5 | `ios/Runner/*` | iOS não implementa `setTorch`/`setExposure`/`cameraCapabilities`/`switchCamera` (só Android — ver contrato de platform channels). Dart engole `MissingPluginException` nesses métodos. | No iOS, LivePage não mostra flash/exposição, e trocar câmera pelo chip só reflete visualmente na resolução do próximo `start()` (não reinicia preview). |
| 6 | `android/.../OpenGateCamera.kt:setTargetFps` | FPS escolhido em Configurações é aplicado direto em `CONTROL_AE_TARGET_FPS_RANGE` sem validar contra `CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES` do device/resolução. | Em hardware que não suporta o fps pedido (ex: 60fps em alguma combinação de sensor), o pedido pode ser ignorado silenciosamente pela câmera. |
| 7 | `ios/Runner/FlutterBridge.swift:emitStats` | iOS não emite `txBytesA/txDatagramsA/txErrorsA`. | Stats de tx no iOS ficam zerados. |
| 8 | `ios/Runner/UdpPublisher.swift` | Arquivo se chama `UdpPublisher.swift` mas a classe é `TcpPublisher`. Histórico do refactor 576ecf5/db40130. | Confusão; renomear quando passar mexer aqui. |
| 9 | `ios/Runner/FileRecorder.swift` / `CameraPreview.swift` | iOS não captura áudio nenhum (sem `AVCaptureAudioDataOutput`, `FileRecorder` só tem `AVAssetWriterInput` de vídeo), apesar de `Info.plist` dizer "LiveGrid captura áudio junto com o vídeo". Android já captura (ver `encoder/AudioEncoder.kt`). | Gravações **iOS** saem mudas; Android não. |

## Decisões já tomadas (não reverter sem motivo forte)

| Tema | Decisão atual | Por quê |
|---|---|---|
| Transporte | TCP plano + MPEG-TS próprio | Simples, OBS abre como Media Source direto, sem libsrt, sem FFmpeg, sem deps nativas. |
| Encoder | HW (VideoToolbox / MediaCodec) | Dual-encode 4K em SW derrete o aparelho. |
| B-frames | 0 | Latência + compat OBS. |
| GOP | = fps (1s) | Recuperação rápida pós-perda. |
| Bitrate mode | CBR | Previsibilidade no LAN. |
| Estabilização | OFF | EIS cropa o sensor. |
| FFmpeg | **NÃO usar** | Mux próprio é suficiente, sem dependência arquivada. |
| libsrt | **NÃO usar** | Pelo menos enquanto TCP cru atender. |
| Plugin `camera` Flutter | NÃO usar | Não expõe controles necessários. |
| Crop vertical Android | shader GL (`GlRenderer`) | Zero cópia. |
| Crop vertical iOS | NV12 CPU memcpy | Provisório. Migrar pra Metal quando virar gargalo. |

## Perfis de encoder (defaults atuais)

Em `lib/app/models/resolution_profile.dart`:

| | Horizontal | Vertical |
|---|---|---|
| Resolução | 1920×1080 (fixo) | 1080×1920 (fixo) |
| FPS | 30 (default) | 30 (default) |
| Bitrate | 4 Mbps CBR | 3.5 Mbps CBR |
| GOP | = FPS (1 s) | = FPS (1 s) |

Sliders na aba Qualidade vão de 2-12 Mbps (H) e 2-10 Mbps (V). FPS é selecionável (24/30/60) em Configurações → Qualidade; `gop` acompanha o fps escolhido pra manter o keyframe a cada 1s (`SettingsPage._save`). No Android, mudar fps em runtime (`setFrameRate`) também reconfigura `CONTROL_AE_TARGET_FPS_RANGE` da câmera — nem todo sensor/resolução aceita todo valor, sem validação contra `CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES` (best-effort).

## Política térmica (controller)

`SessionController._applyThermalPolicy`:

| Status | Ação |
|---|---|
| `none` / `light` | mantém |
| `moderate` | -10% bitrate, fps base |
| `severe` | -25% bitrate, **24 fps**, marca `degraded` |
| `critical` | -40% bitrate horizontal, **vertical = 0**, 24 fps, `degraded` |
| `emergency` / `shutdown` | `stop()` |

iOS não dispara `moderate` (ver Bug #5).

## Permissões

- iOS: `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSPhotoLibraryAddUsageDescription` (recording → galeria). **Ainda não usa o microfone de verdade** (ver Bug #9).
- Android: `CAMERA`, `RECORD_AUDIO` (em uso, ver "Áudio" em Estado atual), `POST_NOTIFICATIONS` (foreground service), `FOREGROUND_SERVICE_MICROPHONE` (Android 14+, exigido pro serviço em foreground acessar o mic), `WRITE_EXTERNAL_STORAGE` pré-Q (recording → MediaStore).
- `permission_handler` lida com solicitação no Flutter (`SessionController._defaultPermissionGate`).

## iOS — limitações

Sem background real. Live iOS precisa tela ligada. Documentar pro operador.

## Convenções

- **Sem comentários no código** salvo o WHY não-óbvio.
- Atualize **este arquivo** quando descobrir que ele divergiu da realidade.
- `flutter analyze` deve passar antes de commit.
- Mensagens de commit em inglês, prefixos `feat:`/`fix:`/`refactor:` (ver `git log`).
