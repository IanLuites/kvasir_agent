defmodule Kvasir.Command.Encodings.Raw do
  import Kvasir.Type, only: [do_encode: 3]

  def encode(command, opts) do
    with {:ok, payload} <- payload(command) do
      {:ok,
       %{
         type: type(command),
         meta: meta(command),
         payload: payload
       }}
    end
  end

  def decode(data, opts) do
  end

  ### Helpers ###

  defp type(%command{}), do: inspect(command)

  defp meta(%{__meta__: meta}) do
    meta
    |> Map.from_struct()
    |> Enum.reject(&is_nil(elem(&1, 1)))
    |> Enum.into(%{})
  end

  defp payload(command = %type{}), do: do_encode(command, type.__command__(:fields), %{})
end
