defmodule Kvasir.Agent.Cache do
  @callback load(agent :: module, id :: term) :: map | nil
  @callback save(agent :: module, id :: term, data :: map) :: :ok | {:error, atom}
end