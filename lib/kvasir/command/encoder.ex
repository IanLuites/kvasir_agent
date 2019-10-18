defmodule Kvasir.Command.Encoder do
  alias Kvasir.Type.Serializer

  def encode(command, _opts \\ []) do
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
    with {:ok, command} <- find_command(MapX.get(data, :type)),
         {:ok, payload} <-
           Serializer.decode(command.__command__(:fields), MapX.get(data, :payload)) do
      cmd =
        Map.put(
          payload,
          :__meta__,
          Kvasir.Command.Meta.decode(MapX.get(data, :meta), opts[:meta])
        )

      case opts[:process] do
        :create -> command.create(cmd)
        :struct -> struct!(command, cmd)
        nil -> struct!(command, cmd)
      end
    end
  end

  ### Helpers ###
  ## Encoding  ##

  defp type(%command{}), do: command.__command__(:type)
  defp meta(%{__meta__: meta}), do: Kvasir.Command.Meta.encode(meta)
  defp payload(command = %type{}), do: Serializer.encode(type.__command__(:fields), command)

  ## Decoding  ##

  defp find_command(command) when is_atom(command) do
    if Code.ensure_compiled?(command),
      do: {:ok, command},
      else: {:error, :unknown_command}
  end

  defp find_command(command) when is_binary(command) do
    if lookup = Kvasir.Command.Registry.lookup(command) do
      find_command(lookup)
    else
      find_command(Module.concat("Elixir", command))
    end
  end
end
