defmodule LocalLedger.BatchSocket do
  @behaviour :cowboy_websocket

  def init(req, state) do
    # Set a long idle timeout (10 minutes)
    {:cowboy_websocket, req, state, %{idle_timeout: 600_000}}
  end

  def websocket_init(_state) do
    :timer.send_interval(30_000, self(), :ping)
    {:ok, %{}}
  end

  def websocket_handle({:text, msg}, state) do
    case JSON.decode(msg) do
      {:ok, %{"action" => "process", "csv_content" => csv_content} = payload} ->
        {:ok,
         state
         |> Map.put(:pending_csv, csv_content)
         |> Map.put(:pending_filename, payload["filename"])}

      {:ok, %{"action" => "classify", "row_number" => row_number, "account" => account}} ->
        case Map.get(state, :worker_pid) do
          pid when is_pid(pid) ->
            send(pid, {:classification, row_number, account})
            {:ok, state}

          _ ->
            {:ok, state}
        end

      {:ok, %{"action" => "ready"}} ->
        case Map.get(state, :pending_csv) do
          nil ->
            {:ok, state}

          csv_content ->
            ws_pid = self()
            filename = Map.get(state, :pending_filename)

            uncertain = fn transaction, reason ->
              send(ws_pid, {:needs_classification, transaction, reason})

              receive do
                {:classification, row_number, account}
                when row_number == transaction.row_number ->
                  {:ok, %{account: account, confidence: 1.0}}

                {:classification_cancelled, row_number}
                when row_number == transaction.row_number ->
                  {:error, "Classification cancelled for CSV row #{row_number}."}
              after
                600_000 -> {:error, "Timed out waiting for a category for CSV row #{transaction.row_number}."}
              end
            end

            {:ok, worker_pid} =
              Task.start(fn ->
              try do
                progress = fn current, total ->
                  send(ws_pid, {:batch_progress, current, total})
                end

                case LocalLedger.Processor.process(csv_content, filename,
                       progress: progress,
                       uncertain: uncertain
                     ) do
                  {:ok, %{journal: journal}} ->
                    send(ws_pid, {:running_ledger})

                    case LocalLedger.LedgerCli.reports(journal) do
                      {:ok, reports} ->
                        send(ws_pid, {:report, reports, journal, LocalLedger.LedgerCli.download_name(journal, filename)})

                      {:error, message} ->
                        send(ws_pid, {:report_error, message, journal, LocalLedger.LedgerCli.download_name(journal, filename)})
                    end

                  {:error, message} ->
                    send(ws_pid, {:error, message})
                end
              rescue
                e ->
                  send(ws_pid, {:error, "An error occurred: #{Exception.message(e)}"})
              catch
                :timeout ->
                  :ok
              end
              end)

            {:ok,
             state
             |> Map.delete(:pending_csv)
             |> Map.delete(:pending_filename)
             |> Map.put(:worker_pid, worker_pid)}
        end

      _ ->
        {:ok, state}
    end
  end

  def websocket_handle(_frame, state) do
    {:ok, state}
  end

  def websocket_info({:batch_progress, current, total}, state) do
    msg = JSON.encode!(%{type: "progress", current: current, total: total})
    {:reply, {:text, msg}, state}
  end

  def websocket_info({:running_ledger}, state) do
    msg = JSON.encode!(%{type: "progress_message", message: "Running ledger…"})
    {:reply, {:text, msg}, state}
  end

  def websocket_info({:needs_classification, transaction, reason}, state) do
    {suggested_account, confidence} =
      case reason do
        {:low_confidence, result} ->
          {Map.get(result, :account), Map.get(result, :confidence)}

        _ ->
          {nil, nil}
      end

    msg =
      JSON.encode!(%{
        type: "needs_classification",
        row_number: transaction.row_number,
        description: transaction.description,
        bank_category: transaction.category,
        transaction_type: transaction.type,
        amount: transaction.amount,
        suggested_account: suggested_account,
        confidence: confidence,
        accounts: LocalLedger.TransactionClassifier.allowed_accounts()
      })

    {:reply, {:text, msg}, state}
  end

  def websocket_info({:report, reports, journal, download}, state) do
    msg =
      JSON.encode!(%{
        type: "report",
        balance: reports.balance,
        journal: journal,
        download: download
      })

    {:reply, {:text, msg}, state}
  end

  def websocket_info({:report_error, message, journal, download}, state) do
    msg =
      JSON.encode!(%{
        type: "report_error",
        message: message,
        journal: journal,
        download: download
      })

    {:reply, {:text, msg}, state}
  end

  def websocket_info({:retry, index, total, retries_left}, state) do
    msg = JSON.encode!(%{type: "progress", current: index, total: total, message: "Batch #{index} timed out, retrying (#{retries_left} left)..."})
    {:reply, {:text, msg}, state}
  end

  def websocket_info({:error, message}, state) do
    msg = JSON.encode!(%{type: "error", message: message})
    {:reply, {:text, msg}, state}
  end

  def websocket_info(:ping, state) do
    {:reply, :ping, state}
  end

  def websocket_info(_info, state) do
    {:ok, state}
  end

  def terminate(_reason, _req, _state) do
    :ok
  end

  defp generate_with_retry(prompt, retries_left, ws_pid, index, total) do
    result = LocalLedger.OllamaClient.generate(prompt)

    if result == "" and retries_left > 0 do
      send(ws_pid, {:retry, index, total, retries_left})
      Process.sleep(5_000)
      generate_with_retry(prompt, retries_left - 1, ws_pid, index, total)
    else
      result
    end
  end
end
