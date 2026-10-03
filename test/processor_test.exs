defmodule LocalLedger.ProcessorTest do
  use ExUnit.Case, async: false

  test "requests and records a user correction for an uncertain model result" do
    path = Path.join(System.tmp_dir!(), "local-ledger-processor-#{System.unique_integer([:positive])}.jsonl")
    Application.put_env(:local_ledger, :feedback_path, path)

    on_exit(fn ->
      File.rm(path)
      Application.delete_env(:local_ledger, :feedback_path)
    end)

    csv = """
    Transaction Date,Post Date,Description,Category,Type,Amount
    01/01/2020,01/02/2020,LOCAL FARM MARKET,Shopping,Sale,-12.00
    """

    uncertain = fn _transaction, _reason ->
      {:ok, %{account: "Expenses:Food:Groceries", confidence: 1.0}}
    end

    classifier = fn _transaction ->
      {:error, {:low_confidence, %{account: "Expenses:Shopping", confidence: 0.2}}}
    end

    assert {:ok, %{journal: journal, row_count: 1}} =
             LocalLedger.Processor.process(csv, "Chase1234.csv",
               classifier: classifier,
               uncertain: uncertain
             )

    assert journal =~ "Expenses:Food:Groceries"
    assert File.read!(path) =~ "LOCAL FARM MARKET"
    assert File.read!(path) =~ "Expenses:Food:Groceries"
  end
end
