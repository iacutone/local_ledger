defmodule LocalLedger.TransactionClassifierTest do
  use ExUnit.Case, async: true

  alias LocalLedger.TransactionClassifier

  test "specific merchant rules win over bank categories" do
    assert TransactionClassifier.known_account("COSTCO WHSE #1195") ==
             "Expenses:Food:Groceries"

    assert TransactionClassifier.known_account("PAYPAL *EBAY SAVMYSERVER") ==
             "Expenses:Books"

    assert TransactionClassifier.known_account("GEICO.  *AUTO") ==
             "Expenses:Insurance:Car"
  end

  test "unknown merchants are left for the model" do
    assert TransactionClassifier.known_account("LOCAL FARM MARKET 42") == nil
  end

  test "normalizes case and punctuation for high-confidence rules" do
    assert TransactionClassifier.known_account("  sTaRbUcKs #42  ") ==
             "Expenses:Food:Coffee"

    assert TransactionClassifier.known_account("ANNUAL-FEE") ==
             "Expenses:Financial:Fees"

    assert TransactionClassifier.known_account("O'Reilly Auto Parts") ==
             "Expenses:Auto"
  end

  test "does not classify generic shopping words as deterministic merchants" do
    assert TransactionClassifier.known_account("LOCAL SHOP") == nil
    assert TransactionClassifier.known_account("GENERAL STORE") == nil
  end

  test "derives the active accounts and group choices from one taxonomy" do
    accounts = TransactionClassifier.allowed_accounts()

    grouped_accounts =
      TransactionClassifier.group_criteria()
      |> Map.keys()
      |> Enum.flat_map(&TransactionClassifier.accounts_for_group/1)

    assert Enum.sort(accounts) == Enum.sort(grouped_accounts)
    assert "Expenses:Education" in accounts
    assert "Expenses:Financial:Fees" in accounts
    assert "Expenses:Housing" in accounts
    assert "Expenses:Donations" in accounts
  end
end
