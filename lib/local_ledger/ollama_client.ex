defmodule LocalLedger.OllamaClient do
  @moduledoc """
  Client for Ollama's Jev-compatible Laya decision endpoint.
  """

  @spec classify(LocalLedger.Transaction.t(), keyword()) ::
          {:ok, %{account: String.t(), confidence: float(), source: atom()}}
          | {:error, term()}
  def classify(transaction, opts \\ []) do
    threshold =
      Keyword.get(
        opts,
        :confidence_threshold,
        Application.get_env(:local_ledger, :classifier_confidence_threshold, 0.80)
      )

    case choose_group(transaction, opts) do
      {:ok, group_answer} ->
        case confident_choice(group_answer, threshold) do
          {:ok, group, _group_confidence} ->
            with {:ok, account_answer} <- choose_account(transaction, group, opts),
                 {:ok, account, confidence} <- confident_choice(account_answer, threshold) do
              {:ok, %{account: account, confidence: confidence, source: :laya}}
            else
              {:error, {:low_confidence, result}} -> {:error, {:low_confidence, result}}
              {:error, reason} -> {:error, {:classification_failed, reason}}
            end

          {:error, {:low_confidence, result}} ->
            {:error, {:low_confidence, Map.put(result, :account, nil)}}

          {:error, reason} ->
            {:error, {:classification_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:classification_failed, reason}}
    end
  end

  defp choose_group(transaction, opts) do
    questions = %{
      "group" => %{
        "type" => "choice",
        "instructions" => "Which broad spending group best fits this transaction?",
        "criteria" => LocalLedger.TransactionClassifier.group_criteria()
      }
    }

    request(transaction_state(transaction), questions, opts)
  end

  defp choose_account(transaction, group, opts) do
    accounts = LocalLedger.TransactionClassifier.accounts_for_group(group)

    criteria =
      Map.new(accounts, fn account ->
        {account, account_description(account)}
      end)

    questions = %{
      "account" => %{
        "type" => "choice",
        "instructions" => "Which ledger account best fits this transaction?",
        "criteria" => criteria
      }
    }

    request(transaction_state(transaction), questions, opts)
  end

  defp request(state, questions, opts) do
    base_url = Keyword.get(opts, :base_url, base_url())
    model = Keyword.get(opts, :model, model())
    timeout = Keyword.get(opts, :timeout, timeout())

    body =
      JSON.encode!(%{
        model: model,
        state: state,
        questions: questions
      })

    request =
      Finch.build(
        :post,
        "#{String.trim_trailing(base_url, "/")}/v1/systemone",
        [{"content-type", "application/json"}],
        body
      )

    result =
      case Keyword.get(opts, :request_fun) do
        fun when is_function(fun, 4) -> fun.(base_url, model, body, timeout)
        _ -> Finch.request(request, LocalLedger.Finch, receive_timeout: timeout)
      end

    with {:ok, response} <- result,
         true <- response.status in 200..299,
         {:ok, payload} <- JSON.decode(response.body),
         {:ok, answer} <- parse_answer(payload) do
      {:ok, answer}
    else
      false -> {:error, "Laya returned HTTP #{result_status(result)}."}
      {:error, reason} -> {:error, inspect(reason)}
      _ -> {:error, "Laya returned an invalid decision response."}
    end
  end

  defp parse_answer(%{"answers" => answers}) when is_map(answers) do
    case Map.values(answers) do
      [answer | _] when is_map(answer) -> {:ok, answer}
      _ -> {:error, "Laya returned no answer."}
    end
  end

  defp parse_answer(_), do: {:error, "Laya returned no answers."}

  defp confident_choice(
         %{"choice" => choice, "probabilities" => probabilities} = answer,
         threshold
       )
       when is_binary(choice) and is_map(probabilities) do
    probability = Map.get(probabilities, choice, 0.0) * 1.0

    if probability >= threshold do
      {:ok, choice, probability}
    else
      {:error, {:low_confidence, %{account: choice, confidence: probability, answer: answer}}}
    end
  end

  defp confident_choice(answer, _threshold),
    do:
      {:error,
       "Laya answer did not include a choice probability distribution: #{inspect(answer)}"}

  defp transaction_state(transaction) do
    %{
      "description" => transaction.description,
      "bank_category" => transaction.category || "",
      "type" => transaction.type || "",
      "amount" => transaction.amount
    }
  end

  defp account_description("Expenses:Online Services:" <> service),
    do: "online #{service} services"

  defp account_description("Expenses:Food:" <> category),
    do: "food and #{String.downcase(category)}"

  defp account_description("Expenses:" <> category), do: String.downcase(category)
  defp account_description("Assets:Cash"), do: "cash withdrawal"

  defp result_status({:ok, response}), do: response.status
  defp result_status(_), do: "error"

  defp base_url,
    do: Application.get_env(:local_ledger, :ollama_base_url, "http://localhost:11434")

  defp model, do: Application.get_env(:local_ledger, :laya_model, "laya")
  defp timeout, do: Application.get_env(:local_ledger, :ollama_timeout, 120_000)
end
