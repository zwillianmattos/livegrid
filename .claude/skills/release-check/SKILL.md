---
name: release-check
description: Use before committing native or Dart changes, before a release build, or when asked "is this ready" — runs the full LiveGrid gate (analyze, tests, Android debug+release builds, iOS build) and parity/media review.
---

# Release check

Rode tudo e leia cada saída. Não declare "pronto" com etapa pulada; se pular, diga qual e por quê.

| # | Comando | Passa quando |
|---|---|---|
| 1 | `fvm dart format --output=none --set-exit-if-changed lib test` | exit 0 |
| 2 | `fvm flutter analyze` | `No issues found!` |
| 3 | `fvm flutter test` | `All tests passed!` |
| 4 | `fvm flutter build apk --debug` | `✓ Built` |
| 5 | `fvm flutter build apk --release` | `✓ Built`. Exercita R8 e a assinatura via `android/key.properties`. Nunca leia esse arquivo. |
| 6 | `fvm flutter build ios --no-codesign` | `✓ Built`. Só se `ios/` mudou ou se é release. |

Depois:
- O diff toca `FlutterBridge.*` ou `native_bridge.dart`? Rode o agente `parity-reviewer`.
- O diff toca `encoder/`, `camera/` ou `ios/Runner/*Encoder*|*Recorder*|CameraPreview*`? Rode o agente `media-reviewer`.
- O `CLAUDE.md` ainda descreve o código? Confira as seções Estado, Contrato, Dívidas e Perfis contra o diff.

Mudança de mídia (áudio, encoder, câmera) não está validada só com build. Diga explicitamente que falta o teste em aparelho (skill `device-debug`).
