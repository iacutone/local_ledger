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

  post "/upload" do
    case conn.params do
      %{"csv_file" => %Plug.Upload{path: path}} ->
        batches = LocalLedger.OllamaClient.stream_csv_batches(path) |> Enum.to_list()

        html_start = Render.render("results_start.html.eex", batch_count: length(batches))
        html_end = Render.render("results_end.html.eex")

        conn
        |> put_resp_header("content-type", "text/html; charset=utf-8")
        |> put_resp_header("transfer-encoding", "chunked")
        |> send_chunked(200)
        |> then(fn conn ->
          {:ok, conn} = chunk(conn, html_start)
          
          # Process batches and stream directly
          final_conn = Enum.with_index(batches, 1)
          |> Enum.reduce(conn, fn {batch, index}, acc_conn ->
            if index > 1 do
              Process.sleep(2000)
              {:ok, conn_with_sep} = chunk(acc_conn, "\n\n")
              conn_with_sep
            else
              acc_conn
            end
            |> then(fn c ->
              LocalLedger.OllamaClient.stream_batch_to_conn(batch, c)
            end)
          end)
          
          {:ok, conn} = chunk(final_conn, html_end)
          conn
        end)

      _ ->
        send_resp(conn, 400, "No file uploaded")
    end
  end

  match _ do
    send_resp(conn, 404, "Not Found")
  end
end
