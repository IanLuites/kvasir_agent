defmodule Kvasir.Agent.Cache do
  @callback load(agent :: module, id :: term) :: {:ok, Kvasir.Offset.t(), map} | {:error, atom}
  @callback save(agent :: module, id :: term, data :: map, offset :: Kvasir.Offset.t()) ::
              :ok | {:error, atom}
end
