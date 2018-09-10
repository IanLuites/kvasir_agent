defmodule Kvasir.Command.Router do
  @epoch_time "2018-09-01T00:00:00Z"
              |> DateTime.from_iso8601()
              |> elem(1)
              |> DateTime.to_unix()
              |> Kernel.*(1_000_000)

  def dispatch(command = %{__meta__: meta}, opts \\ []) do
    if meta.id do
      command
    else
      %{command | __meta__: %{meta | id: generate_id}}
    end
  end

  @spec generate_id :: non_neg_integer
  defp generate_id do
    micro = :os.system_time(:microsecond) - @epoch_time
    random = :crypto.strong_rand_bytes(8)
    Base.encode64(<<micro::integer-unsigned-64>> <> random, padding: false)
  end
end
