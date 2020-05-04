defmodule Kvasir.Agent.ObjectValue do
  defmodule Definition do
    import Kvasir.Event, only: [property: 4]

    defmacro property(name, type \\ :string, opts \\ []) do
      t = Macro.expand(type, __CALLER__)

      Code.ensure_loaded(t)

      if :erlang.function_exported(t, :__object_value__, 1) do
        Kvasir.Agent.Mutator.add_object_value(__CALLER__, name, t)
      end

      property(__CALLER__, name, type, opts)
    end
  end

  alias Kvasir.Agent.Mutator
  @callback base :: any

  defmacro __using__(opts \\ []) do
    Mutator.init(__CALLER__)

    quote location: :keep do
      @before_compile unquote(__MODULE__)
      @behaviour Kvasir.Agent.ObjectValue
      @__struct__ unquote(opts[:struct]) || __MODULE__
      import Kvasir.Agent.ObjectValue, only: [object_value: 1, object_value: 2]
    end
  end

  defmacro object_value(do: block) do
    quote location: :keep do
      @__type__ nil
      @__opts__ nil

      import Kvasir.Agent.ObjectValue, only: []
      Module.register_attribute(__MODULE__, :fields, accumulate: true)

      try do
        import Kvasir.Agent.ObjectValue.Definition,
          only: [
            property: 1,
            property: 2,
            property: 3
          ]

        unquote(block)
      after
        :ok
      end

      require Kvasir.Agent.Mutator
      Kvasir.Agent.Mutator.imports()

      if @__struct__ == __MODULE__ do
        @struct_fields Enum.reverse(@fields)
        defstruct Enum.map(@struct_fields, fn {field, type, opts} ->
                    if :erlang.function_exported(type, :__object_value__, 1) do
                      {field, type.base()}
                    else
                      {field, Keyword.get(opts, :default)}
                    end
                  end)

        defimpl Jason.Encoder, for: __MODULE__ do
          def encode(value, opts) do
            Jason.Encode.map(Map.from_struct(value), opts)
          end
        end
      else
        @struct_fields []
      end

      @doc false
      @impl Kvasir.Agent.ObjectValue
      @spec base :: term
      def base, do: %@__struct__{}

      defoverridable base: 0
    end
  end

  defmacro object_value(type, opts \\ []) do
    quote do
      @__type__ unquote(type)
      @__opts__ unquote(opts)
      @struct_fields []

      require Kvasir.Agent.Mutator
      Kvasir.Agent.Mutator.imports()

      @doc false
      @impl Kvasir.Agent.ObjectValue
      @spec base :: term
      def base, do: unquote(Keyword.get(opts, :default))

      defoverridable base: 0
    end
  end

  defmacro __before_compile__(env) do
    quote do
      @doc false
      @spec generate_apply([atom]) :: term
      def generate_apply(path) do
        Kvasir.Agent.Mutator.generate_apply(
          __object_value__(:events),
          __object_value__(:object_values),
          [],
          path
        )
      end

      @doc false
      @spec generate_execution([atom]) :: term
      def generate_execution(path) do
        Kvasir.Agent.Mutator.generate_execution(
          __object_value__(:executes),
          __object_value__(:object_values),
          [],
          path
        )
      end

      @doc false
      @spec __object_value__(atom) :: term
      def __object_value__(:config),
        do: %{
          type: @__type__,
          opts: @__opts__,
          struct: @__struct__,
          fields: @struct_fields
        }

      def __object_value__(:struct), do: @__struct__
      def __object_value__(:fields), do: @struct_fields

      def __object_value__(:events) do
        unquote(Macro.escape(Mutator.events(env)))
      end

      def __object_value__(:executes) do
        unquote(Macro.escape(Mutator.executes(env)))
      end

      def __object_value__(:object_values) do
        unquote(Macro.escape(Mutator.object_values(env)))
      end
    end
  end
end
