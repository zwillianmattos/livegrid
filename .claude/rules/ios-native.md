---
paths:
  - "ios/Runner/**/*.swift"
  - "ios/Runner/Info.plist"
---

# iOS nativo

- A captura usa `AVCaptureSession.sessionPreset` 16:9 (`CameraPreview.presetFor`). Não é open gate como no Android.
- O crop vertical é calculado no Swift a partir da altura de captura (`FlutterBridge.swift`, `vCropW = captureH * 9/16`). O iOS **ignora** `width`/`height` do perfil vertical vindo do Dart. Usa só `fps` e `bitrateBps`.
- O crop vertical é `memcpy` NV12 em CPU (Dívida #2). Não adicione mais cópias por frame no caminho de captura.
- Não há áudio (Dívida #9). Ao implementar, use o mesmo relógio do vídeo (`CMSampleBuffer` PTS da sessão) e adicione o `AVAssetWriterInput` de áudio antes de `startWriting`.
- Métodos só do Android (`setTorch`, `setExposure`, `cameraCapabilities`, `switchCamera`) não existem aqui. O Dart engole `MissingPluginException`. Ao implementar um deles, atualize a coluna "Plataformas" no CLAUDE.md.
- `UdpPublisher.swift` contém `TcpPublisher` (Dívida #8).
- Compile: `fvm flutter build ios --no-codesign`.
