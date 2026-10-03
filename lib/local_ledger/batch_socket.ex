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

      {:ok, %{"action" => "ready"}} ->
        case Map.get(state, :pending_csv) do
          nil ->
            {:ok, state}

          csv_content ->
            ws_pid = self()
            filename = Map.get(state, :pending_filename)

            Task.start(fn ->
              try do
                progress = fn current, total ->
                  send(ws_pid, {:batch_progress, current, total})
                end

                case LocalLedger.Processor.process(csv_content, filename, progress: progress) do
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
                _e ->
                  send(ws_pid, {:error, "An error occurred during processing. Please try again."})
              catch
                :timeout ->
                  :ok
              end
            end)

            {:ok, state |> Map.delete(:pending_csv) |> Map.delete(:pending_filename)}
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

  def websocket_info({:report, reports, journal, download}, state) do
    msg =
      JSON.encode!(%{
        type: "report",
        balance: reports.balance,
        register: reports.register,
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
end
