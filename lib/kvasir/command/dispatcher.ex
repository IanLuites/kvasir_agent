defmodule Kvasir.Command.Dispatcher do
  @callback dispatch(Kvasir.Command.t(), Keyword.t()) ::
              {:ok, Kvasir.Command.t()} | {:error, atom}
  @callback do_dispatch(Kvasir.Command.t()) :: {:ok, Kvasir.Command.t()} | {:error, atom}

  @default_timeout 5_000

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
    command = set_instance(command, opts[:instance])

    case set_wait(command, opts[:wait]) do
      error = {:error, _} ->
        error

      command ->
        command
        |> set_timeout(opts[:timeout])
        |> set_id()
        |> set_dispatch(opts[:dispatch] || :single)
        |> dispatcher.do_dispatch()
    end
  end

  def dispatch(dispatcher, command, _opts), do: dispatcher.do_dispatch(command)

  defp set_dispatch(command, type),
    do:
      command |> update_meta(:dispatch, type) |> update_meta(:dispatched, NaiveDateTime.utc_now())

  defp set_id(command), do: update_meta(command, :id, generate_id())

  defp set_wait(command, nil), do: command

  defp set_wait(command, wait) when wait in ~w(dispatch execute apply)a,
    do: update_meta(command, :wait, wait)

  defp set_wait(_command, _), do: {:error, :invalid_wait_value}

  defp set_timeout(command, nil), do: update_meta(command, :timeout, @default_timeout)
  defp set_timeout(command, timeout), do: update_meta(command, :timeout, timeout)

  defp set_instance(command = %type{}, nil) do
    if instance = Map.get(command, type.__command__(:instance_id)) do
      update_meta(command, :scope, {:instance, instance})
    else
      update_meta(command, :scope, :global)
    end
  end

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
