defmodule Kvasir.Agent.Cache do
  @callback init(agent :: module, partition :: non_neg_integer(), opts :: Keyword.t()) ::
              :ok | {:ok, map}

  @callback track_command(agent :: module, partition :: non_neg_integer(), id :: term) ::
              {:ok, non_neg_integer()} | {:error, atom}

  @callback load(agent :: module, partition :: non_neg_integer(), id :: term) ::
              {:ok, Kvasir.Offset.t(), map} | {:error, atom}
  @callback save(
              agent :: module,
              partition :: non_neg_integer(),
              id :: term,
              data :: map,
              offset :: Kvasir.Offset.t(),
              command_counter :: non_neg_integer()
            ) ::
              :ok | {:error, atom}
  @callback delete(agent :: module, partition :: non_neg_integer(), id :: term) ::
              :ok | {:error, atom}
end
