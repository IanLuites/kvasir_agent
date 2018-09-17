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
    do: do_decode_command(command.__command__(:fields), data, %{__meta__: meta}, command)

  defp do_decode_command([], _data, acc, command), do: {:ok, struct!(command, acc)}

  defp do_decode_command([{property, type, opts} | props], data, acc, command) do
    with {:ok, value} <- Map.fetch(data, to_string(property)),
         {:ok, parsed_value} <- Kvasir.Type.load(type, value, opts) do
      do_decode_command(props, data, Map.put(acc, property, parsed_value), command)
    else
      :error ->
        if opts[:optional],
          do: do_decode_command(props, data, acc, command),
          else: {:error, :missing_field}

      error = {:error, _} ->
        error
    end
  end
end
