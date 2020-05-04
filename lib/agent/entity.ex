defmodule Kvasir.Agent.Entity do
  defmodule Definition do
    import Kvasir.Event, only: [property: 4]

    defmacro property(name, type \\ :string, opts \\ []) do
      t = Macro.expand(type, __CALLER__)

      Code.ensure_compiled(t)
      Code.ensure_loaded(t)

      x =
        if :erlang.function_exported(t, :__object_value__, 1) do
          quote do
            Module.put_attribute(__MODULE__, :object_values, {unquote(name), unquote(t)})
          end
        end

      quote do
        unquote(x)
        unquote(property(__CALLER__, name, type, opts))
      end
    end

    defmacro entity(_, _, _ \\ []), do: :ok

    defmacro entities(name, entity) do
      entity = Macro.expand(entity, __CALLER__)

      Code.ensure_compiled(entity)
      Code.ensure_loaded(entity)

      quote do
        Module.put_attribute(__MODULE__, :entities, {unquote(name), unquote(entity)})
        unquote(property(__CALLER__, name, :map, default: {:%{}, [], []}))
      end
    end
  end

  @callback base(id :: any) :: any
  @callback apply(state :: any, event :: map) :: {:ok, any} | {:error, atom}
  @callback execute(state :: any, command :: map) ::
              :ok | {:ok, map} | {:ok, [map]} | {:error, atom}

  defmacro __using__(opts \\ []) do
    Kvasir.Agent.Mutator.init(__CALLER__)

    quote location: :keep do
      @base unquote(opts[:base])
      @has_base unquote(Keyword.has_key?(opts, :base))
      @behaviour Kvasir.Agent.Entity
      @before_compile unquote(__MODULE__)
      @__struct__ unquote(opts[:struct]) || __MODULE__
      import Kvasir.Agent.Entity, only: [entity: 1, entity: 2]
    end
  end

  defmacro entity(type, opts \\ [])

  defmacro entity([do: block], _) do
    quote location: :keep do
      import Kvasir.Agent.Entity, only: []
      Module.register_attribute(__MODULE__, :fields, accumulate: true)

      try do
        import Kvasir.Agent.Entity.Definition,
          only: [
            property: 1,
            property: 2,
            property: 3,
            entity: 2,
            entity: 3,
            entities: 2
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
      @impl Kvasir.Agent.Entity
      @spec base(term) :: term
      def base(_id), do: %@__struct__{}

      defoverridable base: 1

      if @has_base do
        def base(_id), do: @base
      end

      @doc false
      @spec __entity__(atom) :: term
      def __entity__(:config),
        do: %{
          struct: @__struct__,
          fields: @struct_fields
        }

      def __entity__(:struct), do: @__struct__
      def __entity__(:fields), do: @struct_fields
    end
  end

  defmacro __before_compile__(env) do
    quote do
      @doc false
      @impl Kvasir.Agent.Entity
      @spec apply(term, term) :: {:ok, term} | {:error, atom}
      unquote(Kvasir.Agent.Mutator.gen_apply(env))

      @doc false
      @impl Kvasir.Agent.Entity
      @spec execute(term, term) :: :ok | {:ok, map} | {:ok, [map]} | {:error, atom}
      unquote(Kvasir.Agent.Mutator.gen_exec(env))
    end
  end
end
