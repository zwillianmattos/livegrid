#!/usr/bin/env bash
# PostToolUse(Edit|Write): formata o arquivo Dart editado.
file=$(jq -r '.tool_input.file_path // ""')
case "$file" in
  *.dart) [ -f "$file" ] && cd "$CLAUDE_PROJECT_DIR" && fvm dart format "$file" >/dev/null 2>&1 ;;
esac
exit 0
