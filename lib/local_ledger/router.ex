defmodule LocalLedger.Router do
  use Plug.Router
  import Plug.Conn
  alias LocalLedger.Render

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart],
    length: 10_000_000
  )

  plug(Plug.Static, from: :local_ledger, at: "/")
  plug(:match)
  plug(:dispatch)

  get "/" do
    html = Render.render("index.html.eex")
    send_resp(conn, 200, html)
  end

  match _ do
    send_resp(conn, 404, "Not Found")
  end
end
