defmodule LocalLedger.OllamaClient do
  @moduledoc """
  Client for interacting with Ollama API with streaming support.
  """

  @ollama_model "ledger"

  defp base_url do
    Application.get_env(:local_ledger, :ollama_base_url, "http://localhost:11434")
  end

  def stream_batch_to_pid(content, pid) do
    url = "#{base_url()}/api/generate"

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

  def stream_batch_to_conn(content, conn) do
    url = "#{base_url()}/api/generate"

    body = JSON.encode!(%{
      model: @ollama_model,
      prompt: content,
      stream: true
    })

    headers = [{"content-type", "application/json"}]

    result = Finch.build(:post, url, headers, body)
    |> Finch.stream(LocalLedger.Finch, {conn, ""}, fn
      {:data, data}, {conn_acc, buffer} ->
        new_buffer = buffer <> data
        lines = String.split(new_buffer, "\n")

        {complete_lines, remaining} =
          if length(lines) > 1 do
            {Enum.take(lines, length(lines) - 1), List.last(lines)}
          else
            {[], new_buffer}
          end

        final_conn = Enum.reduce(complete_lines, conn_acc, fn line, acc_conn ->
          if line != "" do
            case JSON.decode(line) do
              {:ok, %{"response" => resp}} when is_binary(resp) ->
                case Plug.Conn.chunk(acc_conn, resp) do
                  {:ok, new_conn} -> new_conn
                  {:error, _reason} ->
                    acc_conn
                end
              _ -> acc_conn
            end
          else
            acc_conn
          end
        end)

        {final_conn, remaining}

      _, {conn_acc, buffer} -> {conn_acc, buffer}
    end)

    case result do
      {:ok, {final_conn, _buffer}} -> 
        final_conn
      {:error, _reason} -> 
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

    data_lines
    |> Enum.chunk_every(10)
    |> Enum.map(fn batch -> [header | batch] |> Enum.join("\n") end)
  end

  @doc """
  Stream CSV file and prepare batches without loading entire file into memory.
  Returns a stream of batches (each batch is a string with header + 10 rows).
  """
  def stream_csv_batches(file_path, batch_size \\ 10) do
    lines = 
      file_path
      |> File.stream!()
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 == ""))
      |> Enum.to_list()
    
    case lines do
      [header | data_lines] ->
        data_lines
        |> Stream.chunk_every(batch_size)
        |> Stream.map(fn batch -> 
          [header | batch] |> Enum.join("\n")
        end)
      
      [] ->
        []
    end
  end
end
