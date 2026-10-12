defmodule LocalLedger.OllamaClientTest do
  use ExUnit.Case, async: true

  alias LocalLedger.{OllamaClient, Transaction}

  test "uses Laya's hierarchical choice responses and returns low confidence" do
    transaction = %Transaction{
      description: "UNKNOWN MERCHANT",
      category: "Shopping",
      type: "Sale",
      amount: "-10.00"
    }

    request_fun = fn base_url, model, body, _timeout ->
      payload = JSON.decode!(body)

      response =
        cond do
          base_url == "http://laya" and model == "laya" and
              Map.has_key?(payload["questions"], "group") ->
            ~S({"answers":{"group":{"type":"choice","choice":"food","probabilities":{"food":0.95,"shopping":0.03,"other":0.02},"confidence":0.90}}})

          base_url == "http://laya" and model == "laya" ->
            ~S({"answers":{"account":{"type":"choice","choice":"Expenses:Food:Groceries","probabilities":{"Expenses:Food:Groceries":0.20,"Expenses:Food:Restaurants":0.80},"confidence":0.70}}})
        end

      {:ok, %{status: 200, body: response}}
    end

    assert {:error, {:low_confidence, result}} =
             OllamaClient.classify(transaction,
               base_url: "http://laya",
               model: "laya",
               request_fun: request_fun
             )

    assert result.account == "Expenses:Food:Groceries"
    assert result.confidence == 0.2
  end
end
