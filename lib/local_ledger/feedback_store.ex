defmodule LocalLedger.FeedbackStore do
  @moduledoc """
  Persists user corrections as append-only JSONL records for future model
  refinement.

  Only classification features and labels are retained. Dates, filenames, and
  card identifiers are intentionally excluded.
  """

  alias LocalLedger.Transaction

  @spec record(Transaction.t(), term(), String.t()) :: :ok | {:error, String.t()}
  def record(%Transaction{} = transaction, prediction, corrected_account) do
    record = %{
      "description" => transaction.description,
      "bank_category" => transaction.category,
      "type" => transaction.type,
      "amount" => transaction.amount,
      "predicted_account" => predicted_account(prediction),
      "predicted_confidence" => predicted_confidence(prediction),
      "corrected_account" => corrected_account,
      "recorded_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    path = Application.get_env(:local_ledger, :feedback_path, "priv/data/classification_feedback.jsonl")

    try do
      path |> Path.dirname() |> File.mkdir_p!()
      File.write!(path, JSON.encode!(record) <> "\n", [:append, :utf8])
      :ok
    rescue
      error -> {:error, "Could not save classification feedback: #{Exception.message(error)}"}
    end
  end

  defp predicted_account({:low_confidence, result}) when is_map(result),
    do: Map.get(result, :account)

  defp predicted_account(_), do: nil

  defp predicted_confidence({:low_confidence, result}) when is_map(result),
    do: Map.get(result, :confidence)

  defp predicted_confidence(_), do: nil
end
