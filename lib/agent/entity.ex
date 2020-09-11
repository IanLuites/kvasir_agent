defmodule Kvasir.Agent.Entity do
  defmodule Definition do
    import Kvasir.Event, only: [property: 4]

    defp force_load!(module) do
      if not is_atom(module) or match?(":" <> _, inspect(module)) do
        :ok
      else
        force_load_try!(module)
      end
    end

    defp force_load_try!(module, attempt \\ 0)
    defp force_load_try!(module, 5), do: raise("Can't load: #{module}")

    defp force_load_try!(module, attempt) do
      Code.ensure_compiled(module)

      if Code.ensure_loaded?(module) do
        :ok
      else
        :timer.sleep(attempt * 100)
        force_load_try!(module, attempt + 1)
      end
    end

    defmacro property(name, type \\ :string, opts \\ []) do
      t = Macro.expand(type, __CALLER__)
      force_load!(t)

      opts =
        if :erlang.function_exported(t, :__object_value__, 1) do
          opts |> Keyword.put(:object_value, t) |> Keyword.put(:relation, {1, 1})
        else
          opts
        end

      x =
        if :erlang.function_exported(t, :__object_value__, 1) do
          quote do
            Module.put_attribute(__MODULE__, :object_values, {unquote(name), unquote(t)})
          end
        end

      x =
        case Macro.expand(opts[:auto], __CALLER__) do
          {:set, command} ->
            cmd = Macro.expand(command, __CALLER__)
            Code.ensure_compiled(cmd)
            Code.ensure_loaded(cmd)

            quote do
              unquote(x)

              Module.put_attribute(
                __MODULE__,
                :setters,
                {unquote(cmd), unquote(name), unquote(name)}
              )
            end

          {:{}, _, [:set, command, field]} ->
            cmd = Macro.expand(command, __CALLER__)
            Code.ensure_compiled(cmd)
            Code.ensure_loaded(cmd)

            quote do
              unquote(x)

              Module.put_attribute(
                __MODULE__,
                :setters,
                {unquote(cmd), unquote(name), unquote(field)}
              )
            end

          {:{}, _, [:collect, add, remove]} ->
            add_cmd = Macro.expand(add, __CALLER__)
            Code.ensure_compiled(add_cmd)
            Code.ensure_loaded(add_cmd)
            remove_cmd = Macro.expand(remove, __CALLER__)
            Code.ensure_compiled(remove_cmd)
            Code.ensure_loaded(remove_cmd)

            quote do
              unquote(x)

              Module.put_attribute(
                __MODULE__,
                :collectors,
                {unquote(add_cmd), unquote(remove_cmd), unquote(name), unquote(type), []}
              )
            end

          {:{}, _, [:collect, add, remove, o]} ->
            add_cmd = Macro.expand(add, __CALLER__)
            Code.ensure_compiled(add_cmd)
            Code.ensure_loaded(add_cmd)
            remove_cmd = Macro.expand(remove, __CALLER__)
            Code.ensure_compiled(remove_cmd)
            Code.ensure_loaded(remove_cmd)

            quote do
              unquote(x)

              Module.put_attribute(
                __MODULE__,
                :collectors,
                {unquote(add_cmd), unquote(remove_cmd), unquote(name), unquote(type),
                 unquote(Macro.escape(o))}
              )
            end

          _ ->
            x
        end

      quote do
        unquote(x)
        unquote(property(__CALLER__, name, type, opts))
      end
    end

    defmacro entity(name, entity, opts \\ []) do
      aggregate = Macro.expand(opts[:in], __CALLER__)
      entity = Macro.expand(entity, __CALLER__)
      force_load!(aggregate)
      force_load!(entity)

      key = aggregate.__aggregate__(:key)
      optional = Keyword.get(opts, :optional, not Keyword.get(opts, :required, false))

      opts =
        Keyword.merge(
          [
            optional: optional,
            entity: entity,
            relation: {:*, if(optional, do: 0..1, else: 1)}
          ],
          Keyword.put(opts, :in, aggregate)
        )

      quote do
        unquote(property(__CALLER__, name, key, Macro.escape(opts)))
      end
    end

    defmacro entities(name, entity, opts \\ []) do
      entity = Macro.expand(entity, __CALLER__)
      force_load!(entity)

      opts =
        Keyword.merge(opts,
          default: {:%{}, [], []},
          value: entity,
          entity: entity,
          relation: {1, :*}
        )

      quote do
        Module.put_attribute(__MODULE__, :entities, {unquote(name), unquote(entity)})
        unquote(property(__CALLER__, name, :map, opts))
      end
    end
  end

  @callback base(id :: any) :: any
  @callback apply(state :: any, event :: map) :: {:ok, any} | {:error, atom}
  @callback execute(state :: any, command :: map) ::
              :ok | {:ok, map} | {:ok, [map]} | {:error, atom}

  @callback __encode__(term) :: {Version.t(), term}
  @callback __decode__({Version.t(), term}) :: term

  defmacro __using__(opts \\ []) do
    Kvasir.Agent.Mutator.init(__CALLER__)

    quote location: :keep do
      @base unquote(opts[:base])
      @has_base unquote(Keyword.has_key?(opts, :base))
      @behaviour Kvasir.Agent.Entity
      @before_compile unquote(__MODULE__)
      @__struct__ unquote(opts[:struct]) || __MODULE__
      use UTCDateTime
      import Kvasir.Agent.Entity, only: [entity: 1, entity: 2, version: 1, version: 2, upgrade: 2]

      Module.register_attribute(__MODULE__, :version, persist: true, accumulate: true)
      @version {Version.parse!("1.0.0"), nil, "Create entity."}
    end
  end

  defmacro version(version, updated \\ nil) do
    precision = version |> String.graphemes() |> Enum.count(&(&1 == "."))
    v = Version.parse!(version <> String.duplicate(".0", 2 - precision))

    quote do
      @version {unquote(Macro.escape(v)), unquote(updated),
                elem(Module.delete_attribute(__MODULE__, :doc) || {0, ""}, 1)}
    end
  end

  defmacro upgrade(version, do: block) do
    upgrades = Module.get_attribute(__CALLER__.module, :upgrades, [])
    func = :"__upgrade_#{Enum.count(upgrades)}"
    Module.put_attribute(__CALLER__.module, :upgrades, [{version, func} | upgrades])

    quote do
      defp unquote(func)(unquote(Macro.var(:state, __CALLER__.context))) do
        unquote(block)
      end
    end
  end

  defmacro entity(opts \\ [], block)

  defmacro entity(opts, do: block) do
    creation =
      if c = opts[:creation] do
        creation_opts = [
          validate: opts[:validate],
          tag:
            Keyword.get(
              opts,
              :tag,
              __CALLER__.module |> Module.split() |> List.last() |> Macro.underscore()
            )
        ]

        t = Macro.expand(c, __CALLER__)

        Code.ensure_compiled(t)
        Code.ensure_loaded(t)

        quote do
          _ = @base
          _ = @has_base
          @base nil
          @has_base true
          Module.put_attribute(
            __MODULE__,
            :creation,
            {unquote(t), unquote(Macro.escape(creation_opts))}
          )
        end
      end

    quote location: :keep do
      unquote(creation)
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
            entities: 2,
            entities: 3
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

      @version_history Enum.sort(@version, &(Version.compare(elem(&1, 0), elem(&2, 0)) != :gt))
      @current_version @version_history
                       |> List.last()
                       |> elem(0)

      @doc false
      @spec __entity__(atom) :: term
      def __entity__(:config),
        do: %{
          struct: @__struct__,
          fields: @struct_fields
        }

      def __entity__(:struct), do: @__struct__
      def __entity__(:fields), do: @struct_fields
      def __entity__(:version), do: @current_version
      def __entity__(:history), do: @version_history
    end
  end

  defmacro __before_compile__(env) do
    alias Kvasir.Agent.Mutator

    upgrades =
      env.module
      |> Module.get_attribute(:upgrades, [])
      |> Enum.reduce(nil, fn {version, func}, acc ->
        quote do
          def upgrade(
                %Version{
                  major: unquote(Macro.var(:major, nil)),
                  minor: unquote(Macro.var(:minor, nil)),
                  patch: unquote(Macro.var(:patch, nil))
                },
                state
              )
              when unquote(Mutator.guard(version)) do
            _ = unquote(Macro.var(:major, nil))
            _ = unquote(Macro.var(:minor, nil))
            _ = unquote(Macro.var(:patch, nil))
            unquote(func)(state)
          end

          unquote(acc)
        end
      end)

    quote do
      @doc false
      @impl Kvasir.Agent.Entity
      @spec apply(term, term) :: {:ok, term} | {:error, atom}
      unquote(Kvasir.Agent.Mutator.gen_apply(env))

      @doc false
      @impl Kvasir.Agent.Entity
      @spec execute(term, term) :: :ok | {:ok, map} | {:ok, [map]} | {:error, atom}
      unquote(Kvasir.Agent.Mutator.gen_exec(env))

      @doc false
      @impl Kvasir.Agent.Entity
      @spec __encode__(term) :: {Version.t(), term}
      unquote(Kvasir.Agent.Mutator.gen_encode(env))

      @doc false
      @impl Kvasir.Agent.Entity
      @spec __decode__({Version.t(), term}) :: term
      unquote(Kvasir.Agent.Mutator.gen_decode(env))

      @doc ~S"""
      Upgrade entity state from older to current version.

      ## Examples

      ```elixir
      iex> upgrade(#Version<1.0.0>, %Entity{...})
      ```
      """
      @spec upgrade(Version.t(), map) :: {:ok, map} | {:error, atom}
      def upgrade(version, state)
      unquote(upgrades)
      def upgrade(_, state), do: {:ok, state}
    end
  end
end
