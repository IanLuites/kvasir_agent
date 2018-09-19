defmodule Kvasir.Command.Router do
  require Logger

  defmacro __using__(opts \\ []) do
    no_match =
      case opts[:no_match] do
        nil -> :ok
        :error -> {:error, :no_match}
        custom -> custom
      end

    quote location: :keep do
      use Kvasir.Command.Dispatcher
      require Kvasir.Command.Router
      import Kvasir.Command.Router, only: [dispatch: 1, dispatch_match: 4]
      Module.register_attribute(__MODULE__, :dispatch, accumulate: true)
      @before_compile Kvasir.Command.Router
      @no_match unquote(no_match)
    end
  end

  defmacro dispatch(opts) do
    env = __CALLER__
    to = opts[:to] || raise "Need to set dispatch target with `to:`."
    namespace = if ns = opts[:namespace], do: inspect(Macro.expand(ns, env)), else: ""
    include = opts |> Keyword.get(:in, []) |> Enum.map(&inspect(Macro.expand(&1, env)))
    match = Keyword.get(opts, :match, nil)
    scope = Keyword.get(opts, :scope, nil)

    quote do
      Module.put_attribute(
        __MODULE__,
        :dispatch,
        {unquote(to), unquote(namespace), unquote(include), unquote(match), unquote(scope)}
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
      @impl Kvasir.Command.Dispatcher
      def do_dispatch(command = %type{}),
        do: dispatch_match(@dispatch, inspect(type), command, no_match: @no_match)
    end
  end

  @doc false
  @spec dispatch_match(list, String.t(), Kvasir.Command.t(), Keyword.t()) :: :ok | {:error, atom}
  def dispatch_match([], _, _, opts), do: opts[:no_match] || :ok

  def dispatch_match([dispatch | tail], type, command, opts) do
    to = do_match(dispatch, type)

    cond do
      command.__meta__.dispatch == :multi and not is_nil(to) ->
        to.dispatch(command)
        dispatch_match(tail, type, command, opts)

      not is_nil(to) ->
        to.dispatch(command)

      :no_match ->
        dispatch_match(tail, type, command, opts)
    end
  end

  @spec do_match({module, String.t(), [String.t()], Regex.t()}, String.t()) :: module | nil
  defp do_match({to, ns, s, m, scope}, c) do
    cond do
      not String.starts_with?(c, ns) -> nil
      not scope_match?(c, scope) -> nil
      m != nil and not c =~ m -> nil
      s != [] or c not in s -> nil
      :match -> to
    end
  end

  @spec scope_match?(Kvasir.Command.t(), atom) :: boolean
  defp scope_match?(_, nil), do: true
  defp scope_match?(%{__meta__: %{scope: {type, _}}}, scope), do: scope == type
  defp scope_match?(%{__meta__: %{scope: type}}, scope), do: scope == type
end
