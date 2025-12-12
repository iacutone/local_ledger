defmodule LocalLedger.BatchSocket do
  @behaviour :cowboy_websocket

  def init(req, state) do
    # Set a long idle timeout (10 minutes)
    {:cowboy_websocket, req, state, %{idle_timeout: 600_000}}
  end

  def websocket_init(_state) do
    # Send periodic pings to keep connection alive
    :timer.send_interval(30_000, self(), :ping)
    {:ok, %{chunks_received: false}}
  end

  def websocket_handle({:text, msg}, state) do
    case JSON.decode(msg) do
      {:ok, %{"action" => "process", "csv_content" => csv_content}} ->
        {:ok, Map.put(state, :pending_csv, csv_content)}

      {:ok, %{"action" => "ready"}} ->
        case Map.get(state, :pending_csv) do
          nil ->
            {:ok, state}

          csv_content ->
            ws_pid = self()

            Task.start(fn ->
              try do
                batches = LocalLedger.OllamaClient.parse_csv_and_prepare_batches(csv_content)

                total_batches = length(batches)
                
                Enum.with_index(batches, 1)
                |> Enum.each(fn {batch, index} ->
                  send(ws_pid, {:batch_progress, index, total_batches})

                  if index > 1 do
                    Process.sleep(2000)
                    send(ws_pid, {:batch_separator})
                  end

                  # Call directly - streaming sends chunks as they arrive
                  LocalLedger.OllamaClient.stream_batch_to_pid(batch, ws_pid)
                end)

                send(ws_pid, :processing_done)
              rescue
                _e ->
                  send(ws_pid, {:error, "An error occurred during processing. Please try again."})
              catch
                :timeout ->
                  :ok
              end
            end)

            {:ok, Map.delete(state, :pending_csv)}
        end

      _ ->
        {:ok, state}
    end
  end

  def websocket_handle(_frame, state) do
    {:ok, state}
  end

  def websocket_info({:chunk, text}, state) when text != "" do
    msg = JSON.encode!(%{type: "chunk", text: text})
    {:reply, {:text, msg}, %{state | chunks_received: true}}
  end

  def websocket_info({:chunk, ""}, state) do
    # Ignore empty chunks
    {:ok, state}
  end

  def websocket_info({:batch_separator}, state) do
    msg = JSON.encode!(%{type: "chunk", text: "\n\n"})
    {:reply, {:text, msg}, state}
  end

  def websocket_info({:batch_progress, current, total}, state) do
    msg = JSON.encode!(%{type: "progress", current: current, total: total})
    {:reply, {:text, msg}, state}
  end

  def websocket_info(:processing_done, state) do
    if state.chunks_received do
      msg = JSON.encode!(%{type: "done"})
      {:reply, {:text, msg}, %{state | chunks_received: false}}
    else
      msg =
        JSON.encode!(%{
          type: "error",
          message:
            "The AI model returned no data. It may be warming up - please try again in a few seconds."
        })

      {:reply, {:text, msg}, state}
    end
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
