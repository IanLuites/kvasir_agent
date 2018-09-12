defmodule Kvasir.Agent do
  @moduledoc """
  Documentation for Kvasir.Agent.
  """

  defmacro __using__(opts \\ []) do
    client = opts[:client] || raise "Need to pass the Kvasir client."
    topic = opts[:topic] || raise "Need to pass the Kafka topic."
    aggregate = opts[:aggregate] || raise "Need to pass the Kvasir aggregate."
    cache = Kvasir.Agent.Config.cache!(opts)
    registry = Kvasir.Agent.Config.registry!(opts)

    quote do
      use Kvasir.Command.Dispatcher
      alias Kvasir.Agent
      alias Kvasir.Agent.{Manager, Supervisor}

      @client unquote(client)
      @topic unquote(topic)
      @cache unquote(cache)
      @registry unquote(registry)
      @aggregate unquote(aggregate)

      def child_spec(_opts \\ []), do: Agent.child_spec(__agent__(:config))

      def open(id), do: Supervisor.open(__agent__(:config), id)
      def do_dispatch(command), do: Manager.dispatch(__MODULE__, command)
      def inspect(id), do: Manager.inspect(__agent__(:config), id)

      @doc false
      def __agent__(:config),
        do: %{
          agent: __MODULE__,
          aggregate: @aggregate,
          cache: @cache,
          client: @client,
          registry: @registry,
          topic: @topic
        }

      def __agent__(:topic), do: @topic
    end
  end

  def child_spec(config = %{agent: agent}) do
    %{
      id: agent,
      start: {Kvasir.Agent.Supervisor, :start_link, [config]}
    }
  end
end
