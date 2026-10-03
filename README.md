# Local Ledger

[Local Ledger](https://ledger.iacut.one): an application that parses your credit card csv data with the qwen2.5:7b LLM and outputs data in the Plain Text Accounting ([ledger](https://plaintextaccounting.org/)) format.

- the aim of this application is to use a local LLM in order to not expose sensitive financial data

## Dependencies

- [Ollama](https://ollama.com/)
- Elixir (via [asdf](https://asdf-vm.com/))
- [ledger-cli](https://ledger-cli.org/) (`brew install ledger` or `apt install ledger`)
- [ngrok](https://ngrok.com/) tunnel


## To Run

- `ollama pull qwen2.5:7b`
- `ollama create ledger -f Modelfile`
- `mix run --no-halt`
- Visit `http://localhost:4000`
- For Docker, set `OLLAMA_BASE_URL` to the static ngrok url

## ngrok

ngrok creates a public HTTPS tunnel to your local server, which is useful when running the app inside Docker (where `localhost` doesn't resolve to the host machine) or for sharing it over the internet.

**First-time setup** — set your authtoken (from [https://dashboard.ngrok.com/get-started/your-authtoken](https://dashboard.ngrok.com/get-started/your-authtoken)) as an environment variable:

```bash
export NGROK_AUTHTOKEN=<your-token>
```

Add that to your shell profile (`.zshrc`, etc.) so it persists. Make sure the ngrok config file (`~/Library/Application Support/ngrok/ngrok.yml` on macOS) does not have a hardcoded `authtoken` line, as it will override the env var.

**Start the tunnel** (the app must already be running on port 4000):

```bash
ngrok http 4000
```

ngrok will print a public URL like `https://abc123.ngrok-free.app`. Use that as the value of `OLLAMA_BASE_URL` when running via Docker:

```bash
docker run -e OLLAMA_BASE_URL=https://abc123.ngrok-free.app ...
```

You can also inspect live traffic at the ngrok web interface: [http://localhost:4040](http://localhost:4040).

## TODO

- write tests
- Fix Task timeout when chunking csv files
- run each csv row through a classifier to have more accurate categories
