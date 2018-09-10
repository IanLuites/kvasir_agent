defmodule Kvasir.Agent.Supervisor do
  use Supervisor
  import Kvasir.Agent.Helpers

  def start_link(config = %{agent: agent}) do
    Supervisor.start_link(__MODULE__, config, name: supervisor(agent))
  end

  def open(config = %{registry: registry}, id), do: registry.start_child(config, id)

  # @spec init(module, module) ::
  def init(config = %{agent: agent}) do
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

    Supervisor.init(children, strategy: :one_for_one)
  end
end
