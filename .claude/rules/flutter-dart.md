---
paths:
  - "lib/**/*.dart"
  - "test/**/*.dart"
---

# Flutter / Dart

- Toda chamada nativa passa por `NativeBridge` (`lib/app/services/native_bridge.dart`). Widgets e controller nunca usam `MethodChannel` direto.
- Método que só existe numa plataforma: capture `MissingPluginException` no `NativeBridge` e retorne um valor neutro.
- `CaptureResolution.width/height` é um **tier 16:9**, não o tamanho real do sensor. O Android abre 4:3 open gate, o iOS abre o preset 16:9. Ver o doc em `resolution_profile.dart`.
- `defaultVerticalEncoder` é a saída 9:16 (720×1280 ou 1080×1920). O Android escala o crop até ela. O iOS ignora as dimensões.
- Bitrate padrão precisa caber em `kHorizontalMaxKbps`/`kVerticalMaxKbps`. O `Slider` faz assert se `value > max`.
- O estado da sessão vive em `SessionController` (ChangeNotifier). Não crie outro gerenciador de estado.
- Testes de controller usam `_FakeBridge extends NativeBridge` (`test/session_controller_test.dart`). Ao adicionar método no bridge, sobrescreva no fake.
- Async em `State`: cheque `if (!mounted) return;` antes de usar `context` depois de `await`.
- Gate antes de commit: `fvm flutter analyze` sem issues e `fvm flutter test` verde.
