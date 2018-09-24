defmodule Kvasir.Command.Encodings.Brod do
  alias Kvasir.Command.Encodings.JSON

  def encode(command, opts) do
    JSON.encode(command, opts)
  end

  def decode({:kafka_message_set, _topic, _from, _to, values}, opts) do
    multi_decode(values, opts, [])
  end

  def decode({:kafka_message, _offset, _key, value, _ts_type, _ts, _headers}, opts) do
    Jason.decode(value, opts)
  end

  defp multi_decode([], _opts, acc), do: {:ok, Enum.reverse(acc)}

  defp multi_decode([h | t], opts, acc) do
    case decode(h, opts) do
      {:ok, command} -> multi_decode(t, opts, [command | acc])
      error -> error
    end
  end
end
