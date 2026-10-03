defmodule LocalLedger.FeedbackStoreTest do
  use ExUnit.Case, async: false

  alias LocalLedger.{FeedbackStore, Transaction}

  test "stores minimal correction data without dates or card identifiers" do
    path = Path.join(System.tmp_dir!(), "local-ledger-feedback-#{System.unique_integer([:positive])}.jsonl")
    Application.put_env(:local_ledger, :feedback_path, path)

    on_exit(fn ->
      File.rm(path)
      Application.delete_env(:local_ledger, :feedback_path)
    end)

    transaction = %Transaction{
      row_number: 2,
      post_date: "2020-01-02",
      transaction_date: "2020-01-01",
      description: "LOCAL FARM MARKET",
      category: "Shopping",
      type: "Sale",
      amount: "-12.00"
    }

    assert :ok =
             FeedbackStore.record(
               transaction,
               {:low_confidence,
                %{account: "Expenses:Shopping", confidence: 0.42}},
               "Expenses:Food:Groceries"
             )

    record = path |> File.read!() |> String.trim() |> JSON.decode!()
    assert record["description"] == "LOCAL FARM MARKET"
    assert record["corrected_account"] == "Expenses:Food:Groceries"
    assert record["predicted_confidence"] == 0.42
    refute Map.has_key?(record, "post_date")
    refute Map.has_key?(record, "transaction_date")
  end
end
