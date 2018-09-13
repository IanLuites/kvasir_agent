defmodule Kvasir.Command.Decoder do
  def decode(value, meta \\ %Kvasir.Command.Meta{}) do
    with {:ok, data} <- Jason.decode(value) do
      do_decode(data, update_meta(meta, data["meta"]))
    end
  end

  defp update_meta(meta, data) when is_map(data) do
    struct!(
      Kvasir.Command.Meta,
      for(
        {key, val} when val != nil <- data,
        into: Map.from_struct(meta),
        do: {String.to_atom(key), val}
      )
    )
  end

  defp update_meta(meta, _nil), do: meta

  defp do_decode(data, meta) do
    command = Module.concat("Elixir", data["type"])

    if Code.ensure_compiled?(command),
      do: decode_command(command, data["payload"], meta),
      else: {:error, :unknown_comand}
  end

  defp decode_command(command, data, meta),
    do: do_decode_command(command.__command__(:fields), data, struct(command, %{__meta__: meta}))

  defp do_decode_command([], _data, acc), do: acc

  defp do_decode_command([{property, type} | props], data, acc) do
    case Map.fetch(data, to_string(property)) do
      {:ok, value} ->
        do_decode_command(props, data, Map.put(acc, property, parse_type(value, type)))

      :error ->
        {:error, :invalid_command_payload}
    end
  end

  @unix ~N[1970-01-01 00:00:00]
  defp parse_type(nil, _), do: nil
  defp parse_type(value, :datetime), do: NaiveDateTime.add(@unix, value, :milliseconds)
  defp parse_type(value, _), do: value
end
