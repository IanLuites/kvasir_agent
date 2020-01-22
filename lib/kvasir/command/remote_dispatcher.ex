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
    backend =
      case opts[:mode] do
        :test -> test_backend(opts)
        :placeholder -> placeholder_backend(opts)
        _ -> http_backend(opts)
      end

    Code.compiler_options(ignore_module_conflict: true)

    Code.compile_quoted(
      quote do
        defmodule unquote(module) do
          @moduledoc false
          unquote(backend)
        end
      end
    )

    Code.compiler_options(ignore_module_conflict: false)

    :ok
  end

  @doc false
  @spec http_backend(Keyword.t()) :: term
  def http_backend(opts) do
    if Code.ensure_loaded?(HTTPX) do
      Application.ensure_all_started(:httpx)

      b_opts =
        case opts[:headers] do
          nil -> @opts
          headers -> Keyword.update!(@opts, :headers, &(&1 ++ headers))
        end

      url = opts[:url] || ""

      errors =
        case opts[:atomize_errors] do
          true ->
            quote do
              unquote(__MODULE__).atom_error(b)
            end

          :safe ->
            quote do
              unquote(__MODULE__).atom_error!(b)
            end

          _ ->
            quote do
              unquote(__MODULE__).error(b)
            end
        end

      quote do
        @doc false
        @spec do_dispatch(Kvasir.Command.t()) :: {:ok, Kvasir.Command.t()} | {:error, atom}
        def do_dispatch(command) do
          with {:ok, cmd} <- Encoder.pack(command),
               {:ok, %{status: s, body: b}} <- HTTPX.post(unquote(url), cmd, unquote(b_opts)) do
            if s in 200..299 do
              {:ok, %{command | __meta__: Meta.decode(b, command.__meta__)}}
            else
              unquote(errors)
            end
          end
        end
      end
    else
      placeholder_backend(opts)
    end
  end

  @doc false
  @spec placeholder_backend(Keyword.t()) :: term
  def placeholder_backend(_opts) do
    quote do
      @doc false
      @spec do_dispatch(Kvasir.Command.t()) :: {:ok, Kvasir.Command.t()} | {:error, atom}
      def do_dispatch(command), do: {:ok, unquote(__MODULE__).set_relevant_timestamps(command)}
    end
  end

  @doc false
  @spec test_backend(Keyword.t()) :: term
  def test_backend(_opts) do
    quote do
      @doc false
      @spec do_dispatch(Kvasir.Command.t()) :: {:ok, Kvasir.Command.t()} | {:error, atom}
      def do_dispatch(command) do
        cmd = unquote(__MODULE__).set_relevant_timestamps(command)

        if call = unquote(__MODULE__).command_callback(__MODULE__) do
          call.(cmd)
        else
          unquote(__MODULE__).command_add(__MODULE__, cmd)
          {:ok, cmd}
        end
      end
    end
  end

  def command_callback(backend), do: Agent.get(command_agent(backend), & &1.hook)

  def command_hook(backend, fun), do: Agent.update(command_agent(backend), &%{&1 | hook: fun})

  def command_unhook(backend), do: Agent.update(command_agent(backend), &%{&1 | hook: nil})

  def command_add(backend, command) do
    id =
      case command.__meta__.scope do
        {:instance, i} -> i
        _ -> nil
      end

    Agent.update(command_agent(backend), fn state ->
      %{state | commands: Map.update(state.commands, id, [command], &[command | &1])}
    end)
  end

  def command_get(backend, id) do
    backend
    |> command_agent()
    |> Agent.get(&Map.get(&1.commands, id, []))
    |> :lists.reverse()
  end

  def command_clear(backend), do: Agent.update(command_agent(backend), &%{&1 | commands: %{}})

  def command_clear(backend, id) do
    Agent.update(command_agent(backend), &%{&1 | commands: Map.delete(&1.commands, id)})
  end

  def command_agent(backend) do
    if p = Process.whereis(backend) do
      p
    else
      {:ok, p} = Agent.start(fn -> %{hook: nil, commands: %{}} end, name: backend)
      p
    end
  end

  @doc false
  @spec set_relevant_timestamps(Kvasir.Command.t()) :: {:ok, Kvasir.Command.t()} | {:error, atom}
  def set_relevant_timestamps(command = %{__meta__: meta}) do
    meta = %{meta | dispatched: UTCDateTime.utc_now()}

    if meta.wait == :dispatch do
      %{command | __meta__: meta}
    else
      meta = %{meta | executed: UTCDateTime.utc_now()}

      if meta.wait == :execute do
        %{command | __meta__: meta}
      else
        %{command | __meta__: %{meta | applied: UTCDateTime.utc_now()}}
      end
    end
  end

  @doc false
  @spec error(term) :: {:error, term}
  def error(%{"error" => err}) when err != nil, do: {:error, err}
  def error(_), do: {:error, :dispatch_failed}

  @doc false
  @spec atom_error(term) :: {:error, term}
  def atom_error(%{"error" => err}) when is_binary(err) do
    {:error, String.to_atom(err)}
  rescue
    ArgumentError -> {:error, err}
  end

  def atom_error(%{"error" => err}) when err != nil, do: {:error, err}
  def atom_error(_), do: {:error, :dispatch_failed}

  @doc false
  @spec atom_error!(term) :: {:error, term}
  def atom_error!(%{"error" => err}) when is_binary(err) do
    {:error, String.to_existing_atom(err)}
  rescue
    ArgumentError -> {:error, err}
  end

  def atom_error!(%{"error" => err}) when err != nil, do: {:error, err}
  def atom_error!(_), do: {:error, :dispatch_failed}
end
