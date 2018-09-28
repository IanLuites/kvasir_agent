defmodule Kvasir.Agent do
  @moduledoc """
  Documentation for Kvasir.Agent.
  """

  defmacro __using__(opts \\ []) do
    client = opts[:client] || raise "Need to pass the Kvasir client."
    topic = opts[:topic] || raise "Need to pass the Kafka topic."
    model = opts[:model] || raise "Need to pass a Kvasir model."
    cache = Kvasir.Agent.Config.cache!(opts)
    registry = Kvasir.Agent.Config.registry!(opts)

    auto =
      unless opts[:auto_start] == false do
        auto_start = Module.concat(Kvasir.Util.AutoStart, __CALLER__.module)

        quote do
          defmodule unquote(auto_start) do
            @moduledoc false

            @doc false
            @spec client :: module
            def client, do: unquote(client)

            @doc false
            @spec module :: module
            def module, do: unquote(__CALLER__.module)
          end
        end
      end

    # Disabled environments
    if Mix.env() in (opts[:disable] || []) do
      nil
    else
      quote do
        use Kvasir.Command.Dispatcher
        alias Kvasir.Agent
        alias Kvasir.Agent.{Manager, Supervisor}

        @client unquote(client)
        @topic unquote(topic)
        @cache unquote(cache)
        @registry unquote(registry)
        @model unquote(model)

        unquote(auto)

        def child_spec(_opts \\ []), do: Agent.child_spec(__agent__(:config))

        def open(id), do: Supervisor.open(__agent__(:config), id)
        def do_dispatch(command), do: Manager.dispatch(__MODULE__, command)
        def inspect(id), do: Manager.inspect(__agent__(:config), id)

        @doc false
        def __agent__(:config),
          do: %{
            agent: __MODULE__,
            cache: @cache,
            client: @client,
            model: @model,
            registry: @registry,
            topic: @topic
          }

        def __agent__(:topic), do: @topic
      end
    end
  end

  def child_spec(config = %{agent: agent}) do
    %{
      id: agent,
      start: {Kvasir.Agent.Supervisor, :start_link, [config]}
    }
  end

  @doc ~S"""
  Index all events and other registries.
  """
  @spec create_registries :: :ok
  def create_registries do
    create_command_registry()

    :ok
  end

  defp create_command_registry do
    commands =
      :application.loaded_applications()
      |> Enum.flat_map(fn {app, _, _} ->
        case :application.get_key(app, :modules) do
          :undefined -> []
          {:ok, modules} -> modules
        end
      end)
      |> Enum.filter(&String.starts_with?(to_string(&1), "Elixir.Kvasir.Command.Registry."))

    ensure_unique_commands!(commands)
    registry = Enum.into(commands, %{}, &{&1.type(), &1.module()})

    Code.compiler_options(ignore_module_conflict: true)

    Module.create(
      Kvasir.Command.Registry,
      quote do
        @moduledoc ~S"""
        Kvasir Command Regsitry.
        """

        @doc ~S"""
        Lookup commands.
        """
        @spec lookup(String.t()) :: module | nil
        def lookup(type), do: Map.get(commands(), type)

        @doc ~S"""
        List all commands.
        """
        @spec list :: [module]
        def list, do: Map.values(commands())

        @doc ~S"""
        List all commands matching the filter.
        """
        @spec list(filter :: Keyword.t()) :: [module]
        def list(filter) do
          commands = commands()

          commands =
            if ns = filter[:namespace] do
              ns = to_string(ns) <> "."
              Enum.filter(commands, &String.starts_with?(to_string(elem(&1, 1)), ns))
            else
              commands
            end

          commands =
            if ns = filter[:type_namespace] do
              ns = ns <> "."
              Enum.filter(commands, &String.starts_with?(elem(&1, 0), ns))
            else
              commands
            end

          Enum.map(commands, &elem(&1, 1))
        end

        @doc ~S"""
        All available commands indexed on type.
        """
        @spec commands :: map
        def commands, do: unquote(Macro.escape(registry))
      end,
      Macro.Env.location(__ENV__)
    )

    Code.compiler_options(ignore_module_conflict: false)
  end

  defp ensure_unique_commands!(commands) do
    duplicates =
      commands
      |> Enum.group_by(& &1.type)
      |> Enum.filter(&(Enum.count(elem(&1, 1)) > 1))

    if duplicates == [] do
      :ok
    else
      error =
        duplicates
        |> Enum.map(fn {k, v} ->
          "  \"#{k}\":\n#{v |> Enum.map(&"    * #{inspect(&1.module)}") |> Enum.join("\n")}"
        end)
        |> Enum.join("\n\n")

      raise "Duplicate Command Types\n\n" <> error
    end
  end
end
