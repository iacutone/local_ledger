defmodule LocalLedger.Router do
  use Plug.Router
  import Plug.Conn
  alias LocalLedger.Render
  alias LocalLedger.OllamaClient

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
        csv_content = File.read!(path)
        batches = OllamaClient.parse_csv_and_prepare_batches(csv_content)

        # Send initial HTML structure
        html_start = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8" />
          <title>Ledger Conversion Results</title>
          <style>
            body { font-family: sans-serif; padding: 2rem; max-width: 1200px; margin: 0 auto; background: #1e1e1e; color: #d4d4d4; }
            h1 { color: #4ec9b0; }
            .response { 
              white-space: pre; 
              background: #252526; 
              padding: 1.5rem; 
              border-radius: 8px; 
              margin-top: 1rem; 
              font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
              font-size: 14px;
              line-height: 1.6;
              overflow-x: auto;
              border: 1px solid #3e3e42;
            }
            .loading { color: #858585; }
            .batch-separator { color: #666; margin: 1rem 0; }
            a { color: #4ec9b0; text-decoration: none; }
            a:hover { text-decoration: underline; }
          </style>
        </head>
        <body>
          <h1>Ledger Conversion Results</h1>
          <a href="/">← Upload Another File</a>
          <p class="loading">Processing #{length(batches)} batches...</p>
          <div class="response" id="response">
        """

        conn
        |> put_resp_header("content-type", "text/html; charset=utf-8")
        |> put_resp_header("transfer-encoding", "chunked")
        |> send_chunked(200)
        |> then(fn conn ->
          {:ok, conn} = chunk(conn, html_start)
          
          # Process each batch sequentially
          final_conn = Enum.with_index(batches, 1)
          |> Enum.reduce(conn, fn {batch, index}, acc_conn ->
            require Logger
            Logger.info("Processing batch #{index}/#{length(batches)}")
            
            result_conn = OllamaClient.stream_to_conn(batch, acc_conn)
            
            Logger.info("Completed batch #{index}/#{length(batches)}")
            result_conn
          end)
          
          final_conn
        end)
        |> then(fn conn ->
          html_end = """
            </div>
          </body>
          </html>
          """
          case chunk(conn, html_end) do
            {:ok, conn} -> conn
            {:error, _} = error -> error
          end
        end)

      _ ->
        send_resp(conn, 400, "No file uploaded")
    end
  end

  match _ do
    send_resp(conn, 404, "Not Found")
  end
end
