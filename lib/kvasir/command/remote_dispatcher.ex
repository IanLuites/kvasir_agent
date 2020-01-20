defmodule Kvasir.Command.RemoteDispatcher do
  @moduledoc ~S"""
  Remote dispatch allows you to remotely dispatch commands through HTTP.
  """

  @doc ~S"Configure runtime variables."
  @callback config(opts :: Keyword.t()) :: Keyword.t()

  defmacro __using__(opts \\ []) do
    d = Module.concat(__CALLER__.module, Dispatcher)
    dispatcher(d, opts)

    quote do
      @doc ~S"""
      Configure the remote dispatcher.

      ## Examples

      ```elixir
      iex> configure(mode: :http, url: "...")
      :ok
      ```
      """
      @spec configure(Keyword.t()) :: :ok
      def configure(opts \\ []) do
        o = unquote(opts) |> Keyword.merge(opts) |> config()
        unquote(__MODULE__).dispatcher(unquote(d), o)
      end

      ### Remote Dispatch Behavior ###

      @behaviour unquote(__MODULE__)

      @doc false
      @spec config(opts :: Keyword.t()) :: Keyword.t()
      @impl unquote(__MODULE__)
      def config(opts), do: opts

      defoverridable config: 1

      ### Follow Proper Dispatcher Behaviour ###

      @behaviour Kvasir.Command.Dispatcher

      @doc ~S"""
      Dispatch a command to commander.

      ## Examples

      ```elixir
      iex> dispatch(<cmd>, instance: <id>)
      {:ok, <cmd>}
      ```
      """
      @spec dispatch(Kvasir.Command.t(), Keyword.t()) ::
              {:ok, Kvasir.Command.t()} | {:error, atom}
      @impl Kvasir.Command.Dispatcher
      def dispatch(command, opts \\ []),
        do: Kvasir.Command.Dispatcher.dispatch(__MODULE__, command, opts)

      @doc false
      @spec do_dispatch(Kvasir.Command.t()) :: {:ok, Kvasir.Command.t()} | {:error, atom}
      @impl Kvasir.Command.Dispatcher
      def do_dispatch(command), do: __MODULE__.Dispatcher.do_dispatch(command)

      ### Self Configuration On Load ###

      @on_load :__setup__

      @doc false
      @spec __setup__ :: :ok
      def __setup__, do: configure()
    end
  end

  alias Kvasir.Command.{Encoder, Meta}
  @ua "Kvasir Agent Remote v#{Mix.Project.config()[:version]}"
  @opts headers: [
          {"Content-Type", "kvasir/command"},
          {"User-Agent", @ua}
        ],
        format: :json

  @doc false
  @spec dispatcher(module, Keyword.t()) :: :ok
  def dispatcher(module, opts) do
    if Code.ensure_loaded?(HTTPX) do
      Application.ensure_all_started(:httpx)
      Kvasir.Command.RegistryGenerator.create()

      _backend =
        case opts[:mode] do
          :test -> :test
          _ -> :http
        end

      b_opts =
        case opts[:headers] do
          nil -> @opts
          headers -> Keyword.update!(@opts, :headers, &(&1 ++ headers))
        end

      Code.compiler_options(ignore_module_conflict: true)

      Code.compile_quoted(
        quote do
          defmodule unquote(module) do
            @moduledoc false

            @doc false
            @spec do_dispatch(Kvasir.Command.t()) :: {:ok, Kvasir.Command.t()} | {:error, atom}
            def do_dispatch(command) do
              with {:ok, cmd} <- Encoder.pack(command),
                   {:ok, %{body: result}} <- HTTPX.post(unquote(opts[:url]), cmd, unquote(b_opts)) do
                {:ok, %{command | __meta__: Meta.decode(result, command.__meta__)}}
              end
            end
          end
        end
      )

      Code.compiler_options(ignore_module_conflict: false)
    end

    :ok
  end
end
