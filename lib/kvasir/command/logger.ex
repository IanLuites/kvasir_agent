defmodule Kvasir.Command.Logger do
  @callback log_command(Kvasir.Command.t()) :: :ok
  @callback log_error(Kvasir.Command.t(), atom) :: :ok

  defmacro __using__(opts \\ []) do
    dispatcher = opts[:dispatcher] || raise "Need to config `dispatcher:`."
    d_name = dispatcher |> Macro.expand(__ENV__) |> inspect

    quote location: :keep do
      use Kvasir.Command.Dispatcher
      require Logger
      @behaviour Kvasir.Command.Logger

      @doc false
      @impl Kvasir.Command.Dispatcher
      def do_dispatch(command) do
        result = unquote(dispatcher).dispatch(command)

        spawn(fn ->
          case result do
            :ok -> log_command(command)
            {:ok, updated_command} -> log_command(updated_command)
            {:error, reason} -> log_error(command, reason)
          end
        end)

        result
      end

      @doc false
      @impl Kvasir.Command.Logger
      def log_command(command),
        do: Logger.debug(fn -> "#{unquote(d_name)}: #{inspect(command)}" end)

      @doc false
      @impl Kvasir.Command.Logger
      def log_error(command, reason),
        do: Logger.error(fn -> "#{unquote(d_name)}: #{inspect(command)} (#{reason})" end)

      defoverridable log_command: 1, log_error: 2
    end
  end
end
