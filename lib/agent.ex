defmodule Kvasir.Agent do
  @moduledoc """
  Documentation for Kvasir.Agent.
  """

  defmacro __using__(opts \\ []) do
    topic = opts[:topic] || raise "Need to pass the Kafka topic."
    client = opts[:client] || raise "Need to pass the Kvasir client."
    cache = Kvasir.Agent.Config.cache!(opts)
    registry = Kvasir.Agent.Config.registry!(opts)

    quote do
      alias Kvasir.Agent
      alias Kvasir.Agent.{Manager, Supervisor}

      def child_spec(_opts \\ []), do: Agent.child_spec(__agent__(:config))

      def open(id), do: Supervisor.open(__agent__(:config), id)
      def dispatch(command), do: Manager.dispatch(__MODULE__, command)
      def inspect(id), do: Manager.inspect(__agent__(:config), id)

      def __agent__(:config),
        do: %{
          agent: __MODULE__,
          cache: unquote(cache),
          client: unquote(client),
          registry: unquote(registry),
          topic: unquote(topic)
        }
    end
  end

  def child_spec(config = %{agent: agent}) do
    %{
      id: agent,
      start: {Kvasir.Agent.Supervisor, :start_link, [config]}
    }
  end
end
