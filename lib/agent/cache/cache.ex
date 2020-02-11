defmodule Kvasir.Agent.Cache do
  @callback init(agent :: module, opts :: Keyword.t()) :: :ok | {:ok, map}
  @callback load(agent :: module, id :: term) :: {:ok, Kvasir.Offset.t(), map} | {:error, atom}
  @callback save(agent :: module, id :: term, data :: map, offset :: Kvasir.Offset.t()) ::
              :ok | {:error, atom}
  @callback delete(agent :: module, id :: term) ::
              :ok | {:error, atom}
end
