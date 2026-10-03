defmodule LocalLedger.OllamaClientTest do
  use ExUnit.Case, async: true

  alias LocalLedger.{OllamaClient, Transaction}

  test "returns low confidence so the caller can request user input" do
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
        end

      {:ok, %{status: 200, body: response}}
    end

    assert {:error, {:low_confidence, result}} =
             OllamaClient.classify(transaction,
               base_url: "http://small",
               model: "ledger-small",
               request_fun: request_fun
             )

    assert result.account == "Expenses:Shopping"
    assert result.confidence == 0.2
  end
end
