defmodule LocalLedger.MerchantMemory do
  @moduledoc """
  Remembers user-corrected merchant → account mappings across sessions.

  On startup, loads past corrections from the feedback JSONL file and builds
  an in-memory lookup keyed by normalized description. When the classifier
  encounters a description that was previously corrected, it uses the stored
  account deterministically instead of hitting the model.
  """

  use GenServer

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns the corrected account for a description, or nil if unknown."
  @spec lookup(String.t()) :: String.t() | nil
  def lookup(description) when is_binary(description) do
    GenServer.call(__MODULE__, {:lookup, normalize(description)})
  end

  @doc "Stores a user correction for a description."
  @spec add(String.t(), String.t()) :: :ok
  def add(description, account) when is_binary(description) and is_binary(account) do
    GenServer.cast(__MODULE__, {:add, normalize(description), account})
  end

  # --- GenServer callbacks ---

  @impl true
  def init(_opts) do
    {:ok, load_from_feedback()}
  end

  @impl true
  def handle_call({:lookup, key}, _from, state) do
    {:reply, Map.get(state, key), state}
  end

  @impl true
  def handle_cast({:add, key, account}, state) do
    {:noreply, Map.put(state, key, account)}
  end

  # --- Private helpers ---

  defp normalize(description) do
    description
    |> String.trim()
    |> String.upcase()
  end

  defp load_from_feedback do
    path = Application.get_env(:local_ledger, :feedback_path, "priv/data/classification_feedback.jsonl")

    if File.exists?(path) do
      path
      |> File.stream!()
      |> Enum.reduce(%{}, fn line, acc ->
        case JSON.decode(String.trim(line)) do
          {:ok, %{"description" => desc, "corrected_account" => account}}
          when is_binary(desc) and is_binary(account) and desc != "" and account != "" ->
            Map.put(acc, normalize(desc), account)

          _ ->
            acc
        end
      end)
    else
      %{}
    end
  end
end
