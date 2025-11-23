# Local Ledger

[Local Ledger](https://ledger.iacut.one): an application that parses your credit card csv data with the qwen2.5:7b LLM and outputs data in the Plain Text Accounting ([ledger](https://plaintextaccounting.org/)) format.

- the aim of this application is to use a local LLM in order to not expose sensitive financial data

## Dependencies

- [Ollama](https://ollama.com/))
- Elixir (via [asdf](https://asdf-vm.com/))
- [ngrok](https://ngrok.com/) tunnel


## To Run

- `ollama pull qwen2.5:7b`
- `ollama create ledger -f Modelfile`
- `mix run --no-halt`
- Visit `http://localhost:4000`
- For Docker, set `OLLAMA_BASE_URL` to the static ngrok url

## TODO

- write tests
- Fix Task timeout when chunking csv files
- run each csv row through a classifier to have more accurate categories
