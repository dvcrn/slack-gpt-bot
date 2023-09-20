defmodule Summarizer.Chatgpt do
  @type msg :: %{text: String.t(), user: String.t()}

  defp extract_result(%{message: %{content: content}}), do: content
  defp extract_result(_), do: "sorry something went wrong"

  defp sanitize_name(name) do
    String.replace(name, ~r[\ |\.], "")
  end

  defp role(%{user: userid}, botid) do
    case userid == botid do
      true -> :assistant
      false -> :user
    end
  end

  @spec summarize([msg]) :: {:ok, any()} | {:error, any()}

  def summarize(msgs, botid \\ "") when is_list(msgs) do
    operator_message = %ExOpenAI.Components.ChatCompletionRequestMessage{
      role: :system,
      name: "system",
      content: Application.get_env(:summarizer, :prompt) |> String.replace("{botid}", botid)
    }

    chatgpt_messages =
      msgs
      # sort messages
      |> Enum.filter(fn msg -> msg.user != botid end)
      |> Enum.sort(fn a, b ->
        Kernel.elem(Float.parse(a.ts), 0) <= Kernel.elem(Float.parse(b.ts), 0)
      end)
      |> Enum.map(fn msg ->
        %ExOpenAI.Components.ChatCompletionRequestMessage{
          content: msg.text,
          role: role(msg, botid),
          name: sanitize_name(msg.user)
        }
      end)

    case ExOpenAI.Chat.create_chat_completion(
           [operator_message | chatgpt_messages],
           "gpt-4",
           temperature: 0.6
         ) do
      {:ok, result} ->
        {:ok, List.first(result.choices) |> extract_result()}

      {:error, %{"error" => %{"message" => msg}}} ->
        IO.puts("got error message: #{inspect(msg)}")

        if String.contains?(msg, "The server had an error while processing your request.") do
          summarize(msgs, botid)
        else
          {:error, msg}
        end

      {:error, e} ->
        IO.puts("got error: #{inspect(e)}")
        {:error, e}
    end
  end
end
