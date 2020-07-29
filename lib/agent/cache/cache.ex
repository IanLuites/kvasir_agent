defmodule Kvasir.Agent.Cache do
  @type ref :: term()

  @callback init(agent :: module, partition :: non_neg_integer(), opts :: Keyword.t()) ::
              :ok | {:ok, map}

  @callback cache(agent :: module, partition :: non_neg_integer(), id :: term) ::
              {:ok, ref}

  @callback track_command(ref) :: :ok | {:error, atom}

  @callback load(ref) ::
              {:ok, Kvasir.Offset.t(), map}
              | :no_previous_state
              | {:error, atom}

  @callback save(
              cache :: ref,
              data :: map,
              offset :: Kvasir.Offset.t()
            ) ::
              :ok | {:error, atom}

  @callback delete(ref) :: :ok | {:error, atom}
end
