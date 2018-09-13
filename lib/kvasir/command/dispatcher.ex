defmodule Kvasir.Command.Dispatcher do
  @callback dispatch(Kvasir.Command.t(), Keyword.t()) :: any
  @callback do_dispatch(Kvasir.Command.t()) :: any

  defmacro __using__(_opts \\ []) do
    quote do
      @behaviour Kvasir.Command.Dispatcher

      @doc ~S"""
      Dispatch a command.
      """
      @impl Kvasir.Command.Dispatcher
      def dispatch(command, opts \\ []),
        do: Kvasir.Command.Dispatcher.dispatch(__MODULE__, command, opts)
    end
  end

  def dispatch(dispatcher, command, opts \\ [])

  def dispatch(dispatcher, command = %{__meta__: %{dispatched: nil}}, opts) do
    command
    |> set_instance(opts[:instance])
    |> set_dispatch()
    |> set_id()
    |> dispatcher.do_dispatch()
  end

  def dispatch(dispatcher, command, _opts), do: dispatcher.do_dispatch(command)

  defp set_dispatch(command), do: update_meta(command, :dispatched, NaiveDateTime.utc_now())

  defp set_id(command), do: update_meta(command, :id, generate_id())

  defp set_instance(command, nil), do: update_meta(command, :scope, :global)
  defp set_instance(command, id), do: update_meta(command, :scope, {:instance, id})

  defp update_meta(command = %{__meta__: meta}, field, value),
    do: %{command | __meta__: Map.put(meta, field, value)}

  @epoch_time "2018-09-01T00:00:00Z"
              |> NaiveDateTime.from_iso8601()
              |> elem(1)
              |> NaiveDateTime.diff(~N[1970-01-01 00:00:00], :microsecond)

  @spec generate_id :: non_neg_integer
  defp generate_id do
    micro = :os.system_time(:microsecond) - @epoch_time
    random = :crypto.strong_rand_bytes(8)
    Base.encode64(<<micro::integer-unsigned-64>> <> random, padding: false)
  end
end
