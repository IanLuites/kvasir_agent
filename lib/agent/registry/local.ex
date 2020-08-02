defmodule Kvasir.Agent.Registry.Local do
  @behaviour Kvasir.Agent.Registry

  @impl Kvasir.Agent.Registry
  def start_child(agent, partition, id) do
    child = {:agent, id}
    via_name = {:via, Registry, {agent.__registry__(partition), id}}
    supervisor = agent.__supervisor__(partition)

    case DynamicSupervisor.start_child(supervisor, %{
           id: child,
           start: {Kvasir.Agent.Instance, :start_agent, [agent, partition, id, [name: via_name]]},
           restart: :transient
         }) do
      {:error, {:already_started, pid}} -> {:ok, pid}
      # {:error, :already_present} -> DynamicSupervisor.restart_child(supervisor, child)
      reply -> reply
    end
  end

  @impl Kvasir.Agent.Registry
  def start_child(agent, partition, id, offset, state, cache) do
    child = {:agent, id}
    via_name = {:via, Registry, {agent.__registry__(partition), id}}
    supervisor = agent.__supervisor__(partition)

    case DynamicSupervisor.start_child(supervisor, %{
           id: child,
           start:
             {Kvasir.Agent.Instance, :pre_start_agent,
              [agent, partition, id, offset, state, cache, [name: via_name]]},
           restart: :transient
         }) do
      {:error, {:already_started, pid}} -> {:ok, pid}
      # {:error, :already_present} -> DynamicSupervisor.restart_child(supervisor, child)
      reply -> reply
    end
  end

  def whereis(agent, partition, id) do
    with {pid, _} <- List.first(Registry.lookup(agent.__registry__(partition), id)) do
      pid
    end
  end
end
