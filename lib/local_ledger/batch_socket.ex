defmodule LocalLedger.BatchSocket do
  @behaviour :cowboy_websocket

  require Logger

  def init(req, state) do
    # Set a long idle timeout (10 minutes)
    {:cowboy_websocket, req, state, %{idle_timeout: 600_000}}
  end

  def websocket_init(state) do
    Logger.info("WebSocket connected")
    # Send periodic pings to keep connection alive
    :timer.send_interval(30_000, self(), :ping)
    {:ok, state}
  end

  def websocket_handle({:text, msg}, state) do
    case JSON.decode(msg) do
      {:ok, %{"action" => "process", "csv_content" => csv_content}} ->
        Logger.info("Starting batch processing (#{String.length(csv_content)} chars)")
        
        # Get WebSocket PID before spawning
        ws_pid = self()
        
        # Spawn a task to handle processing
        Task.start(fn ->
          try do
            # Prepare batches
            batches = LocalLedger.OllamaClient.parse_csv_and_prepare_batches(csv_content)
            
            Logger.info("Starting batch processing: #{length(batches)} batches")
            
            # Process each batch with streaming
            Enum.with_index(batches, 1)
            |> Enum.each(fn {batch, index} ->
              Logger.info("Processing batch #{index}/#{length(batches)}")
              
              # Send batch progress update
              send(ws_pid, {:batch_progress, index, length(batches)})
              
              if index > 1 do
                Process.sleep(2000)
                send(ws_pid, {:batch_separator})
              end
              
              # Stream this batch
              LocalLedger.OllamaClient.stream_batch_to_pid(batch, ws_pid)
              
              Logger.info("Batch #{index} complete")
            end)
            
            Logger.info("All batches completed, sending done")
            send(ws_pid, :processing_done)
            Logger.info("Sent done message")
          rescue
            e ->
              Logger.error("Error in batch processing task: #{inspect(e)}")
              Logger.error(Exception.format_stacktrace(__STACKTRACE__))
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
    Logger.info("Sending done message via WebSocket")
    msg = JSON.encode!(%{type: "done"})
    {:reply, {:text, msg}, state}
  end

  def websocket_info(:ping, state) do
    {:reply, :ping, state}
  end

  def websocket_info(info, state) do
    Logger.warning("Unexpected websocket_info: #{inspect(info)}")
    {:ok, state}
  end

  def terminate(reason, _req, _state) do
    Logger.info("WebSocket terminated: #{inspect(reason)}")
    :ok
  end
end
