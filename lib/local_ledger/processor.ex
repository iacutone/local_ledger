defmodule LocalLedger.Processor do
  @moduledoc """
  Coordinates CSV parsing, transaction normalization, classification, and
  deterministic ledger formatting.
  """

  alias LocalLedger.{CsvParser, LedgerFormatter, Transaction}

  @spec process(String.t(), String.t() | nil, keyword()) ::
          {:ok, %{journal: String.t(), row_count: non_neg_integer()}}
          | {:error, String.t()}
  def process(csv_content, filename, opts \\ []) do
    with {:ok, %{rows: rows}} <- CsvParser.parse(csv_content),
         {:ok, transactions} <- normalize_rows(rows) do
      progress = Keyword.get(opts, :progress, fn _current, _total -> :ok end)
      resolver = user_resolver(opts)

      formatter_opts =
        opts
        |> Keyword.put(:progress, progress)
        |> Keyword.put(:resolve_classification, resolver)

      case LedgerFormatter.format(transactions, filename || "", formatter_opts) do
        {:ok, journal} ->
          {:ok, %{journal: journal, row_count: length(transactions)}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp user_resolver(opts) do
    case Keyword.get(opts, :uncertain) do
      callback when is_function(callback, 2) ->
        fn transaction, reason ->
          with {:ok, %{account: account} = classification} <- callback.(transaction, reason),
               true <- account in LocalLedger.TransactionClassifier.allowed_accounts(),
               :ok <- LocalLedger.FeedbackStore.record(transaction, reason, account) do
            {:ok, Map.put_new(classification, :source, :user)}
          else
            false -> {:error, "The selected account is not allowed."}
            {:error, reason} -> {:error, reason}
          end
        end

      _ ->
        fn _transaction, reason -> {:error, reason}
    end
  end
  end

  defp normalize_rows(rows) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, transactions} ->
      case Transaction.from_row(row) do
        {:ok, transaction} -> {:cont, {:ok, [transaction | transactions]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, transactions} -> {:ok, Enum.reverse(transactions)}
      error -> error
    end
  end
end
