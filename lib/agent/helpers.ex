defmodule Kvasir.Agent.Helpers do
  @moduledoc false

  @doc false
  @spec supervisor(module) :: module
  def supervisor(agent), do: Module.concat(agent, Supervisor)

  @doc false
  @spec manager(module) :: module
  def manager(agent), do: Module.concat(agent, Manager)

  @doc false
  @spec registry(module) :: module
  def registry(agent), do: Module.concat(agent, Registry)
end
