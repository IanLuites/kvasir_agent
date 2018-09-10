defmodule Kvasir.Agent.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = []

    Kvasir.Agent.Cache.ETS.load(nil, nil)

    opts = [strategy: :one_for_one, name: Kvasir.Agent.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
