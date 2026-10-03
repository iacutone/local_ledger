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
end
