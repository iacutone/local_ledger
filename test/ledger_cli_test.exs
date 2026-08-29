defmodule LocalLedger.LedgerCliTest do
  use ExUnit.Case, async: true

  alias LocalLedger.LedgerCli

  setup tags do
    if tags[:ledger] && is_nil(System.find_executable("ledger")) do
      {:skip, "ledger is not installed"}
    else
      :ok
    end
  end

  @journal """
  2019-12-22	12/22/2019; AUTOMATIC PAYMENT - THANK; Payment	;
  	Liabilities:Credit Card 1234			 $3476.17
  	Assets:Checking:Bank Account

  2019-12-23	12/21/2019; TARGET 00011569; Shopping; Sale	;
  	Expenses:Shopping
  	Liabilities:Credit Card 1234			-$48.30
  """

  test "returns an error when the journal is empty" do
    assert {:error, message} = LedgerCli.reports("   \n")
    assert message =~ "no journal"
  end

  test "returns an error when ledger is not installed" do
    assert {:error, message} = LedgerCli.reports(@journal, executable: "/definitely/not/ledger")
    assert message =~ "not installed"
  end

  @tag :ledger
  test "rewrites -$ amounts, strips fences, and returns balance plus register" do
    journal = """
    ```ledger
    #{@journal}
    ```
    """

    assert {:ok, reports} = LedgerCli.reports(journal)
    assert reports.balance =~ "Expenses:Shopping"
    assert reports.balance =~ "Liabilities:Credit Card 1234"
    assert reports.balance =~ "Assets:Checking:Bank Account"
    assert reports.register =~ "TARGET"
    assert reports.register =~ "AUTOMAT"
  end

  @tag :ledger
  test "returns ledger stderr when the journal does not balance" do
    unbalanced = """
    2019-12-23	12/23/2019; TARGET; Sale	;
    	Expenses:Shopping			$10.00
    """

    assert {:error, message} = LedgerCli.reports(unbalanced)
    assert message =~ "balance" or message =~ "Balance"
  end
end
