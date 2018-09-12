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

    quote do
      @behaviour Kvasir.Agent.Aggregate
      import Kvasir.Agent.Aggregate, only: [aggregate: 1]

      if unquote(commands), do: defdelegate(execute(state, command), to: unquote(commands))
      if unquote(events), do: defdelegate(apply(state, event), to: unquote(events))
    end
  end

  defmacro field(name, type) do
    quote do
      Module.put_attribute(__MODULE__, :aggregate_fields, {unquote(name), unquote(type)})
    end
  end

  defmacro aggregate(do: block) do
    quote do
      Module.register_attribute(__MODULE__, :aggregate_fields, accumulate: true)

      try do
        import Kvasir.Agent.Aggregate, only: [field: 2]
        unquote(block)
      after
        :ok
      end

      @struct_fields Enum.reverse(@aggregate_fields)
      defstruct Enum.map(@struct_fields, &elem(&1, 0))

      @doc false
      @impl Kvasir.Agent.Aggregate
      def base(_id), do: %__MODULE__{}

      defoverridable base: 1
      @doc false
      def __aggregate__(:config),
        do: %{
          struct: __MODULE__,
          fields: @struct_fields
        }

      def __aggregate__(:struct), do: __MODULE__
      def __aggregate__(:fields), do: @struct_fields

      defimpl Jason.Encoder, for: __MODULE__ do
        def encode(value, opts) do
          Jason.Encode.map(Map.from_struct(value), opts)
        end
      end
    end
  end
end
