# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Projeto

**LiveGrid** é um app Flutter que funciona como nó local de captura + processamento + distribuição de vídeo para OBS. Objetivo: transformar um único celular em estação de live que entrega **dois feeds simultâneos** a partir de uma única câmera física — um horizontal 16:9 (YouTube) e um vertical 9:16 (TikTok) — expostos via SRT no LAN para o OBS consumir como fontes independentes.

Stack: Flutter (UI) + Android nativo (Kotlin, Camera2 + MediaCodec + OpenGL) + libsrt/FFmpeg-mux. SDK Dart `^3.11.5`. Foco principal Android; iOS é paridade futura.

Estado atual: **scaffold default do Flutter** (`lib/main.dart` → `MyApp`/`MyHomePage` + `test/widget_test.dart`). Nenhuma parte da arquitetura descrita abaixo está implementada ainda.

Bug pré-existente no scaffold: `lib/main.dart:31` tem `.fromSeed(...)` (falta `ColorScheme`) e `lib/main.dart:105` tem `.center` (falta `MainAxisAlignment`). `flutter analyze` / `flutter run` falham até corrigir.

## Commands

- Install deps: `flutter pub get`
- Run: `flutter run` (use `-d <device>`; `flutter devices` lista)
- Analyze / lint: `flutter analyze`
- Format: `dart format .`
- Run all tests: `flutter test`
- Run a single test file: `flutter test test/widget_test.dart`
- Run a single test by name: `flutter test --plain-name "Counter increments smoke test"`
- Build: `flutter build apk` / `ios` / `macos` / etc.

## Arquitetura alvo

```
┌──────────────────── NATIVE (Kotlin/Swift) ────────────────────┐
│  Camera2/AVFoundation  ──►  GL Texture (sensor Open Gate)      │
│        (4:3 máx)                │                              │
│                                 ├─► Surface A: full 16:9       │
│                                 │     → MediaCodec H.264 HW    │
│                                 │     → MPEG-TS mux → SRT(A)   │
│                                 ├─► Surface B: crop shader 9:16│
│                                 │     → MediaCodec H.264 HW    │
│                                 │     → MPEG-TS mux → SRT(B)   │
│                                 └─► Flutter Texture (preview)  │
└────────────────────────────────────────────────────────────────┘
                                │ platform channel
                                ▼
┌─────────────────── FLUTTER (UI) ──────────────────────────────┐
│  Preview • Start/Stop • Bitrate live • Status • Perfil res    │
└────────────────────────────────────────────────────────────────┘
```

**Fluxo end-to-end:** câmera entrega frames para um `SurfaceTexture` → `GlRenderer` renderiza em dois FBO/Surface (full + crop 9:16 via shader) → dois `MediaCodec` H.264 hardware em paralelo → mux MPEG-TS → `libsrt` em modo listener → OBS conecta como caller em `srt://PHONE_IP:9000` (horizontal) e `srt://PHONE_IP:9001` (vertical).

### Estrutura de pastas planejada

```
lib/
  app/
    controllers/           # estado da sessão
    models/                # ResolutionProfile, NetworkProfile, StreamStats
    pages/                 # live_page.dart, settings_page.dart
    services/
      native_bridge.dart   # MethodChannel + EventChannel typed
      stats_stream.dart    # Stream<BitrateSample>
android/app/src/main/kotlin/...
  camera/OpenGateCamera.kt # Camera2 wrapper, modo de maior área
  camera/GlRenderer.kt     # 2 SurfaceTexture consumers + shader crop
  encoder/HardwareEncoder.kt
  encoder/EncoderPool.kt
  stream/SrtMuxer.kt       # JNI → libsrt / FFmpeg-mux
  stream/BitrateMeter.kt
  FlutterBridge.kt         # MethodCallHandler + EventSink
native/
  ffmpeg/                  # build scripts (libsrt habilitado)
  jni/srt_mux.c
```

## Decisões não-óbvias (ler antes de alterar o pipeline)

| Tema | Decisão | Porquê |
|---|---|---|
| Encoder | **MediaCodec HW**, não FFmpeg | 4K dual-encode em SW derrete o aparelho |
| Crop 9:16 | **Shader GL**, não filtro FFmpeg `crop=w=ih*9/16:h=ih` | Zero cópia; filtro FFmpeg exigiria re-decode |
| Plugin `camera` do Flutter | **Não usar** | Não expõe controles necessários, adiciona cópias |
| FFmpegKit | Evitar — **arquivado em jan/2025**. Usar fork `ffmpeg_kit_flutter_new` ou JNI direto sobre libsrt | Abandonware |
| FFmpeg no pipeline | Só como **mux + transporte** (`-c copy`), nunca como encoder | Latência e térmica |
| Estabilização de vídeo (EIS) | **Desligar** (`CONTROL_VIDEO_STABILIZATION_MODE = OFF`) | EIS cropa o sensor e anula o Open Gate |
| Modo de câmera | 4:3 maior resolução disponível (ex: 4032x3024) | 4:3 usa mais área ativa que 16:9 (que já vem cropado do driver) |
| Resolução mínima de captura | ≥ 2160 de altura | Para manter ≥ 1080p no vertical após crop 9:16 |
| SRT topologia | Celular **listener**, OBS **caller** | OBS reconecta sozinho, não precisa descobrir IP |
| SRT latência | `latency=120` (LAN), subir para 200–300 se Wi-Fi 5GHz congestionado | Balanço ARQ vs delay |
| B-frames | **0** | Latência + compat OBS/SRT |
| GOP | 1s (= FPS) | Recuperação rápida pós-perda |
| Bitrate mode | **CBR** | Previsibilidade no LAN |
| Fallback RTMP | Só após **3 falhas SRT em 10s** | RTMP tem latência 2–4× pior |
| Preview | `Texture` widget Flutter ligado a `SurfaceTexture` nativa | Nunca trafegar frames pelo MethodChannel |

