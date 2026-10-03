defmodule LocalLedger.OllamaClient do
  @moduledoc """
  Client for interacting with Ollama API with streaming support.
  """

  @ollama_model "ledger"

  defp base_url do
    Application.get_env(:local_ledger, :ollama_base_url, "http://localhost:11434")
  end

  def generate(content) do
    url = "#{base_url()}/api/generate"

    body =
      JSON.encode!(%{
        model: @ollama_model,
        prompt: content,
        stream: true
      })

    headers = [{"content-type", "application/json"}]

    result =
      Finch.build(:post, url, headers, body)
      |> Finch.stream(LocalLedger.Finch, %{buffer: "", collected: ""}, fn
        {:data, data}, acc ->
          new_buffer = acc.buffer <> data
          lines = String.split(new_buffer, "\n")

          {complete_lines, remaining} =
            if length(lines) > 1 do
              {Enum.take(lines, length(lines) - 1), List.last(lines)}
            else
              {[], new_buffer}
            end

          collected =
            Enum.reduce(complete_lines, acc.collected, fn line, col ->
              case decode_response(line) do
                {:ok, resp} -> col <> resp
                :skip -> col
              end
            end)

          %{buffer: remaining, collected: collected}

        _, acc ->
          acc
      end)

    case result do
      {:ok, acc} ->
        case decode_response(acc.buffer) do
          {:ok, resp} -> acc.collected <> resp
          :skip -> acc.collected
        end

      {:error, _reason} ->
        ""
    end
  end

  defp decode_response(""), do: :skip

  defp decode_response(line) do
    case JSON.decode(line) do
      {:ok, %{"response" => resp}} when is_binary(resp) and resp != "" -> {:ok, resp}
      _ -> :skip
    end
  end

  def stream_batch_to_pid(content, pid) do
    url = "#{base_url()}/api/generate"

    body = JSON.encode!(%{
      model: @ollama_model,
      prompt: content,
      stream: true
    })

    headers = [{"content-type", "application/json"}]

    result = Finch.build(:post, url, headers, body)
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
              {:ok, %{"response" => resp, "done" => false}} when is_binary(resp) and resp != "" ->
                send(pid, {:chunk, resp})
              {:ok, %{"response" => resp}} when is_binary(resp) and resp != "" ->
                send(pid, {:chunk, resp})
              _ -> :ok
            end
          end
        end)

        remaining

      _, buffer -> buffer
    end)

    # Process any remaining buffer content
    case result do
      {:ok, remaining_buffer} when remaining_buffer != "" ->
        case JSON.decode(remaining_buffer) do
          {:ok, %{"response" => resp}} when is_binary(resp) ->
            send(pid, {:chunk, resp})
          _ -> :ok
        end
      _ -> :ok
    end
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

  @doc """
  Classifies one transaction with the small model and retries the complete
  request against the configured fallback model when the answer is uncertain.
  """
  def classify(transaction, opts \\ []) do
    threshold =
      Keyword.get(
        opts,
        :confidence_threshold,
        Application.get_env(:local_ledger, :classifier_confidence_threshold, 0.80)
      )

    primary =
      classify_with_model(
        transaction,
        Keyword.get(opts, :base_url, primary_base_url()),
        Keyword.get(opts, :model, primary_model()),
        opts
      )

    case primary do
      {:ok, result} when result.confidence >= threshold ->
        {:ok, Map.put(result, :source, :small_model)}

      _ ->
        case Keyword.get(opts, :fallback_base_url, fallback_base_url()) do
          nil ->
            {:ok,
             %{
               account: "Expenses:Miscellaneous",
               confidence: 0.0,
               source: :safe_fallback
             }}

          fallback_url ->
            case classify_with_model(
                   transaction,
                   fallback_url,
                   Keyword.get(opts, :fallback_model, fallback_model()),
                   opts
                 ) do
              {:ok, result} -> {:ok, Map.put(result, :source, :fallback_model)}
              {:error, _reason} -> safe_classification()
            end
        end
    end
  end

  defp classify_with_model(transaction, base_url, model, opts) when is_binary(base_url) do
    timeout = Keyword.get(opts, :timeout, classifier_timeout())
    prompt = LocalLedger.TransactionClassifier.prompt(transaction)

    body =
      JSON.encode!(%{
        model: model,
        prompt: prompt,
        stream: false,
        format: "json",
        options: %{temperature: 0, num_predict: 80}
      })

    request = Finch.build(:post, "#{String.trim_trailing(base_url, "/")}/api/generate", [{"content-type", "application/json"}], body)

    request_result =
      case Keyword.get(opts, :request_fun) do
        fun when is_function(fun, 4) -> fun.(base_url, model, body, timeout)
        _ -> Finch.request(request, LocalLedger.Finch, receive_timeout: timeout)
      end

    with {:ok, response} <- request_result,
         true <- response.status in 200..299,
         {:ok, payload} <- JSON.decode(response.body),
         {:ok, result} <- parse_classification(payload) do
      {:ok, result}
    else
      false -> {:error, "Ollama returned a non-success response."}
      {:error, reason} -> {:error, inspect(reason)}
      _ -> {:error, "Ollama returned invalid classification JSON."}
    end
  end

  defp classify_with_model(_transaction, _base_url, _model, _opts),
    do: {:error, "No Ollama URL is configured."}

  defp parse_classification(%{"response" => response}) when is_binary(response) do
    with {:ok, decoded} <- JSON.decode(response),
         account when is_binary(account) <- Map.get(decoded, "account"),
         confidence when is_number(confidence) <- Map.get(decoded, "confidence"),
         true <- account in LocalLedger.TransactionClassifier.allowed_accounts(),
         true <- confidence >= 0.0 and confidence <= 1.0 do
      {:ok, %{account: account, confidence: confidence * 1.0}}
    else
      _ -> {:error, "The classification was not an allowed account and confidence pair."}
    end
  end

  defp parse_classification(_), do: {:error, "Ollama returned no classification."}

  defp safe_classification do
    {:ok, %{account: "Expenses:Miscellaneous", confidence: 0.0, source: :safe_fallback}}
  end

  defp primary_base_url do
    Application.get_env(:local_ledger, :ollama_base_url, "http://localhost:11434")
  end

  defp fallback_base_url do
    case Application.get_env(:local_ledger, :ollama_fallback_base_url) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp primary_model, do: Application.get_env(:local_ledger, :ollama_primary_model, "ledger-small")
  defp fallback_model, do: Application.get_env(:local_ledger, :ollama_fallback_model, "ledger-fallback")
  defp classifier_timeout, do: Application.get_env(:local_ledger, :ollama_timeout, 120_000)
end
