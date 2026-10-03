defmodule LocalLedger.CsvParserTest do
  use ExUnit.Case, async: true

  alias LocalLedger.CsvParser

  test "parses quoted commas and normalizes headers" do
    csv = """
    Transaction Date,Post Date,Description,Amount
    01/02/2020,01/03/2020,"COFFEE, INC.",-4.50
    """

    assert {:ok, %{headers: headers, rows: [row]}} = CsvParser.parse(csv)
    assert headers == ["transaction_date", "post_date", "description", "amount"]
    assert row.row_number == 2
    assert row.values["description"] == "COFFEE, INC."
    assert row.values["amount"] == "-4.50"
  end

  test "parses tab-delimited exports and quoted newlines" do
    tsv = "Date\tDescription\tAmount\r\n01/02/2020\t\"STORE\nNOTE\"\t-4.50\r\n"

    assert {:ok, %{rows: [row]}} = CsvParser.parse(tsv)
    assert row.values["description"] == "STORE\nNOTE"
  end

  test "trims a UTF-8 BOM and skips blank rows" do
    csv = "\uFEFFDate,Description\n\n01/02/2020,Store\n\n"

    assert {:ok, %{rows: [row]}} = CsvParser.parse(csv)
    assert row.row_number == 2
  end

  test "rejects duplicate headers" do
    assert {:error, "The CSV contains duplicate column names."} =
             CsvParser.parse("Date,DATE\n01/01/2020,01/01/2020")
  end

  test "reports rows with the wrong number of fields" do
    assert {:error, message} = CsvParser.parse("Date,Description\n01/01/2020")
    assert message =~ "CSV row 2 has 1 fields; expected 2."
  end
end
