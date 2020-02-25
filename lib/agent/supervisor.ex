defmodule Kvasir.Agent.Supervisor do
  use Supervisor
  import Kvasir.Agent.Helpers

  def start_link(config = %{agent: agent}) do
    Supervisor.start_link(__MODULE__, config, name: supervisor(agent))
  end

  def open(config = %{registry: registry}, id), do: registry.start_child(config, id)

  def count(%{agent: agent}), do: agent |> registry() |> Registry.count()

  def list(%{agent: agent}) do
    agent
    |> registry()
    |> Registry.select([{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}])
    |> Enum.map(&(&1 |> elem(0) |> elem(1)))
  end

  def whereis(%{agent: agent}, id), do: agent |> registry() |> Registry.lookup({agent, id})

  def alive?(config, id), do: whereis(config, id) != nil

  # @spec init(module, module) ::
  def init(config = %{agent: agent, cache: {cache, cache_opts}}) do
    children = [
      %{
        id: :manager,
        start: {Kvasir.Agent.Manager, :start_link, [config]}
      },
      %{
        id: :registry,
        start: {Registry, :start_link, [[keys: :unique, name: registry(agent)]]}
      }
    ]

    case cache.init(agent, agent.config(:cache, cache_opts)) do
      :ok -> Supervisor.init(children, strategy: :one_for_one)
      {:ok, child} -> Supervisor.init([child | children], strategy: :one_for_one)
    end
  end
end
