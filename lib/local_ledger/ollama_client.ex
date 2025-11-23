defmodule LocalLedger.OllamaClient do
  @moduledoc """
  Client for interacting with Ollama API with streaming support.
  """
  require Logger
  import Plug.Conn

  @base_url "http://localhost:11434"
  @ollama_model "ledger"

  def stream_batch_to_pid(content, pid) do
    url = "#{@base_url}/api/generate"

    body = JSON.encode!(%{
      model: @ollama_model,
      prompt: content,
      stream: true
    })

    headers = [{"content-type", "application/json"}]

    Finch.build(:post, url, headers, body)
    |> Finch.stream(LocalLedger.Finch, "", fn
      {:data, data}, buffer ->
        new_buffer = buffer <> data
        lines = String.split(new_buffer, "\n")

        {complete_lines, remaining} =
          if length(lines) > 1 do
            {Enum.take(lines, length(lines) - 1), List.last(lines)}
          else
            {[], new_buffer}
          end

        Enum.each(complete_lines, fn line ->
          if line != "" do
            case JSON.decode(line) do
              {:ok, %{"response" => resp}} when is_binary(resp) ->
                send(pid, {:chunk, resp})
              _ -> :ok
            end
          end
        end)

        remaining

      _, buffer -> buffer
    end)
  end

  def process_batch_sync(content) do
    url = "#{@base_url}/api/generate"

    body = JSON.encode!(%{
      model: @ollama_model,
      prompt: content,
      stream: false
    })

    headers = [{"content-type", "application/json"}]

    case Finch.build(:post, url, headers, body)
    |> Finch.request(LocalLedger.Finch, receive_timeout: :infinity) do
      {:ok, %{status: 200, body: response_body}} ->
        case JSON.decode(response_body) do
          {:ok, %{"response" => response}} -> response
          _ -> "[Error: Invalid response]"
        end
      {:error, error} ->
        Logger.error("Finch error: #{inspect(error)}")
        "[Error: Request failed]"
    end
  end

  def stream_to_conn(content, conn, _opts \\ []) do
    url = "#{@base_url}/api/generate"

    body =
      JSON.encode!(%{
        model: @ollama_model,
        prompt: content,
        stream: true
      })

    Logger.info("=== OLLAMA REQUEST ===")
    Logger.info("Model: #{@ollama_model}")
    Logger.info("Prompt length: #{String.length(content)} chars")

    headers = [{"content-type", "application/json"}]
    stream_ollama_response(conn, url, headers, body)
  end

  defp stream_ollama_response(conn, url, headers, body) do
    Logger.info("Starting Ollama stream")

    result =
      Finch.build(:post, url, headers, body)
      |> Finch.stream(LocalLedger.Finch, {conn, ""}, fn
        {:status, status}, {acc_conn, buffer} ->
          if status != 200, do: Logger.error("HTTP #{status}")
          {acc_conn, buffer}

        {:headers, _}, {acc_conn, buffer} ->
          {acc_conn, buffer}

        {:data, data}, {acc_conn, buffer} ->
          new_buffer = buffer <> data
          lines = String.split(new_buffer, "\n")

          {complete_lines, remaining} =
            if length(lines) > 1 do
              {Enum.take(lines, length(lines) - 1), List.last(lines)}
            else
              {[], new_buffer}
            end

          result_conn =
            Enum.reduce(complete_lines, acc_conn, fn line, conn_acc ->
              if line != "" do
                case JSON.decode(line) do
                  {:ok, %{"response" => resp}} when is_binary(resp) ->
                    escaped =
                      resp
                      |> String.replace("&", "&amp;")
                      |> String.replace("<", "&lt;")
                      |> String.replace(">", "&gt;")

                    case chunk(conn_acc, escaped) do
                      {:ok, new_conn} -> new_conn
                      {:error, _} -> conn_acc
                    end

                  _ ->
                    conn_acc
                end
              else
                conn_acc
              end
            end)

          {result_conn, remaining}

        {:done, _}, {acc_conn, buffer} ->
          final_conn =
            if buffer != "" do
              case JSON.decode(buffer) do
                {:ok, %{"response" => resp}} when is_binary(resp) ->
                  escaped =
                    resp
                    |> String.replace("&", "&amp;")
                    |> String.replace("<", "&lt;")
                    |> String.replace(">", "&gt;")

                  case chunk(acc_conn, escaped) do
                    {:ok, new_conn} -> new_conn
                    {:error, _} -> acc_conn
                  end

                _ ->
                  acc_conn
              end
            else
              acc_conn
            end

          {final_conn, ""}

        {:error, error}, {acc_conn, buffer} ->
          Logger.error("Stream error: #{inspect(error)}")
          {acc_conn, buffer}
      end)

    case result do
      {:ok, {final_conn, _}} ->
        Logger.info("Stream completed")
        final_conn

      {:error, %Mint.TransportError{reason: :timeout}, {partial_conn, _}} ->
        Logger.error("Request timeout")
        chunk(partial_conn, "\n\n[Timeout]")
        partial_conn

      {:error, error, {partial_conn, _}} ->
        Logger.error("Finch error: #{inspect(error)}")
        chunk(partial_conn, "\n\n[Error]")
        partial_conn

      {:error, error} ->
        Logger.error("Finch error: #{inspect(error)}")
        chunk(conn, "\n\n[Error]")
        conn
    end
  end

  def parse_csv_and_prepare_batches(csv_content) do
    lines =
      csv_content
      |> String.trim()
      |> String.split("\n")
      |> Enum.filter(&(&1 != ""))

    {header, data_lines} =
      case lines do
        [h | rest] -> {h, rest}
        [] -> {"", []}
      end

    batches =
      data_lines
      |> Enum.chunk_every(20)
      |> Enum.map(fn batch -> [header | batch] |> Enum.join("\n") end)

    Logger.info("Split into #{length(batches)} batches (#{length(data_lines)} transactions)")
    batches
  end
end
