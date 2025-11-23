defmodule LocalLedger.Application do
  use Application

  def start(_type, _args) do
    dispatch = :cowboy_router.compile([
      {:_, [
        {"/ws", LocalLedger.BatchSocket, []},
        {:_, Plug.Cowboy.Handler, {LocalLedger.Router, []}}
      ]}
    ])

    children = [
      {Finch, name: LocalLedger.Finch},
      :ranch.child_spec(:http, :ranch_tcp, [port: 4000], :cowboy_clear, %{env: %{dispatch: dispatch}})
    ]

    opts = [strategy: :one_for_one, name: LocalLedger.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
