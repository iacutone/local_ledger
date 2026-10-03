defmodule LocalLedger.LedgerFormatter do
  @moduledoc """
  Converts normalized transactions and classifications into balanced ledger
  entries without asking a language model to generate accounting syntax.
  """

  alias LocalLedger.Transaction

  @spec format([Transaction.t()], String.t(), keyword()) ::
          {:ok, String.t()} | {:error, String.t()}
  def format(transactions, filename, opts \\ []) do
    progress = Keyword.get(opts, :progress, fn _current, _total -> :ok end)
    total = length(transactions)

    transactions
    |> Enum.sort_by(& &1.post_date)
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {transaction, current}, {:ok, entries} ->
      progress.(current, total)

      case entry(transaction, filename, opts) do
        {:ok, formatted} -> {:cont, {:ok, [formatted | entries]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, entries |> Enum.reverse() |> Enum.join("\n\n") |> Kernel.<>("\n")}
      error -> error
    end
  end

  @spec entry(Transaction.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def entry(%Transaction{} = transaction, filename, opts \\ []) do
    card_account = card_account(filename)
    header = header(transaction)

    case Transaction.kind(transaction) do
      :payment ->
        {:ok,
         [
           header,
           "\t#{card_account}\t\t\t#{ledger_amount(transaction.amount)}",
           "\tAssets:Checking:Bank Account"
         ]
         |> Enum.join("\n")}

      kind when kind in [:expense, :refund] ->
        with {:ok, classification} <- classify(transaction, opts) do
          expense_line = "\t#{classification.account}"

          {:ok,
           [
             header,
             expense_line,
             "\t#{card_account}\t\t\t#{ledger_amount(transaction.amount)}"
           ]
           |> Enum.join("\n")}
        else
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp classify(transaction, opts) do
    result =
      case Keyword.get(opts, :classifier) do
      classifier when is_function(classifier, 1) -> classifier.(transaction)
      _ -> LocalLedger.TransactionClassifier.classify(transaction, opts)
      end

    case result do
      {:ok, _classification} ->
        result

      {:error, reason} ->
        case Keyword.get(opts, :resolve_classification) do
          resolver when is_function(resolver, 2) -> resolver.(transaction, reason)
          _ -> {:error, reason}
        end
    end
  end

  defp header(transaction) do
    metadata =
      [transaction.transaction_date, transaction.description, transaction.category, transaction.type]
      |> Enum.map(&String.trim(to_string(&1 || "")))
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("; ")

    "#{transaction.post_date}\t#{metadata}\t;"
  end

  defp ledger_amount(amount) do
    amount = String.trim(to_string(amount))

    cond do
      String.starts_with?(amount, "$") -> amount
      String.starts_with?(amount, "+") -> "$" <> String.trim_leading(amount, "+")
      true -> "$" <> amount
    end
  end

  def card_account(filename) do
    last_four =
      case Regex.run(~r/^[A-Za-z]+(\d{4})/, Path.basename(filename || "")) do
        [_, digits] -> " #{digits}"
        _ -> ""
      end

    "Liabilities:Credit Card#{last_four}"
  end
end
