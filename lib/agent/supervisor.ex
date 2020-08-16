defmodule Kvasir.Agent.Supervisor do
  # use Supervisor
  alias Kvasir.Agent.PartitionSupervisor
  require Logger

  defmodule Monitor do
    def start_link(agent) do
      {:ok, spawn_link(__MODULE__, :monitor, [agent])}
    end

    def monitor(agent) do
      Process.flag(:trap_exit, true)

      Logger.info(fn -> "Kvasir Agents: Starting #{inspect(agent)} supervisor." end)

      do_monitor(agent)
    end

    defp do_monitor(agent) do
      receive do
        {:EXIT, _, reason} ->
          Logger.info(fn ->
            "Kvasir Agents: Stopped<#{inspect(reason)}> #{inspect(agent)} supervisor."
          end)

        _ ->
          do_monitor(agent)
      end
    end
  end

  @spec start_link(%{agent: any, source: any, topic: any}) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(config = %{agent: agent, source: source, topic: topic}) do
    # Supervisor.start_link(__MODULE__, config, name: :"#{agent}.Supervisor")
    with {:ok, pid} <-
           DynamicSupervisor.start_link(strategy: :one_for_one, name: :"#{agent}.Supervisor") do
      partitions = source.__topics__()[topic].partitions

      DynamicSupervisor.start_child(pid, %{
        id: :monitor,
        start: {Monitor, :start_link, [agent]},
        type: :worker
      })

      Enum.each(0..(partitions - 1), fn p ->
        DynamicSupervisor.start_child(pid, %{
          id: :"supervisor#{p}",
          start: {PartitionSupervisor, :start_link, [config, p]},
          type: :supervisor
        })
      end)

      {:ok, pid}
    end
  end

  def open(registry, agent, partition, id) do
    registry.start_child(agent, partition, id)
  end

  def preload(registry, agent, partition, id, offset, state, cache) do
    registry.start_child(agent, partition, id, offset, state, cache)
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

  # def init(config = %{source: source}) do
  #   partitions = source.__topics__()[config.topic].partitions

  #   children =
  #     Enum.map(0..(partitions - 1), fn p ->
  #       %{
  #         id: :"supervisor#{p}",
  #         start: {PartitionSupervisor, :start_link, [config, p]},
  #         type: :supervisor
  #       }
  #     end)

  #   Supervisor.init(children, strategy: :one_for_one)
  # end
end
