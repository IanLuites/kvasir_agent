defmodule Kvasir.Command.Encoder do
  def encode(command, opts \\ []), do: encoding(opts).encode(command, opts)
  def decode(command, opts \\ []), do: encoding(opts).decode(command, opts)

  @base_encoders %{
    brod: Kvasir.Command.Encodings.Brod,
    json: Kvasir.Command.Encodings.JSON,
    raw: Kvasir.Command.Encodings.Raw
  }

  @spec encoding(Keyword.t()) :: module
  defp encoding(opts) do
    encoding = opts[:encoding]

    cond do
      is_nil(encoding) -> Kvasir.Command.Encodings.JSON
      :erlang.function_exported(encoding, :encode, 2) -> encoding
      encoding = @base_encoders[encoding] -> encoding
      :no_valid_given -> {:error, :invalid_encoding}
    end
  end
end
