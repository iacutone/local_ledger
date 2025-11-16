defmodule LocalLedger.OllamaClient do
  @moduledoc """
  Client for interacting with Ollama API with streaming support.
  """
  require Logger
  import Plug.Conn

  @base_url "http://localhost:11434"
  @ollama_model "ledger"

  def stream_to_conn(content, conn, _opts \\ []) do
    url = "#{@base_url}/api/generate"

    body =
      %{
        model: @ollama_model,
        prompt: content,
        stream: true
      }
      |> JSON.encode!()

    Logger.info("=== OLLAMA REQUEST ===")
    Logger.info("Model: #{@ollama_model}")
    Logger.info("URL: #{url}")
    Logger.info("Prompt length: #{String.length(content)} chars")
    Logger.info("Prompt preview: #{String.slice(content, 0, 200)}")

    headers = [
      {"content-type", "application/json"}
    ]

    # Conn is already set up for chunked streaming by the router
    stream_ollama_response(conn, url, headers, body)
  end

  defp stream_ollama_response(conn, url, headers, body) do
    parent = self()

    Logger.info("Starting Ollama stream request to #{url}")

    Task.start(fn ->
      try do
        Finch.build(:post, url, headers, body)
        |> Finch.stream(LocalLedger.Finch, "", fn
          {:status, status}, acc ->
            if status != 200 do
              send(parent, {:error, "HTTP #{status}"})
            end
            {:cont, acc}

          {:headers, _headers}, acc ->
            {:cont, acc}

          {:data, data}, acc ->
            # Ensure acc is a string
            acc_str = if is_binary(acc), do: acc, else: ""
            # Buffer incomplete JSON lines
            buffer = acc_str <> data
            lines = String.split(buffer, "\n")

            # Last element might be incomplete, keep it in buffer
            {complete_lines, new_buffer} =
              if length(lines) > 1 do
                {Enum.take(lines, length(lines) - 1), List.last(lines)}
              else
                {[], buffer}
              end

            # Process complete lines
            Enum.each(complete_lines, fn line ->
              if line != "" do
                case JSON.decode(line) do
                  {:ok, %{"response" => response, "done" => true}} when is_binary(response) ->
                    Logger.debug("Received final chunk with done=true: #{String.slice(response, 0, 50)}")
                    send(parent, {:chunk, response})
                    send(parent, {:done})

                  {:ok, %{"response" => response, "done" => false}} when is_binary(response) ->
                    send(parent, {:chunk, response})

                  {:ok, %{"response" => response}} when is_binary(response) ->
                    send(parent, {:chunk, response})

                  {:ok, %{"done" => true}} ->
                    Logger.debug("Received done=true without response")
                    send(parent, {:done})

                  {:ok, %{"error" => error}} ->
                    send(parent, {:error, inspect(error)})

                  {:error, decode_error} ->
                    Logger.debug("JSON decode error: #{inspect(decode_error)}")
                    :ok

                  _ ->
                    :ok
                end
              end
            end)

            {:cont, new_buffer}

          {:done, _}, acc ->
            # Ensure acc is a string
            acc_str = if is_binary(acc), do: acc, else: ""
            # Process any remaining buffer
            if acc_str != "" do
              case JSON.decode(acc_str) do
                {:ok, %{"response" => response}} when is_binary(response) ->
                  send(parent, {:chunk, response})
                _ -> :ok
              end
            end

            send(parent, {:done})
            {:cont, ""}

          {:error, error}, acc ->
            send(parent, {:error, inspect(error)})
            {:cont, acc}
        end)
      catch
        error ->
          send(parent, {:error, inspect(error)})
      end
    end)

    receive_stream(conn)
  end

  defp receive_stream(conn, buffer \\ "") do
    receive do
      {:chunk, content} ->
        Logger.info("Received chunk to send: #{String.length(content)} chars - #{String.slice(content, 0, 50)}...")
        # Accumulate content in buffer
        new_buffer = buffer <> content

        # Escape HTML to prevent breaking the page (but preserve formatting)
        escaped_content =
          content
          |> String.replace("&", "&amp;")
          |> String.replace("<", "&lt;")
          |> String.replace(">", "&gt;")

        # Send content with HTML escaping
        case chunk(conn, escaped_content) do
          {:ok, new_conn} ->
            Logger.debug("Chunk sent successfully")
            receive_stream(new_conn, new_buffer)
          {:error, _} = error ->
            Logger.error("Error sending chunk: #{inspect(error)}")
            error
        end

      {:done} ->
        Logger.info("Stream completed")
        conn

      {:error, error} ->
        Logger.error("Stream error: #{inspect(error)}")
        escaped_error =
          error
          |> inspect()
          |> String.replace("&", "&amp;")
          |> String.replace("<", "&lt;")
          |> String.replace(">", "&gt;")

        chunk(conn, "\n\nError: #{escaped_error}")
        conn

      {:DOWN, _ref, :process, _pid, reason} ->
        Logger.error("Task process died: #{inspect(reason)}")
        chunk(conn, "\n\nError: Task process died: #{inspect(reason)}")
        conn
    after
      # 5 minute timeout
      300_000 ->
        Logger.warning("Stream timeout after 5 minutes")
        conn
    end
  end

  def parse_csv_and_prepare_batches(csv_content) do
    # Split CSV into batches of 20 transactions
    lines = csv_content
    |> String.trim()
    |> String.split("\n")
    |> Enum.filter(&(&1 != ""))
    
    # Separate header and data
    {header, data_lines} = case lines do
      [h | rest] -> {h, rest}
      [] -> {"", []}
    end
    
    # Create batches of 20 with header
    batches = data_lines
    |> Enum.chunk_every(20)
    |> Enum.map(fn batch -> 
      [header | batch] |> Enum.join("\n")
    end)
    
    Logger.info("Split CSV into #{length(batches)} batches")
    Logger.info("Total transactions: #{length(data_lines)}")
    
    batches
  end
end
