defmodule Kvasir.Command.Encodings.Raw do
  import Kvasir.Type, only: [do_encode: 3]

  def encode(command, _opts) do
    with {:ok, payload} <- payload(command) do
      {:ok,
       %{
         type: type(command),
         meta: meta(command),
         payload: payload
       }}
    end
  end

  def decode(data, opts \\ []) do
    with {:ok, command} <- find_command(get(data, :type)) do
      do_decode(
        command.__command__(:fields),
        get(data, :payload),
        %{__meta__: Kvasir.Command.Meta.decode(get(data, :meta), opts[:meta])},
        case opts[:process] do
          :create -> &command.create/1
          :struct -> &struct!(command, &1)
          nil -> &struct!(command, &1)
        end
      )
    end
  end

  ### Helpers ###
  ## Encoding  ##

  defp type(%command{}), do: inspect(command)

  defp meta(%{__meta__: meta}), do: Kvasir.Command.Meta.encode(meta)

  defp payload(command = %type{}), do: do_encode(command, type.__command__(:fields), %{})

  ## Decoding  ##

  defp find_command(command) when is_atom(command) do
    if Code.ensure_compiled?(command),
      do: {:ok, command},
      else: {:error, :unknown_command}
  end

  defp find_command(command) when is_binary(command),
    do: find_command(Module.concat("Elixir", command))

  defp do_decode([], _data, acc, process), do: process.(acc)

  defp do_decode([{property, type, opts} | props], data, acc, process) do
    with {:ok, value} <- fetch(data, property),
         {:ok, parsed_value} <- Kvasir.Type.load(type, value, opts) do
      do_decode(props, data, Map.put(acc, property, parsed_value), process)
    else
      :error ->
        if opts[:optional],
          do: do_decode(props, data, acc, process),
          else: {:error, :missing_field}

      error = {:error, _} ->
        error
    end
  end

  defp fetch(data, field) do
    with :error <- Map.fetch(data, field) do
      Map.fetch(data, to_string(field))
    end
  end

  defp get(data, field) do
    Map.get(data, field) || Map.get(data, to_string(field))
  end
end
