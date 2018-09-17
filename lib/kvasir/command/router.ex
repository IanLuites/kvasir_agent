defmodule Kvasir.Command.Router do
  require Logger

  defmacro __using__(_opts \\ []) do
    quote location: :keep do
      use Kvasir.Command.Dispatcher
      require Kvasir.Command.Router
      import Kvasir.Command.Router, only: [dispatch: 1]
      Module.register_attribute(__MODULE__, :dispatch, accumulate: true)
      @before_compile Kvasir.Command.Router
    end
  end

  defmacro dispatch(opts) do
    env = __CALLER__
    to = opts[:to] || raise "Need to set dispatch target with `to:`."
    namespace = if ns = opts[:namespace], do: inspect(Macro.expand(ns, env)), else: ""
    match = opts |> Keyword.get(:in, []) |> Enum.map(&inspect(Macro.expand(&1, env)))

    quote do
      Module.put_attribute(
        __MODULE__,
        :dispatch,
        {unquote(to), unquote(namespace), unquote(match)}
      )
    end
  end

  defmacro __before_compile__(env) do
    dispatches = Module.get_attribute(env.module, :dispatch)
    if dispatches == [], do: Logger.warn(fn -> "#{env.module}: No dispatches set." end)

    # dispatch =
    #   Enum.reduce(
    #     dispatches,
    #     quote do
    #       defp do_match(_, _), do: :ok
    #     end,
    #     fn
    #       {to, namespace, []}, acc ->
    #         quote do
    #           defp do_match(unquote(namespace) <> _, command), do: unquote(to).dispatch(command)
    #           unquote(acc)
    #         end

    #       {to, namespace, values}, acc ->
    #         quote do
    #           defp do_match(ns = unquote(namespace) <> _, command) when ns in unquote(values),
    #             do: unquote(to).dispatch(command)

    #           unquote(acc)
    #         end
    #     end
    #   )

    quote do
      @spec dispatch_match(list, String.t(), Kvasir.Command.t()) :: :ok | {:error, atom}
      defp dispatch_match([], _, _), do: :ok

      defp dispatch_match([dispatch | tail], type, command) do
        to = do_match(dispatch, type)

        cond do
          command.__meta__.dispatch == :multi and not is_nil(to) ->
            to.dispatch(command)
            dispatch_match(tail, type, command)

          not is_nil(to) ->
            to.dispatch(command)

          :no_match ->
            dispatch_match(tail, type, command)
        end
      end

      @spec do_match({module, String.t(), [String.t()]}, String.t()) :: module | nil
      defp do_match(a = {to, ns, s}, c) do
        cond do
          not String.starts_with?(c, ns) -> nil
          s == [] or c in s -> to
          :no_match -> nil
        end
      end

      @impl Kvasir.Command.Dispatcher
      def do_dispatch(command = %type{}),
        do: dispatch_match(@dispatch, inspect(type), command)
    end
  end
end
