defmodule LocalLedger.BatchSocket do
  @behaviour :cowboy_websocket

  def init(req, state) do
    # Set a long idle timeout (10 minutes)
    {:cowboy_websocket, req, state, %{idle_timeout: 600_000}}
  end

  def websocket_init(state) do
    # Send periodic pings to keep connection alive
    :timer.send_interval(30_000, self(), :ping)
    {:ok, state}
  end

  def websocket_handle({:text, msg}, state) do
    case JSON.decode(msg) do
      {:ok, %{"action" => "process", "csv_content" => csv_content}} ->
        # Get WebSocket PID before spawning
        ws_pid = self()
        
        # Spawn a task to handle processing
        Task.start(fn ->
          try do
            # Parse CSV content to get batches
            batches = LocalLedger.OllamaClient.parse_csv_and_prepare_batches(csv_content)
            
            Enum.with_index(batches, 1)
            |> Enum.each(fn {batch, index} ->
              send(ws_pid, {:batch_progress, index, length(batches)})
              
              if index > 1 do
                Process.sleep(2000)
                send(ws_pid, {:batch_separator})
              end
              
              # Process batch with timeout
              task = Task.async(fn ->
                LocalLedger.OllamaClient.stream_batch_to_pid(batch, ws_pid)
              end)
              
              case Task.yield(task, 30_000) || Task.shutdown(task) do
                {:ok, _result} ->
                  :ok
                nil ->
                  send(ws_pid, {:error, "Ollama server not responding. Please try again later."})
                  throw(:timeout)
              end
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
        
        {:ok, state}
      
      _ ->
        {:ok, state}
    end
  end

  def websocket_handle(_frame, state) do
    {:ok, state}
  end

  def websocket_info({:chunk, text}, state) do
    msg = JSON.encode!(%{type: "chunk", text: text})
    {:reply, {:text, msg}, state}
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
    msg = JSON.encode!(%{type: "done"})
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
