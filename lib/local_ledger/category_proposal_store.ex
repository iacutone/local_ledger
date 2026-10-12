defmodule LocalLedger.CategoryProposalStore do
  @moduledoc """
  Persists proposed ledger categories without adding them to the active
  classifier allowlist.

  Proposals are append-only JSONL records so they can be reviewed and
  approved separately from transaction processing.
  """

  alias LocalLedger.Transaction

  @spec record(Transaction.t(), term(), String.t(), String.t()) ::
          :ok | {:error, String.t()}
  def record(%Transaction{} = transaction, prediction, proposed_account, group)
      when is_binary(proposed_account) and is_binary(group) do
    with :ok <- validate(proposed_account, group) do
      record = %{
        "description" => transaction.description,
        "bank_category" => transaction.category,
        "type" => transaction.type,
        "amount" => transaction.amount,
        "predicted_account" => predicted_account(prediction),
        "predicted_confidence" => predicted_confidence(prediction),
        "proposed_account" => proposed_account,
        "group" => group,
        "status" => "pending",
        "recorded_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      path =
        Application.get_env(
          :local_ledger,
          :category_proposal_path,
          "priv/data/category_proposals.jsonl"
        )

      try do
        path |> Path.dirname() |> File.mkdir_p!()
        File.write!(path, JSON.encode!(record) <> "\n", [:append, :utf8])
        :ok
      rescue
        error -> {:error, "Could not save category proposal: #{Exception.message(error)}"}
      end
    end
  end

  def record(_transaction, _prediction, _proposed_account, _group) do
    {:error, "A category proposal must include an account and parent group."}
  end

  @spec validate(String.t(), String.t()) :: :ok | {:error, String.t()}
  def validate(proposed_account, group) do
    cond do
      group not in Map.keys(LocalLedger.TransactionClassifier.group_criteria()) ->
        {:error, "The proposed category must use an allowed parent group."}

      proposed_account in LocalLedger.TransactionClassifier.allowed_accounts() ->
        {:error, "That category already exists in the active account list."}

      not valid_account_name?(proposed_account) ->
        {:error, "Use a ledger account such as Expenses:Education."}

      true ->
        :ok
    end
  end

  defp valid_account_name?(account) do
    Regex.match?(
      ~r/^(Expenses|Assets):[A-Za-z0-9][A-Za-z0-9 _-]*(?::[A-Za-z0-9][A-Za-z0-9 _-]*)*$/,
      account
    ) and
      String.length(account) <= 120
  end

  defp predicted_account({:low_confidence, result}) when is_map(result),
    do: Map.get(result, :account)

  defp predicted_account(_), do: nil

  defp predicted_confidence({:low_confidence, result}) when is_map(result),
    do: Map.get(result, :confidence)

  defp predicted_confidence(_), do: nil
end
