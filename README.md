# Local Ledger

[Local Ledger](https://ledger.iacut.one): an application that parses credit-card CSV data with NimbleCSV, classifies merchants locally, and outputs Plain Text Accounting ([ledger](https://plaintextaccounting.org/)) format.

- CSV parsing, transaction types, balancing, and ledger generation are deterministic Elixir code.
- Unknown merchants are classified by a local `qwen2.5:0.5b` Ollama model. A private `qwen2.5:7b` Ollama host is used only when the small model returns invalid or low-confidence JSON.
- Financial data is sent only to the configured Ollama endpoints.

## Dependencies

- [Ollama](https://ollama.com/)
- Elixir (via [asdf](https://asdf-vm.com/))
- [ledger-cli](https://ledger-cli.org/) (`brew install ledger` or `apt install ledger`)
- [ngrok](https://ngrok.com/) tunnel


## To Run

- `ollama pull qwen2.5:0.5b`
- `ollama create ledger-small -f Modelfile.classifier`
- Configure `OLLAMA_BASE_URL` to the host Ollama service.
- Configure `OLLAMA_FALLBACK_BASE_URL` to a private Ollama service with `qwen2.5:7b` and `Modelfile.fallback` when a larger fallback is desired.
- `mix run --no-halt`
- Visit `http://localhost:4000`
- For Docker, set `OLLAMA_BASE_URL` to the static ngrok url

## Hetzner deployment

Ollama is installed on the Hetzner host rather than inside the application
Docker image. This keeps deployments small and lets Ollama retain its model
cache between releases.

On the Hetzner host:

```bash
curl -fsSL https://ollama.com/install.sh | sh
sudo mkdir -p /etc/systemd/system/ollama.service.d
sudo tee /etc/systemd/system/ollama.service.d/override.conf >/dev/null <<'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
EOF
sudo systemctl daemon-reload
sudo systemctl restart ollama
ollama pull qwen2.5:0.5b
ollama create ledger-small -f Modelfile.classifier
curl http://127.0.0.1:11434/api/generate \
  -d '{"model":"ledger-small","prompt":"Return JSON for COSTCO WHSE #1195","format":"json","stream":false}'
```

The deployed container reaches host Ollama through
`http://host.docker.internal:11434`; Kamal adds the Docker host-gateway
mapping in `config/deploy.yml`. Keep port 11434 restricted to the host/private
network. Ollama does not provide suitable authentication for an Internet-facing
endpoint.

The fallback host should use private networking or an authenticated reverse
proxy:

```bash
ollama pull qwen2.5:7b
ollama create ledger-fallback -f Modelfile.fallback
```

Set the corresponding `OLLAMA_FALLBACK_BASE_URL` GitHub/Kamal secret. The
application retries a complete classification request against this endpoint
when the small model is invalid or below
`CLASSIFIER_CONFIDENCE_THRESHOLD` (default `0.80`).

## CSV behavior

Comma- and tab-delimited exports are supported. Headers are matched by name,
including `Post Date`, `Posted Date`, `Posting Date`, `Transaction Date`,
`Description`, `Merchant`, `Payee`, `Memo`, `Amount`, `Debit`, `Credit`,
`Category`, and `Type`. Quoted commas and embedded newlines are parsed safely.

Known merchants use deterministic rules before Ollama is called. Payment,
return, adjustment, amount-sign, card-account, and balancing rules never come
from the model. Model classifications are restricted to the account allowlist
and invalid results fall back to `Expenses:Miscellaneous`.
