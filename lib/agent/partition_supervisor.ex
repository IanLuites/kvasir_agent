defmodule Kvasir.Agent.PartitionSupervisor do
  use Supervisor

  def start_link(config, partition) do
    Supervisor.start_link(__MODULE__, Map.put(config, :partition, partition))
  end

  def open(registry, agent, partition, id),
    do: registry.start_child(agent, partition, id)

  def count(agent, partition), do: partition |> agent.__registry__() |> Registry.count()

  def list(agent, partition) do
    partition
    |> agent.__registry__
    |> Registry.select([{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}])
    |> Enum.map(&(&1 |> elem(0) |> elem(1)))
  end

  def whereis(agent, partition, id) do
    case partition |> agent.__registry__() |> Registry.lookup({agent, id}) do
      [{pid, _}] -> pid
      _ -> nil
    end
  end

  # @spec init(module, module) ::
  def init(config = %{agent: agent, cache: {cache, cache_opts}, partition: partition}) do
    children = [
      %{
        id: :manager,
        type: :worker,
        start: {Kvasir.Agent.Manager, :start_link, [config, partition]}
      },
      %{
        id: :registry,
        type: :worker,
        start:
          {Registry, :start_link,
           [
             [
               keys: :unique,
               name: agent.__registry__(partition),
               partitions: System.schedulers_online()
             ]
           ]}
      },
      %{
        id: :instance_supervisor,
        type: :supervisor,
        start:
          {DynamicSupervisor, :start_link,
           [[strategy: :one_for_one, name: agent.__supervisor__(partition)]]}
      }
    ]

    case cache.init(agent, partition, agent.config(:cache, cache_opts)) do
      :ok -> Supervisor.init(children, strategy: :rest_for_one)
      {:ok, child} -> Supervisor.init([child | children], strategy: :rest_for_one)
    end
  end
end
