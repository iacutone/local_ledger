# Local Ledger

[Local Ledger](https://ledger.iacut.one): an application that parses credit-card CSV data with NimbleCSV, classifies merchants locally, and outputs Plain Text Accounting ([ledger](https://plaintextaccounting.org/)) format.

- CSV parsing, transaction types, balancing, and ledger generation are deterministic Elixir code.
- Unknown merchants are classified by Ollama's local `laya` decision model. When it cannot classify confidently, processing pauses for a user-selected account.
- Financial data is sent only to the configured Ollama endpoints.

## Dependencies

- [Ollama](https://ollama.com/)
- Elixir (via [asdf](https://asdf-vm.com/))
- [ledger-cli](https://ledger-cli.org/) (`brew install ledger` or `apt install ledger`)


## To Run

- `ollama pull laya`
- Configure `OLLAMA_BASE_URL` to the host Ollama service.
- `mix run --no-halt`
- Visit `http://localhost:4000`
- For Docker, set `OLLAMA_BASE_URL` to the Ollama host URL.

## ngrok

ngrok creates a public HTTPS tunnel to your local server, which is useful when running the app inside Docker (where `localhost` doesn't resolve to the host machine) or for sharing it over the internet.

**First-time setup** — set your authtoken (from [https://dashboard.ngrok.com/get-started/your-authtoken](https://dashboard.ngrok.com/get-started/your-authtoken)) as an environment variable:

```bash
export NGROK_AUTHTOKEN=<your-token>
```

Add that to your shell profile (`.zshrc`, etc.) so it persists. Make sure the ngrok config file (`~/Library/Application Support/ngrok/ngrok.yml` on macOS) does not have a hardcoded `authtoken` line, as it will override the env var.

**Start the tunnel** pointing at Ollama (port 11434) using the permanent domain:

```bash
ngrok http --url=$NGROK_BASE_URL 11434
```

Set `OLLAMA_BASE_URL` to the permanent domain when running via Docker:

```bash
docker run -e OLLAMA_BASE_URL=https://$NGROK_BASE_URL ...
```

Using the permanent domain means `OLLAMA_BASE_URL` never needs updating after a restart.

You can also inspect live traffic at the ngrok web interface: [http://localhost:4040](http://localhost:4040).

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
ollama pull laya
curl http://127.0.0.1:11434/v1/systemone \
  -H 'Content-Type: application/json' \
  -d '{"model":"laya","state":{"description":"COSTCO WHSE #1195","bank_category":"Shopping","type":"Sale","amount":"-173.61"},"questions":{"group":{"type":"choice","instructions":"Which broad spending group best fits this transaction?","criteria":{"food":"groceries or restaurants","shopping":"general retail","other":"anything else"}}}}'
```

The deployed container reaches host Ollama through
`http://host.docker.internal:11434`; Kamal adds the Docker host-gateway
mapping in `config/deploy.yml`. Keep port 11434 restricted to the host/private
network. Ollama does not provide suitable authentication for an Internet-facing
endpoint. Laya requires Ollama 0.40.0 or newer.

When the model is invalid or below `CLASSIFIER_CONFIDENCE_THRESHOLD` (default
`0.80`), the browser asks for an account before processing continues.
Corrections are appended to `/data/classification_feedback.jsonl` on the
mounted Hetzner volume. Records contain the merchant description, bank
category, type, amount, model prediction, confidence, corrected account, and
timestamp; dates and card identifiers are excluded.

The uncertainty form also accepts a proposed new ledger account and parent
group. Proposals are appended to
`/data/category_proposals.jsonl` with a `pending` status, but they are not
used for the current transaction and do not change the active classifier
allowlist. Review and approve proposals separately before adding them to the
account taxonomy. Set `CATEGORY_PROPOSAL_PATH` to override the proposal
storage path.

## CSV behavior

Comma- and tab-delimited exports are supported. Headers are matched by name,
including `Post Date`, `Posted Date`, `Posting Date`, `Transaction Date`,
`Description`, `Merchant`, `Payee`, `Memo`, `Amount`, `Debit`, `Credit`,
`Category`, and `Type`. Quoted commas and embedded newlines are parsed safely.

Known merchants use deterministic rules before Ollama is called. Payment,
return, adjustment, amount-sign, card-account, and balancing rules never come
from the model. Laya classifies broad groups and then leaf accounts because a
single choice question should stay below its option limit. Model
classifications and user corrections are restricted to the account allowlist.
New category proposals are intentionally restricted to valid ledger account
names and existing parent groups, but remain inactive until approved.
