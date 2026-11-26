---
paths:
  - "android/app/src/main/kotlin/**/*.kt"
  - "android/app/src/main/AndroidManifest.xml"
---

# Android: câmera, encoder e muxer

## Relógio único

- Todo PTS (vídeo e áudio) está em **`System.nanoTime` (MONOTONIC)**, em µs no encoder/muxer.
- O vídeo usa o timestamp do `SurfaceTexture`. `GlRenderer.toMonotonicNanos` converte câmeras `SENSOR_INFO_TIMESTAMP_SOURCE=REALTIME` (base `elapsedRealtimeNanos`, maioria dos Samsung).
- O áudio ancora o primeiro frame com `AudioRecord.getTimestamp(TIMEBASE_MONOTONIC)` e depois conta amostras.
- Nunca use PTS começando em 0 numa trilha e absoluto na outra. Em Samsung, o MP4 sai sem som.

## MediaMuxer

- A trilha de áudio entra **na criação do muxer** (`HardwareEncoder.start`), com `AudioEncoder.trackFormat()` (csd-0 montado à mão). Não existe timeout de espera de áudio. Não reintroduza.
- `addTrack` depois de `start()` lança `IllegalStateException`. Só adicione trilha antes de `start()`.
- Nunca grave buffers com `BUFFER_FLAG_CODEC_CONFIG` via `writeSampleData`.
- O PTS de cada trilha precisa ser estritamente crescente (`writeAudioLocked` descarta repetidos).

## Áudio

- Fontes: `CAMCORDER`, depois `MIC`. Com mic externo preferido e não roteado (Samsung), `MIC` e depois `VOICE_RECOGNITION` no mesmo formato. **Não use `UNPROCESSED`**: sem AGC, sai quase mudo em Samsung.
- Taxas: 48000, depois 44100. Use só taxas presentes na tabela AAC (`AudioEncoder.AAC_FREQ_INDEX`).
- Mic indisponível: grava mudo e loga. Nunca derruba a gravação.

## Câmera (open gate)

- `OpenGateCamera.pickSize` sempre abre **4:3** (sensor inteiro). Os crops 16:9 e 9:16 saem do shader em `GlRenderer.cropUniform`.
- Só use tamanhos com `getOutputMinFrameDuration` ≤ 1/30 s.
- Valide fps com `pickFpsRange` contra `CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES`.
- Estabilização (EIS/OIS) fica OFF. EIS cropa o sensor.

## Encoder

- Gravação (`.mp4`): perfil High se suportado, VBR se suportado, sem `KEY_LATENCY`.
- Live (MPEG-TS): Main, CBR, `KEY_LATENCY=1`.
- Não fixe `KEY_LEVEL`. O encoder escolhe, e 4.1 fixo quebra 1080p60/Exynos.
- B-frames=0 sempre.
- O downscale usa 4 amostras bilineares no fragment shader (`uStep`). Não volte para uma amostra só, porque reduzir 4000×3000 para 1080p com um tap gera aliasing.

## Threads

- O GL roda só em `GlRenderer.handler`. Cada encoder tem seu `HandlerThread`. O muxer é protegido por `muxerLock`.
- Campos lidos por outra thread (`EncoderPool.horizontal/vertical`) levam `@Volatile`.

## Verificação

- Compile: `fvm flutter build apk --debug`. Bug de produção: também `--release` (R8).
- Comportamento real só em aparelho: use o skill `device-debug`.
