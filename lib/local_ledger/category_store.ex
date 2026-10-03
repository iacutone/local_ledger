defmodule LocalLedger.CategoryStore do
  @moduledoc """
  Persists user-defined account names to an append-only JSONL file and
  keeps them in memory so they survive restarts and appear in the UI datalist.
  """

  use GenServer

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns all user-defined account names."
  @spec all() :: [String.t()]
  def all do
    GenServer.call(__MODULE__, :all)
  end

  @doc "Adds a new account name if it is not already known. Persists to JSONL."
  @spec add(String.t()) :: :ok
  def add(account) when is_binary(account) do
    GenServer.cast(__MODULE__, {:add, String.trim(account)})
  end

  # --- GenServer callbacks ---

  @impl true
  def init(_opts) do
    accounts = load_from_file()
    {:ok, %{accounts: MapSet.new(accounts)}}
  end

  @impl true
  def handle_call(:all, _from, state) do
    {:reply, MapSet.to_list(state.accounts), state}
  end

  @impl true
  def handle_cast({:add, account}, state) do
    if MapSet.member?(state.accounts, account) do
      {:noreply, state}
    else
      append_to_file(account)
      {:noreply, %{state | accounts: MapSet.put(state.accounts, account)}}
    end
  end

  # --- Private helpers ---

  defp path do
    Application.get_env(:local_ledger, :category_store_path, "priv/data/user_categories.jsonl")
  end

  defp load_from_file do
    p = path()

    if File.exists?(p) do
      p
      |> File.stream!()
      |> Enum.flat_map(fn line ->
        case JSON.decode(String.trim(line)) do
          {:ok, %{"account" => account}} when is_binary(account) and account != "" -> [account]
          _ -> []
        end
      end)
    else
      []
    end
  end

  defp append_to_file(account) do
    p = path()

    try do
      p |> Path.dirname() |> File.mkdir_p!()
      File.write!(p, JSON.encode!(%{"account" => account}) <> "\n", [:append, :utf8])
    rescue
      error ->
        require Logger
        Logger.warning("CategoryStore: could not persist account: #{Exception.message(error)}")
    end
  end
end
