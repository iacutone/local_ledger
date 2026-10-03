#!/usr/bin/env bash
set -euo pipefail

role="${1:-small}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v ollama >/dev/null 2>&1; then
  curl -fsSL https://ollama.com/install.sh | sh
fi

case "$role" in
  small)
    ollama pull qwen2.5:0.5b
    ollama create ledger-small -f "$repo_root/Modelfile.classifier"
    ;;
  fallback)
    ollama pull qwen2.5:7b
    ollama create ledger-fallback -f "$repo_root/Modelfile.fallback"
    ;;
  *)
    echo "Usage: $0 [small|fallback]" >&2
    exit 64
    ;;
esac

echo "Ollama model provisioning completed for $role."
