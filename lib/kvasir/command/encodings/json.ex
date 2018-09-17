defmodule Kvasir.Command.Encodings.JSON do
  alias Kvasir.Command.Encodings.Raw

  def encode(command, opts) do
    with {:ok, data} <- Raw.encode(command, opts) do
      Jason.encode(data, opts)
    end
  end

  def decode(data, opts) do
    with {:ok, payload} <- Jason.decode(data, opts) do
      Raw.decode(payload, opts)
    end
  end
end
