#!/usr/bin/env bash
# PreToolUse(Bash): bloqueia `flutter`/`dart` sem `fvm`.
# O `flutter` do PATH é outra versão (3.29.x) e quebra com Dart ^3.11.5 deste projeto.
cmd=$(jq -r '.tool_input.command // ""')
if printf '%s' "$cmd" | grep -Eq '(^|[;&|(`]|&&|\|\||\$\()[[:space:]]*(flutter|dart)([[:space:]]|$)'; then
  echo "Use 'fvm flutter' / 'fvm dart' neste projeto (versão fixada em .fvmrc). Comando bloqueado: $cmd" >&2
  exit 2
fi
exit 0
