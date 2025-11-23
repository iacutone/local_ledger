import Config

config :local_ledger,
  ollama_base_url: System.get_env("OLLAMA_BASE_URL", "http://localhost:11434")
