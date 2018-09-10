defmodule Kvasir.Agent.Manager do
  use GenServer
  import Kvasir.Agent.Helpers, only: [manager: 1]

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: manager(config.agent))
  end

  def dispatch(agent, command = %{id: id}) do
    opts = []
    timeout = opts[:timeout] || 5_000

    with :ok <- GenServer.call(manager(agent), {:command, id, command}) do
      ref = command.__meta__.id

      receive do
        {:command, ^ref, response} -> response
      after
        timeout -> {:error, :command_timeout}
      end
    end
  end

  def inspect(config, id) do
    with {:ok, agent} <- Kvasir.Agent.Supervisor.open(config, id) do
      GenServer.call(agent, :inspect)
    end
  end

  @impl GenServer
  def init(config) do
    spawn(fn ->
      config.topic
      |> config.client.stream()
      |> Enum.each(fn event ->
        if agent = config.registry.whereis(config.agent, event.__meta__.key) do
          send(agent, {:event, event})
        end
      end)
    end)

    {:ok, config}
  end

  @impl GenServer
  def handle_call({:command, id, command}, {from, _ref}, config) do
    with {:ok, agent} <- Kvasir.Agent.Supervisor.open(config, id) do
      send(agent, {:command, from, command})
      {:reply, :ok, config}
    else
      error -> {:reply, error, config}
    end
  end
end
