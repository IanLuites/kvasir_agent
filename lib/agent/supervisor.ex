defmodule Kvasir.Agent.Supervisor do
  use Supervisor
  alias Kvasir.Agent.PartitionSupervisor

  def start_link(config = %{agent: agent}) do
    Supervisor.start_link(__MODULE__, config, name: :"#{agent}.Supervisor")
  end

  def open(registry, agent, partition, id) do
    registry.start_child(agent, partition, id)
  end

  def count(agent, partitions) do
    0..(partitions - 1)
    |> Enum.map(&PartitionSupervisor.count(agent, &1))
    |> Enum.sum()
  end

  def list(agent, partitions) do
    Enum.flat_map(
      0..(partitions - 1),
      fn p ->
        p
        |> agent.__registry__()
        |> Registry.select([{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}])
        |> Enum.map(&(&1 |> elem(0)))
      end
    )
  end

  def whereis(agent, partition, id) do
    case partition |> agent.__registry__() |> Registry.lookup(id) do
      [{pid, _}] -> pid
      _ -> nil
    end
  end

  def alive?(config, partition, id), do: whereis(config, partition, id) != nil

  # @spec init(module, module) ::
  def init(config = %{source: source}) do
    partitions = source.__topics__()[config.topic].partitions

    children =
      Enum.map(0..(partitions - 1), fn p ->
        %{
          id: :"supervisor#{p}",
          start: {PartitionSupervisor, :start_link, [config, p]},
          type: :supervisor
        }
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
