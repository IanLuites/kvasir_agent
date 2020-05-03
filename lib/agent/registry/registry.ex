defmodule Kvasir.Agent.Registry do
  @callback start_child(
              agent :: module,
              partition :: non_neg_integer,
              id :: term
            ) :: {:ok, pid} | {:error, atom}
end
