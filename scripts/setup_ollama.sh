#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v ollama >/dev/null 2>&1; then
  curl -fsSL https://ollama.com/install.sh | sh
fi

ollama pull qwen2.5:0.5b
ollama create ledger-small -f "$repo_root/Modelfile"

echo "Ollama model provisioning completed for the local classifier."
