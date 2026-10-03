defmodule LocalLedger.CsvParser do
  @moduledoc """
  Parses the CSV and TSV exports accepted by Local Ledger.

  NimbleCSV returns binary references into its input for speed. Rows are copied
  before they leave this module because they are sent to other processes while
  an upload is being classified.
  """

  NimbleCSV.define(LocalLedger.CsvParser.Comma, separator: ",", escape: "\"")
  NimbleCSV.define(LocalLedger.CsvParser.Tab, separator: "\t", escape: "\"")

  @type row :: %{
          row_number: pos_integer(),
          values: %{String.t() => String.t()},
          raw: [String.t()]
        }

  @doc """
  Parses a CSV or TSV string into normalized rows.

  Headers are normalized to lowercase snake case. The first row is treated as
  the header row, and the returned row number starts at 2 to match the source
  file.
  """
  @spec parse(String.t()) :: {:ok, %{headers: [String.t()], rows: [row()]}} | {:error, String.t()}
  def parse(content) when is_binary(content) do
    content = String.trim_leading(content, "\uFEFF")

    with {:ok, header_line} <- header_line(content),
         parser <- parser_for(header_line),
         rows <- parser.parse_string(content, skip_headers: false),
         {:ok, [header_row | data_rows]} <- non_empty_rows(rows),
         {:ok, headers} <- normalize_headers(header_row),
         {:ok, parsed_rows} <- build_rows(headers, data_rows) do
      {:ok, %{headers: headers, rows: parsed_rows}}
    else
      {:error, message} -> {:error, message}
      _ -> {:error, "The CSV file could not be parsed."}
    end
  rescue
    error in NimbleCSV.ParseError ->
      {:error, "Invalid CSV: #{Exception.message(error)}"}
  end

  def parse(_content), do: {:error, "CSV content must be text."}

  defp header_line(content) do
    case content |> String.split(~r/\r\n|\n|\r/, parts: 2) |> Enum.find(&(&1 != "")) do
      nil -> {:error, "The CSV file is empty."}
      header -> {:ok, header}
    end
  end

  defp parser_for(header_line) do
    if String.contains?(header_line, "\t"), do: LocalLedger.CsvParser.Tab, else: LocalLedger.CsvParser.Comma
  end

  defp non_empty_rows(rows) do
    rows =
      Enum.reject(rows, fn row ->
        Enum.all?(row, &(String.trim(&1) == ""))
      end)

    case rows do
      [] -> {:error, "The CSV file is empty."}
      rows -> {:ok, rows}
    end
  end

  defp normalize_headers(header_row) do
    headers = Enum.map(header_row, &normalize_header/1)

    cond do
      Enum.any?(headers, &(&1 == "")) ->
        {:error, "The CSV contains an empty column name."}

      length(headers) != length(Enum.uniq(headers)) ->
        {:error, "The CSV contains duplicate column names."}

      true ->
        {:ok, headers}
    end
  end

  defp normalize_header(header) do
    header
    |> :binary.copy()
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "_")
    |> String.trim("_")
  end

  defp build_rows(headers, rows) do
    rows
    |> Enum.with_index(2)
    |> Enum.reduce_while({:ok, []}, fn {row, row_number}, {:ok, acc} ->
      cond do
        length(row) != length(headers) ->
          {:halt,
           {:error,
            "CSV row #{row_number} has #{length(row)} fields; expected #{length(headers)}."}}

        true ->
          copied_row = Enum.map(row, &:binary.copy/1)
          values = headers |> Enum.zip(copied_row) |> Map.new()
          {:cont, {:ok, [%{row_number: row_number, values: values, raw: copied_row} | acc]}}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      error -> error
    end
  end
end
