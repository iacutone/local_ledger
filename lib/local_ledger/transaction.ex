defmodule LocalLedger.Transaction do
  @moduledoc """
  Normalized representation of one bank export row.
  """

  defstruct [
    :row_number,
    :post_date,
    :transaction_date,
    :description,
    :category,
    :type,
    :amount,
    :values
  ]

  @type t :: %__MODULE__{
          row_number: pos_integer(),
          post_date: String.t(),
          transaction_date: String.t(),
          description: String.t(),
          category: String.t(),
          type: String.t(),
          amount: String.t(),
          values: map()
        }

  @description_fields ["description", "merchant", "payee", "memo"]

  @spec from_row(map()) :: {:ok, t()} | {:error, String.t()}
  def from_row(%{row_number: row_number, values: values}) do
    post_date = first_value(values, ["post_date", "posted_date", "posting_date", "transaction_date", "date"])
    transaction_date = first_value(values, ["transaction_date", "date", "post_date"])
    description = first_value(values, @description_fields)
    amount = amount_value(values)

    cond do
      post_date == "" ->
        {:error, "CSV row #{row_number} has no transaction date."}

      description == "" ->
        {:error, "CSV row #{row_number} has no merchant description."}

      amount == "" ->
        {:error, "CSV row #{row_number} has no amount."}

      true ->
        {:ok,
         %__MODULE__{
           row_number: row_number,
           post_date: normalize_date(post_date),
           transaction_date: normalize_date(transaction_date),
           description: description,
           category: first_value(values, ["category", "bank_category"]),
           type: first_value(values, ["type"]),
           amount: normalize_amount(amount),
           values: values
         }}
    end
  end

  def kind(%__MODULE__{type: type, amount: amount}) do
    type = String.downcase(String.trim(type || ""))

    cond do
      type == "payment" -> :payment
      type in ["return", "refund", "adjustment"] -> :refund
      positive?(amount) -> :refund
      true -> :expense
    end
  end

  def positive?(amount), do: not String.starts_with?(amount, "-")

  def normalize_date(value) when is_binary(value) do
    value = String.trim(value)

    case Regex.run(~r/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/, value) do
      [_, month, day, year] ->
        "#{year}-#{String.pad_leading(month, 2, "0")}-#{String.pad_leading(day, 2, "0")}"

      _ ->
        value
    end
  end

  def normalize_date(_), do: ""

  def normalize_amount(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.replace(~r/[$,\s]/, "")
    |> parentheses_to_negative()
  end

  def normalize_amount(value), do: to_string(value)

  defp amount_value(values) do
    case first_value(values, ["amount"]) do
      "" ->
        case first_value(values, ["debit"]) do
          "" -> first_value(values, ["credit"])
          debit -> negate_if_positive(debit)
        end

      amount ->
        amount
    end
  end

  defp negate_if_positive("-" <> _ = amount), do: amount
  defp negate_if_positive(amount), do: "-" <> amount

  defp parentheses_to_negative("(" <> rest) do
    case String.trim_trailing(rest, ")") do
      value when value != rest -> "-" <> value
      value -> value
    end
  end

  defp parentheses_to_negative(value), do: value

  defp first_value(values, keys) do
    Enum.find_value(keys, "", fn key ->
      case Map.get(values, key) do
        value when is_binary(value) ->
          value = String.trim(value)
          if value == "", do: nil, else: value

        _ ->
          nil
      end
    end)
  end
end