## Perfis de encoder (referência)

| Parâmetro | Horizontal (A) | Vertical (B) |
|---|---|---|
| Codec | H.264 (`video/avc`) | H.264 |
| Resolução | 1920x1080 (ou 2160 se rede aguentar) | 1080x1920 |
| FPS | 30 | 30 |
| Bitrate | 6–8 Mbps CBR | 5–6 Mbps CBR |
| GOP | 30 | 30 |
| B-frames | 0 | 0 |
| Mode | `BITRATE_MODE_CBR` | `BITRATE_MODE_CBR` |

## Platform channels

- `MethodChannel('livegrid/control')` — `startCapture(profile)`, `stop()`, `switchResolution(res)`, `setBitrate(...)`
- `EventChannel('livegrid/stats')` — emite `StreamStats{bitrateA, bitrateB, fps, droppedFrames, thermalStatus, srtRtt, srtLoss}` a **2 Hz** (nativo faz throttle; UI só consome nessa taxa)
- Preview: `Texture(textureId: ...)` — `textureId` vem do retorno de `init()`

Regra: **nunca passar frames** pelo channel — só comandos, eventos e `textureId`.

## Estratégias de latência e anti-thermal

**Latência alvo end-to-end (celular → OBS → tela):** < 400 ms.
- Encoder: `KEY_LATENCY=1` quando disponível, B-frames=0, GOP=1s.
- SRT: `latency=120`, `tsbpd=1`, `tlpktdrop=1`.
- Mux MPEG-TS com `muxdelay=0 muxpreload=0`.
- Wi-Fi 5GHz obrigatório; UI avisa quando detecta 2.4GHz.

**Thermal (principal risco). Monitorar `PowerManager.getCurrentThermalStatus()` (API 29+):**

| Status | Ação |
|---|---|
| NONE / LIGHT | mantém perfil |
| MODERATE | -25% bitrate; força 30 FPS |
| SEVERE | captura cai para 1440p (ainda cobre 1080p vertical) |
| CRITICAL | corta feed vertical; mantém horizontal 1080p 4 Mbps |
| EMERGENCY | para tudo, notifica UI |

Outros:
- `window.setSustainedPerformanceMode(true)` — segura performance estável por mais tempo.
- Encoder **assíncrono** (`MediaCodec.Callback`), buffers pré-alocados, zero GC no caminho quente.
- `MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME` para keyframe sob demanda quando OBS reconecta.
- UI lembra operador: **não carregar durante live**; brilho 40%.

## Background / permissões Android

- `ForegroundService` tipo `camera|mediaProjection|connectedDevice` (obrigatório Android 14+).
- Manifest: `android:foregroundServiceType="camera|connectedDevice"`.
- Wake lock parcial + `WifiLock` HIGH_PERF.
- Notificação persistente com botão Stop.

## Comandos FFmpeg de referência (mux-only)

Usar FFmpeg apenas para muxar H.264 AnnexB já codificado por MediaCodec e transportar via SRT. **Nunca re-encodar.**

```bash
# Horizontal (listener)
ffmpeg -fflags +nobuffer -flags +low_delay \
  -f h264 -i pipe:3 \
  -c copy -f mpegts \
  "srt://0.0.0.0:9000?mode=listener&latency=120&tsbpd=1&maxbw=12000000"

# Vertical (listener)
ffmpeg -fflags +nobuffer -flags +low_delay \
  -f h264 -i pipe:3 \
  -c copy -f mpegts \
  "srt://0.0.0.0:9001?mode=listener&latency=120&tsbpd=1&maxbw=10000000"

# Fallback RTMP (caller para nginx-rtmp ou OBS Media Source)
ffmpeg -f h264 -i pipe:3 -c copy -f flv "rtmp://PC_IP/live/horiz"
```

Filtro de referência mencionado no briefing (`crop=w=ih*9/16:h=ih`): o equivalente é feito no shader GL, não via FFmpeg — o uv remap amostra a faixa central (`cropW = srcH * 9/16`) e o MediaCodec recebe diretamente a Surface já cropada.

## iOS (futuro)

Peças equivalentes: `AVCaptureSession` (`.hd4K3840x2160`) + `CVMetalTextureCache` + shader Metal + dois `VTCompressionSession` + libsrt (xcframework). Limitação: sem background real — live iOS precisa tela ligada; documentar para o operador.
