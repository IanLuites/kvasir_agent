defmodule Kvasir.Agent.Aggregate do
  @moduledoc ~S"""
  Documentation for Kvasir.Agent.Aggregate.
  """

  @callback base(id :: any) :: any
  @callback apply(state :: any, event :: map) :: {:ok, any} | {:error, atom}
  @callback execute(state :: any, command :: map) ::
              :ok | {:ok, map} | {:ok, [map]} | {:error, atom}

  defmacro __using__(opts \\ []) do
    commands = opts[:command]
    events = opts[:event]

    quote location: :keep do
      @behaviour Kvasir.Agent.Aggregate
      @__struct__ unquote(opts[:struct]) || __MODULE__
      import Kvasir.Agent.Aggregate, only: [aggregate: 1]

      if unquote(commands), do: defdelegate(execute(state, command), to: unquote(commands))
      if unquote(events), do: defdelegate(apply(state, event), to: unquote(events))
    end
  end

  defmacro aggregate(do: block) do
    quote location: :keep do
      Module.register_attribute(__MODULE__, :fields, accumulate: true)

      try do
        import Kvasir.Event, only: [field: 1, field: 2, field: 3]
        unquote(block)
      after
        :ok
      end

      if @__struct__ == __MODULE__ do
        @struct_fields Enum.reverse(@fields)
        defstruct Enum.map(@struct_fields, &elem(&1, 0))

        defimpl Jason.Encoder, for: __MODULE__ do
          def encode(value, opts) do
            Jason.Encode.map(Map.from_struct(value), opts)
          end
        end
      else
        @struct_fields []
      end

      @doc false
      @impl Kvasir.Agent.Aggregate
      def base(_id), do: %@__struct__{}

      defoverridable base: 1

      @doc false
      @spec __aggregate__(atom) :: term
      def __aggregate__(:config),
        do: %{
          struct: @__struct__,
          fields: @struct_fields
        }

      def __aggregate__(:struct), do: @__struct__
      def __aggregate__(:fields), do: @struct_fields
    end
  end
end
