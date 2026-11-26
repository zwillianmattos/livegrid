---
name: device-debug
description: Use when a bug only shows on a real phone (no audio in recordings, A/V desync, dropped frames, wrong resolution, camera fails on a specific model like Samsung) — logcat filters, pulling the recorded MP4 and checking tracks with ffprobe.
---

# Debug em aparelho real (Android)

Regra: nenhum "corrigido" sem evidência do aparelho ou do arquivo gravado.

## 1. Aparelho e build

```bash
adb devices -l
adb shell getprop ro.product.model; adb shell getprop ro.build.version.sdk
```

Bug "só em produção": instale **release** (`fvm flutter build apk --release` e depois `adb install -r build/app/outputs/flutter-apk/app-release.apk`). O debug muda timing e não passa por R8.

## 2. Logcat focado

```bash
adb logcat -c
adb logcat -v time AudioEncoder:V HardwareEncoder:V EncoderPool:V GlRenderer:V OpenGateCamera:V FlutterBridge:V MPEG4Writer:V MediaMuxer:V AudioRecord:W *:S
```

O que procurar:
- `AudioRecord source=... rate=...`: o mic abriu. `nenhuma combinação` ou `não entrou em RECORDING` indica mic ocupado ou bloqueado (toggle de privacidade do Android 12+).
- `encoder H ... audioTrack=N`: a trilha de áudio foi adicionada. `-1` significa gravação muda.
- `camera clock=BOOTTIME|MONOTONIC`: base de tempo detectada.
- `cam=... size=WxH`: tamanho do sensor aberto. Precisa ser 4:3.
- `MPEG4Writer`: erros de timestamp ("timestampUs ... < lastTimestampUs") ou trilha descartada.

## 3. Puxar e inspecionar a gravação

```bash
adb shell ls -t /sdcard/Movies/LiveGrid/ | head -2      # confira o RELATIVE_PATH em FlutterBridge.publishToGallery
adb pull /sdcard/Movies/LiveGrid/<arquivo>.mp4 "$SCRATCH"/
ffprobe -v error -show_entries stream=index,codec_type,codec_name,profile,width,height,sample_rate,start_time,duration,bit_rate -of compact "$SCRATCH"/<arquivo>.mp4
```

Critérios:
- Existem 2 streams: `video` h264 e `audio` aac.
- O `start_time` do áudio e o do vídeo diferem menos de 0.2 s.
- A `duration` do áudio é próxima da do vídeo.
- Horizontal 1920×1080 ou 1280×720. Vertical 1080×1920 ou 720×1280.

Medir volume (áudio presente mas mudo):

```bash
ffmpeg -hide_banner -i <arquivo>.mp4 -af volumedetect -vn -f null - 2>&1 | grep -E "mean_volume|max_volume"
```

`mean_volume` abaixo de -60 dB indica áudio digitalmente mudo (fonte errada ou mic bloqueado).

## 4. Capacidades da câmera

```bash
adb shell dumpsys media.camera | grep -iE "timestampSource|android.scaler.availableStreamConfigurations" | head
```

## 5. Fechamento

Registre no CLAUDE.md (seção "Estado do sistema" ou "Dívidas") o que o aparelho revelou e não está no código. Exemplo: um quirk de modelo.
