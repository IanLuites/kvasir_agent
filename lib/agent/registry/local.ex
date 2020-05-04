defmodule Kvasir.Agent.Registry.Local do
  @behaviour Kvasir.Agent.Registry

  @impl Kvasir.Agent.Registry
  def start_child(agent, partition, id) do
    child = {:agent, id}
    via_name = {:via, Registry, {agent.__registry__(partition), id}}
    supervisor = agent.__supervisor__(partition)

    case Supervisor.start_child(supervisor, %{
           id: child,
           start: {Kvasir.Agent.Instance, :start_agent, [agent, partition, id, [name: via_name]]},
           restart: :transient
         }) do
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, :already_present} -> Supervisor.restart_child(supervisor, child)
      reply -> reply
    end
  end

  def whereis(agent, partition, id) do
    with {pid, _} <- List.first(Registry.lookup(agent.__registry__(partition), id)) do
      pid
    end
  end
end
