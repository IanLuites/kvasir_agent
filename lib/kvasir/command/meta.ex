defmodule Kvasir.Command.Meta do
  @type t :: %__MODULE__{
          id: String.t(),
          scope: :global | {:instance, term},
          dispatch: :single | :multiple
        }

  defstruct [
    :id,
    :created,
    :dispatched,
    :scope,
    dispatch: :single
  ]

  defimpl Inspect do
    def inspect(%{id: nil}, _opts), do: "#Kvasir.Command.Meta<NotDispatched>"
    def inspect(%{id: id}, _opts), do: "#Kvasir.Command.Meta<#{id}>"
  end
end
