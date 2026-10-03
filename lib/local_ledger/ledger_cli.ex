defmodule LocalLedger.LedgerCli do
  @moduledoc """
  Runs the ledger(1) CLI against a generated journal so the UI can show
  account balances instead of raw journal text.
  """

  def reports(journal, opts \\ []) do
    journal = prepare(journal)

    if String.trim(journal) == "" do
      {:error, "The AI model returned no journal data."}
    else
      case executable(opts) do
        nil ->
          {:error,
           "ledger is not installed. Install it with `brew install ledger` (macOS) or `apt install ledger` (Debian/Ubuntu), then retry."}

        bin ->
          run_reports(bin, journal)
      end
    end
  end

  def download_name(journal, filename \\ nil) do
    case last_four(journal, filename) do
      four when is_binary(four) -> "credit-card#{four}.ledger"
      _ -> "credit-card.ledger"
    end
  end

  defp executable(opts) do
    case Keyword.fetch(opts, :executable) do
      {:ok, path} when is_binary(path) ->
        if File.regular?(path), do: path, else: System.find_executable(path)

      {:ok, _} ->
        nil

      :error ->
        System.find_executable(Application.get_env(:local_ledger, :ledger_bin, "ledger"))
    end
  end

  defp run_reports(bin, journal) do
    path = Path.join(System.tmp_dir!(), "local-ledger-#{System.unique_integer([:positive])}.dat")

    try do
      File.write!(path, journal)

      with {:ok, balance} <- run(bin, path, ["balance"]) do
        {:ok, %{balance: String.trim_trailing(balance)}}
      end
    after
      File.rm(path)
    end
  end

  defp run(bin, path, args) do
    {output, status} =
      System.cmd(bin, ["-f", path, "--no-color" | args], stderr_to_stdout: true)

    if status == 0 do
      {:ok, output}
    else
      {:error, String.trim(output)}
    end
  end

  defp prepare(journal) do
    journal
    |> String.replace(~r/^```(?:ledger)?\s*/m, "")
    |> String.replace(~r/^```\s*$/m, "")
    |> String.replace(~r/-\$(\d)/, "$-\\1")
    |> String.trim()
    |> Kernel.<>("\n")
  end

  defp last_four(journal, filename) do
    cond do
      match = Regex.run(~r/Liabilities:\s*Credit Card\s+(\d{4})/, journal || "") ->
        List.last(match)

      match = Regex.run(~r/^[A-Za-z]+(\d{4})/, Path.basename(filename || "")) ->
        List.last(match)

      true ->
        nil
    end
  end
end
