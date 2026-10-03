import Config

ollama_base_url =
  case {System.get_env("OLLAMA_BASE_URL"), config_env()} do
    {nil, :prod} -> raise "OLLAMA_BASE_URL must be configured in production"
    {nil, _env} -> "http://localhost:11434"
    {value, _env} -> value
  end

config :local_ledger,
  ollama_base_url: ollama_base_url,
  ollama_fallback_base_url: System.get_env("OLLAMA_FALLBACK_BASE_URL"),
  ollama_primary_model: System.get_env("OLLAMA_PRIMARY_MODEL", "ledger-small"),
  ollama_fallback_model: System.get_env("OLLAMA_FALLBACK_MODEL", "ledger-fallback"),
  classifier_confidence_threshold:
    System.get_env("CLASSIFIER_CONFIDENCE_THRESHOLD", "0.80") |> String.to_float(),
  ollama_timeout: System.get_env("OLLAMA_TIMEOUT", "120000") |> String.to_integer(),
  ledger_bin: System.get_env("LEDGER_BIN", "ledger")
