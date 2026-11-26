---
paths:
  - "lib/app/services/native_bridge.dart"
  - "ios/Runner/FlutterBridge.swift"
  - "android/app/src/main/kotlin/**/FlutterBridge.kt"
---

# Contrato dos platform channels

- O contrato fica na tabela "Contrato dos platform channels" do `CLAUDE.md`. Qualquer mudança em método, args, retorno ou plataforma atualiza essa tabela no mesmo commit.
- O nome do método e as chaves dos args são idênticos nos três lados (Dart, Swift `case "x":`, Kotlin `"x" ->`).
- Números chegam como `Number` no Kotlin (`(x as? Number)?.toInt()`) e como `Int`/`Double` no Swift. Não assuma `Int` vindo de um `double` Dart.
- Stats (`EventChannel('livegrid/stats')`): chave nova entra nas duas plataformas ou fica documentada como "só X".
- Para adicionar método: use o skill `add-channel-method`. Para revisar paridade: use o agente `parity-reviewer`.
