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
end
