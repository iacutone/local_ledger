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
        # Read CSV content once
        csv_content = File.read!(path)

        html = """
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
            .status { color: #858585; margin: 1rem 0; }
            a { color: #4ec9b0; text-decoration: none; }
            a:hover { text-decoration: underline; }
          </style>
        </head>
        <body>
          <h1>Ledger Conversion Results</h1>
          <a href="/">← Upload Another File</a>
          <div class="status" id="status">Connecting...</div>
          <div class="response" id="response"></div>
          
          <script>
            const ws = new WebSocket('ws://' + window.location.host + '/ws');
            const response = document.getElementById('response');
            const status = document.getElementById('status');
            
            ws.onopen = () => {
              console.log('WebSocket connected');
              status.textContent = 'Processing batches...';
              ws.send(JSON.stringify({action: 'process', csv_content: #{JSON.encode!(csv_content)}}));
            };
            
            ws.onmessage = (event) => {
              const data = JSON.parse(event.data);
              if (data.type === 'chunk') {
                response.textContent += data.text;
              } else if (data.type === 'progress') {
                status.textContent = 'Processing batch ' + data.current + ' of ' + data.total + '...';
              } else if (data.type === 'done') {
                console.log('All done');
                status.textContent = 'All batches completed!';
                ws.close();
              }
            };
            
            ws.onerror = (error) => {
              console.error('WebSocket error:', error);
              status.textContent = 'Error: ' + error;
            };
            
            ws.onclose = (event) => {
              console.log('WebSocket closed:', event.code, event.reason);
            };
          </script>
        </body>
        </html>
        """

        send_resp(conn, 200, html)

      _ ->
        send_resp(conn, 400, "No file uploaded")
    end
  end

  match _ do
    send_resp(conn, 404, "Not Found")
  end
end
