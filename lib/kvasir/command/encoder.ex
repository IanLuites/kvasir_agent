defmodule Kvasir.Command.Encoder do
  def encode(command) do
    %{
      type: type(command),
      meta: meta(command),
      payload: payload(command)
    }
  end

  defp type(%command{}), do: inspect(command)

  defp meta(%{__meta__: meta}) do
    meta
    |> Map.from_struct()
    |> Enum.reject(&is_nil(elem(&1, 1)))
    |> Enum.into(%{})
  end

  defp payload(command) do
    command
    |> Map.from_struct()
    |> Map.delete(:__meta__)
  end
end
