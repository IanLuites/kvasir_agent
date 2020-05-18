defmodule Kvasir.Agent.Aggregate do
  @moduledoc ~S"""
  Documentation for Kvasir.Agent.Aggregate.
  """

  @callback base(id :: any) :: any
  @callback apply(state :: any, event :: map) :: {:ok, any} | {:error, atom}
  @callback execute(state :: any, command :: map) ::
              :ok | {:ok, map} | {:ok, [map]} | {:error, atom}

  defmacro __using__(opts \\ []) do
    root = opts[:root]
    key = opts[:key]

    quote location: :keep do
      @behaviour Kvasir.Agent.Aggregate

      @doc false
      @impl Kvasir.Agent.Aggregate
      @spec base(term) :: term
      defdelegate base(id), to: unquote(root)

      @doc false
      @impl Kvasir.Agent.Aggregate
      @spec apply(term, term) :: {:ok, term} | {:error, atom}
      defdelegate apply(state, event), to: unquote(root)

      @doc false
      @impl Kvasir.Agent.Aggregate
      @spec execute(term, term) :: :ok | {:ok, map} | {:ok, [map]} | {:error, atom}
      defdelegate execute(state, command), to: unquote(root)

      @doc false
      @spec __aggregate__(atom) :: term
      def __aggregate__(:config),
        do: %{
          root: unquote(root),
          key: unquote(key)
        }

      def __aggregate__(:root), do: unquote(root)
      def __aggregate__(:key), do: unquote(key)
    end
  end
end
