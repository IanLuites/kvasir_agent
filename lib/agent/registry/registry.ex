defmodule Kvasir.Agent.Registry do
  @callback start_child(
              config :: map,
              id :: term
            ) :: {:ok, pid} | {:error, atom}
end
