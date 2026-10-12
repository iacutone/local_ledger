defmodule LocalLedger.LedgerFormatterTest do
  use ExUnit.Case, async: true

  alias LocalLedger.{LedgerFormatter, Transaction}

  test "formats a payment with checking and card postings" do
    transaction = %Transaction{
      post_date: "2019-12-22",
      transaction_date: "2019-12-22",
      description: "AUTOMATIC PAYMENT - THANK",
      category: "",
      type: "Payment",
      amount: "3476.17"
    }

    assert {:ok, journal} = LedgerFormatter.entry(transaction, "Chase1234_Activity.csv")
    assert journal =~ "Liabilities:Credit Card 1234"
    assert journal =~ "Assets:Checking:Bank Account"
    assert journal =~ "$3476.17"
  end

  test "formats a known merchant without calling Ollama" do
    transaction = %Transaction{
      post_date: "2019-12-31",
      transaction_date: "2019-12-30",
      description: "COSTCO WHSE #1195",
      category: "Shopping",
      type: "Sale",
      amount: "-173.61"
    }

    assert {:ok, journal} = LedgerFormatter.entry(transaction, "Chase1234_Activity.csv")
    assert journal =~ "Expenses:Food:Groceries"
    assert journal =~ "$-173.61"
  end

  test "uses an injected classifier for an unknown merchant" do
    transaction = %Transaction{
      post_date: "2020-01-01",
      transaction_date: "2020-01-01",
      description: "UNKNOWN MERCHANT",
      category: "",
      type: "Sale",
      amount: "-10.00"
    }

    classifier = fn _ -> {:ok, %{account: "Expenses:Shopping", confidence: 0.9}} end

    assert {:ok, journal} =
             LedgerFormatter.entry(transaction, "statement.csv", classifier: classifier)

    assert journal =~ "Expenses:Shopping"
    assert journal =~ "Liabilities:Credit Card"
  end
end
