defmodule LocalLedger.CategoryProposalStoreTest do
  use ExUnit.Case, async: false

  alias LocalLedger.{CategoryProposalStore, Transaction}

  test "records a pending proposal without changing the active accounts" do
    path =
      Path.join(
        System.tmp_dir!(),
        "local-ledger-category-proposals-#{System.unique_integer([:positive])}.jsonl"
      )

    Application.put_env(:local_ledger, :category_proposal_path, path)

    on_exit(fn ->
      File.rm(path)
      Application.delete_env(:local_ledger, :category_proposal_path)
    end)

    transaction = %Transaction{
      description: "LOCAL FARM MARKET",
      category: "Shopping",
      type: "Sale",
      amount: "-12.00"
    }

    assert :ok =
             CategoryProposalStore.record(
               transaction,
               {:low_confidence, %{account: "Expenses:Shopping", confidence: 0.42}},
               "Expenses:Farmers Markets",
               "food"
             )

    record = path |> File.read!() |> String.trim() |> JSON.decode!()
    assert record["status"] == "pending"
    assert record["proposed_account"] == "Expenses:Farmers Markets"
    assert record["group"] == "food"
    assert record["predicted_account"] == "Expenses:Shopping"
    refute "Expenses:Farmers Markets" in LocalLedger.TransactionClassifier.allowed_accounts()
  end

  test "rejects an active account and an unknown parent group" do
    assert {:error, "That category already exists in the active account list."} =
             CategoryProposalStore.validate("Expenses:Shopping", "shopping")

    assert {:error, "The proposed category must use an allowed parent group."} =
             CategoryProposalStore.validate("Expenses:Education", "learning")
  end
end
