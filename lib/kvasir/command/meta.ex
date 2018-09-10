defmodule Kvasir.Command.Meta do
  defstruct [
    :id,
    :created,
    :dispatched
  ]

  defimpl Inspect do
    def inspect(%{id: nil}, _opts), do: "#Kvasir.Command.Meta<NotDispatched>"
    def inspect(%{id: id}, _opts), do: "#Kvasir.Command.Meta<#{id}>"
  end
end
