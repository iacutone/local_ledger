defmodule LocalLedger.Application do
  use Application

  def start(_type, _args) do
    children = [
      {Finch, name: LocalLedger.Finch},
      {Plug.Cowboy, scheme: :http, plug: LocalLedger.Router, options: [port: 4000]}
    ]

    opts = [strategy: :one_for_one, name: LocalLedger.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
