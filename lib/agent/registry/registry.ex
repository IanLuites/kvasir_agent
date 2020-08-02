defmodule Kvasir.Agent.Registry do
  @callback start_child(
              agent :: module,
              partition :: non_neg_integer,
              id :: term
            ) :: {:ok, pid} | {:error, atom}

  @callback start_child(
              agent :: module,
              partition :: non_neg_integer,
              id :: term,
              offset :: Kvasir.Offset.t(),
              state :: term,
              cache :: term
            ) :: {:ok, pid} | {:error, atom}
end
