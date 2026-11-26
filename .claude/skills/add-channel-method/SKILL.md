---
name: add-channel-method
description: Use when adding, renaming or changing a method on MethodChannel('livegrid/control') or a key on EventChannel('livegrid/stats') — keeps Dart, Swift, Kotlin, tests and the CLAUDE.md contract table in sync.
---

# Adicionar/alterar método de platform channel

Paridade iOS/Android é a fonte nº 1 de bugs deste repo. Faça os passos na ordem, todos no mesmo commit.

1. **Contrato primeiro.** Edite a tabela "Contrato dos platform channels" em `CLAUDE.md`: nome, args (chaves exatas), retorno e coluna Plataformas.
2. **Dart** (`lib/app/services/native_bridge.dart`):
   - Método tipado. Args em `Map` com as chaves do contrato. Opcional usa `'key': ?value`.
   - Se alguma plataforma não implementar: `try { ... } on MissingPluginException { return <neutro>; }`.
3. **Fake de teste** (`test/session_controller_test.dart`, `_FakeBridge`): sobrescreva o método e registre em `calls`.
4. **Android** (`android/.../FlutterBridge.kt`, bloco `when (call.method)`):
   - Use `"nome" -> { ... }`. Leia números como `(call.argument<Number>("k"))?.toInt()`.
   - Responda sempre: `result.success(...)` ou `result.error(code, msg, null)`.
   - Trabalho de câmera/GL: delegue ao `CapturePipeline`. Nunca chame GL fora de `GlRenderer.handler`.
5. **iOS** (`ios/Runner/FlutterBridge.swift`, `switch call.method`):
   - Use `case "nome":`. Args via `call.arguments as? [String: Any]`.
   - Se não implementar agora, não crie stub silencioso: deixe cair em `FlutterMethodNotImplemented` e marque "Android" na tabela.
6. **Controller/UI**: só via `NativeBridge`. Escreva o teste do controller antes da mudança no controller.
7. **Verificação**, rodando cada comando e lendo a saída:
   - `fvm flutter analyze` → `No issues found!`
   - `fvm flutter test` → `All tests passed!`
   - `fvm flutter build apk --debug` → `✓ Built`
   - `fvm flutter build ios --no-codesign` (se o Swift mudou)
8. Rode o agente `parity-reviewer` no diff.
