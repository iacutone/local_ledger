defmodule LocalLedger.OllamaClientTest do
  use ExUnit.Case, async: true

  alias LocalLedger.{OllamaClient, Transaction}

  test "uses the fallback model for a low-confidence primary result" do
    transaction = %Transaction{
      description: "UNKNOWN MERCHANT",
      category: "Shopping",
      type: "Sale",
      amount: "-10.00"
    }

    request_fun = fn base_url, model, _body, _timeout ->
      response =
        cond do
          base_url == "http://small" and model == "ledger-small" ->
            ~S({"response":"{\"account\":\"Expenses:Shopping\",\"confidence\":0.20}"})

          base_url == "http://fallback" and model == "ledger-fallback" ->
            ~S({"response":"{\"account\":\"Expenses:Food:Restaurants\",\"confidence\":0.91}"})
        end

      {:ok, %{status: 200, body: response}}
    end

    assert {:ok, result} =
             OllamaClient.classify(transaction,
               base_url: "http://small",
               model: "ledger-small",
               fallback_base_url: "http://fallback",
               fallback_model: "ledger-fallback",
               request_fun: request_fun
             )

    assert result.account == "Expenses:Food:Restaurants"
    assert result.source == :fallback_model
  end
end
