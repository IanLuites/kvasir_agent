defmodule Kvasir.Agent.Registry.Local do
  import Kvasir.Agent.Helpers, only: [registry: 1, supervisor: 1]
  @behaviour Kvasir.Agent.Registry

  @impl Kvasir.Agent.Registry
  def start_child(config = %{agent: agent}, id) do
    via_name = {:via, Registry, {registry(agent), {agent, id}}}
    supervisor = supervisor(agent)

    case Supervisor.start_child(supervisor, %{
           id: {:agent, id},
           start: {Kvasir.Agent.Instance, :start_agent, [config, id, [name: via_name]]},
           restart: :transient
         }) do
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, :already_present} -> Supervisor.restart_child(supervisor, {:agent, id})
      reply -> reply
    end
  end

  def whereis(agent, id) do
    with {pid, _} <- List.first(Registry.lookup(registry(agent), {agent, id})) do
      pid
    end
  end
end
