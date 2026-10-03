defmodule LocalLedger.TransactionTest do
  use ExUnit.Case, async: true

  alias LocalLedger.{CsvParser, Transaction}

  test "normalizes card export fields and dates" do
    csv = """
    Transaction Date,Post Date,Description,Category,Type,Amount
    12/30/2019,12/31/2019,MACYS EASTVIEW,Shopping,Sale,-81.74
    """

    assert {:ok, %{rows: [row]}} = CsvParser.parse(csv)
    assert {:ok, transaction} = Transaction.from_row(row)
    assert transaction.post_date == "2019-12-31"
    assert transaction.transaction_date == "2019-12-30"
    assert transaction.amount == "-81.74"
    assert Transaction.kind(transaction) == :expense
  end

  test "treats payments and positive non-payments separately" do
    payment = %Transaction{type: "Payment", amount: "100.00"}
    refund = %Transaction{type: "Adjustment", amount: "100.00"}

    assert Transaction.kind(payment) == :payment
    assert Transaction.kind(refund) == :refund
  end
end
