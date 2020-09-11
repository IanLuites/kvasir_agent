defmodule Kvasir.Agent.ObjectValue do
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

    def track_properties(caller, name, type, opts) do
      t = Macro.expand(type, caller)

      force_load!(t)

      if :erlang.function_exported(t, :__object_value__, 1) do
        Kvasir.Agent.Mutator.add_object_value(caller, name, t)
      end

      case Macro.expand(opts[:auto], caller) do
        {:set, command} ->
          cmd = Macro.expand(command, caller)
          Code.ensure_compiled(cmd)
          Code.ensure_loaded(cmd)
          Kvasir.Agent.Mutator.add_setter(caller, cmd, name, name)

        {:{}, _, [:set, command, field]} ->
          cmd = Macro.expand(command, caller)
          Code.ensure_compiled(cmd)
          Code.ensure_loaded(cmd)
          Kvasir.Agent.Mutator.add_setter(caller, cmd, name, field)

        {:{}, _, [:collect, add, remove]} ->
          add_cmd = Macro.expand(add, caller)
          Code.ensure_compiled(add_cmd)
          Code.ensure_loaded(add_cmd)
          remove_cmd = Macro.expand(remove, caller)
          Code.ensure_compiled(remove_cmd)
          Code.ensure_loaded(remove_cmd)
          Kvasir.Agent.Mutator.add_collector(caller, add_cmd, remove_cmd, name, type, [])

        {:{}, _, [:collect, add, remove, o]} ->
          add_cmd = Macro.expand(add, caller)
          Code.ensure_compiled(add_cmd)
          Code.ensure_loaded(add_cmd)
          remove_cmd = Macro.expand(remove, caller)
          Code.ensure_compiled(remove_cmd)
          Code.ensure_loaded(remove_cmd)
          Kvasir.Agent.Mutator.add_collector(caller, add_cmd, remove_cmd, name, type, o)

        _ ->
          :ok
      end
    end

    defmacro property(name, type \\ :string, opts \\ []) do
      track_properties(__CALLER__, name, type, opts)
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
      use UTCDateTime

      import Kvasir.Agent.ObjectValue,
        only: [object_value: 1, object_value: 2, version: 1, version: 2, upgrade: 2]

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
    Definition.track_properties(__CALLER__, nil, type, opts)
    Module.put_attribute(__CALLER__.module, :manual, opts[:manual] || false)

    quote do
      @__type__ unquote(type)
      @__opts__ unquote(Macro.escape(opts))
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
      unless unquote(Module.get_attribute(env.module, :manual)) do
        @doc false
        @spec generate_apply([atom]) :: term
        def generate_apply(path) do
          Kvasir.Agent.Mutator.generate_apply(
            nil,
            __object_value__(:events),
            __object_value__(:object_values),
            [],
            __object_value__(:setters),
            __object_value__(:collectors),
            path
          )
        end

        @doc false
        @spec generate_execution([atom]) :: term
        def generate_execution(path) do
          Kvasir.Agent.Mutator.generate_execution(
            nil,
            __object_value__(:executes),
            __object_value__(:object_values),
            [],
            __object_value__(:setters),
            __object_value__(:collectors),
            path
          )
        end
      end

      @doc false
      @spec __encode__(term) :: {Version.t(), term}
      unquote(Kvasir.Agent.Mutator.gen_encode(env))

      @doc false
      @spec __decode__({Version.t(), term}) :: term
      unquote(Kvasir.Agent.Mutator.gen_decode(env))

      @version_history Enum.sort(@version, &(Version.compare(elem(&1, 0), elem(&2, 0)) != :gt))
      @current_version @version_history
                       |> List.last()
                       |> elem(0)

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
      def __object_value__(:version), do: @current_version
      def __object_value__(:history), do: @version_history

      def __object_value__(:events) do
        unquote(Macro.escape(Mutator.events(env)))
      end

      def __object_value__(:executes) do
        unquote(Macro.escape(Mutator.executes(env)))
      end

      def __object_value__(:object_values) do
        unquote(Macro.escape(Mutator.object_values(env)))
      end

      def __object_value__(:setters) do
        unquote(Macro.escape(Mutator.setters(env)))
      end

      def __object_value__(:collectors) do
        unquote(Macro.escape(Mutator.collectors(env)))
      end

      @doc ~S"""
      Upgrade object value state from older to current version.

      ## Examples

      ```elixir
      iex> upgrade(#Version<1.0.0>, %ObjectValue{...})
      ```
      """
      @spec upgrade(Version.t(), map) :: {:ok, map} | {:error, atom}
      def upgrade(version, state)
      unquote(upgrades)
      def upgrade(_, state), do: {:ok, state}
    end
  end
end
