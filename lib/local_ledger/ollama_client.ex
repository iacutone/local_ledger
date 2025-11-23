defmodule LocalLedger.OllamaClient do
  @moduledoc """
  Client for interacting with Ollama API with streaming support.
  """
  require Logger

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
      |> Enum.chunk_every(10)
      |> Enum.map(fn batch -> [header | batch] |> Enum.join("\n") end)

    Logger.info("Split into #{length(batches)} batches (#{length(data_lines)} transactions)")
    batches
  end
end
