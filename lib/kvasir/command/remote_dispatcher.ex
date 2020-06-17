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
      Dispatch a command to commander, raises on failure.

      ## Examples

      ```elixir
      iex> dispatch!(<cmd>, <payload>, instance: <id>)
      <cmd>
      ```
      """
      @spec dispatch!(command :: module, payload :: map | Keyword.t(), Keyword.t()) ::
              Kvasir.Command.t() | no_return
      def dispatch!(command, payload, opts) do
        case dispatch(command, payload, opts) do
          {:ok, cmd} ->
            cmd

          {:error, err} ->
            raise "#{inspect(__MODULE__)}: Failed to #{opts[:wait] || :dispatch} command. (#{
                    inspect(err)
                  })"
        end
      end

      @doc ~S"""
      Dispatch a command to commander, raises on failure.

      ## Examples

      ```elixir
      iex> dispatch!(<cmd>, instance: <id>)
      <cmd>
      ```
      """
      @spec dispatch!(Kvasir.Command.t(), Keyword.t()) :: Kvasir.Command.t() | no_return
      def dispatch!(command, opts \\ []) do
        case dispatch(command, opts) do
          {:ok, cmd} ->
            cmd

          {:error, err} ->
            raise "#{inspect(__MODULE__)}: Failed to #{opts[:wait] || :dispatch} command. (#{
                    inspect(err)
                  })"
        end
      end

      @doc ~S"""
      Dispatch a command to commander.

      ## Examples

      ```elixir
      iex> dispatch(<cmd>, instance: <id>)
      {:ok, <cmd>}
      ```
      """
      @spec dispatch(command :: module, payload :: map | Keyword.t(), Keyword.t()) ::
              {:ok, Kvasir.Command.t()} | {:error, atom}
      def dispatch(command, payload, opts) do
        with {:ok, cmd} <- command.create(payload), do: dispatch(cmd, opts)
      end

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
      def dispatch(command, opts \\ []) do
        if opts[:dry_run] do
          {:ok, unquote(__MODULE__).set_relevant_timestamps(command)}
        else
          Kvasir.Command.Dispatcher.dispatch(__MODULE__, command, opts)
        end
      end

      @doc false
      @spec do_dispatch(Kvasir.Command.t()) :: {:ok, Kvasir.Command.t()} | {:error, atom}
      @impl Kvasir.Command.Dispatcher
      def do_dispatch(command) do
        if multi = multi_context() do
          Process.put(__MODULE__, unquote(__MODULE__.Multi).add(multi, command))
          {:ok, command}
        else
          __MODULE__.Dispatcher.do_dispatch(command)
        end
      end

      ### Multi ###

      defmodule Multi do
        @moduledoc ~S"""
        Dispatch multiple commands concurrently.

        Support smart retry for failed dispatches.
        """
        alias Kvasir.Command.RemoteDispatcher.Multi, as: M

        @doc ~S"""
        Create a new multi-dispatch for dispatching.

        ## Examples

        ```elixir
        iex> new()
        #Multi<0>
        ```
        """
        @spec new :: Kvasir.Command.RemoteDispatcher.Multi.t()
        defdelegate new, to: M

        @doc ~S"""
        Execute a multi-dispatch; dispatching all added commands.

        ## Examples

        ```elixir
        iex> exec(#Multi<5>, retry: true)
        {:ok, #MultiResult<Success>}
        ```
        """
        @spec exec(Kvasir.Command.RemoteDispatcher.Multi.t(), Keyword.t()) ::
                {:ok | :error, Kvasir.Command.RemoteDispatcher.Multi.Result.t()}
        def exec(multi, opts \\ []) do
          r =
            case opts[:retry] do
              true ->
                {250, 5, fn _ -> true end}

              o when is_list(o) ->
                {Keyword.get(o, :timeout, 250), Keyword.get(o, :attempts, 5),
                 Keyword.get(o, :only, fn _ -> true end)}

              _ ->
                false
            end

          M.exec(
            multi,
            &unquote(__CALLER__.module).do_dispatch/1,
            opts[:failed_successfully] || fn _ -> false end,
            r
          )
        end

        @doc ~S"""
        Add a command for dispatching to the multi-dispatch.

        ## Examples

        ```elixir
        iex> dispatch(#Multi<0>, <cmd>, instance: <id>)
        #Multi<1>
        ```
        """
        @spec dispatch(Kvasir.Command.RemoteDispatcher.Multi.t(), Kvasir.Command.t(), Keyword.t()) ::
                Kvasir.Command.RemoteDispatcher.Multi.t()
        def dispatch(multi, command, opts \\ []) do
          unquote(__MODULE__.Multi).add(
            multi,
            Kvasir.Command.Dispatcher.dispatch(unquote(__MODULE__).Pass, command, opts)
          )
        end
      end

      @doc """
      Dispatch multiple commands as a single retry-able multi-dispatch.

      The `callback` can be any function dispatching commands
      using `#{inspect(__MODULE__)}.dispatch/2`.

      ## Examples

      ```elixir
      iex> multi(fn ->
      ...>   dispatch(<cmd>, instance: <id>)
      ...>   dispatch(<cmd>, instance: <id>)
      ...>   dispatch(<cmd>, instance: <id>)
      ...> end)
      {:ok, #MultiResult<Success>}
      ```
      """
      @spec multi(fun, Keyword.t()) ::
              {:ok | :error, Kvasir.Command.RemoteDispatcher.Multi.Result.t()}
      def multi(callback, opts \\ []) when is_function(callback, 0) do
        Process.put(__MODULE__, Multi.new())
        callback.()
        Multi.exec(Process.delete(__MODULE__), opts)
      end

      @doc """
      Dispatch multiple commands as a single retry-able multi-dispatch.

      The `callback` can be any function dispatching commands
      using `#{inspect(__MODULE__)}.dispatch/2`.

      See: `#{inspect(__MODULE__)}.multi/2`.

      ## Examples

      ```elixir
      iex> multi!(fn ->
      ...>   dispatch(<cmd>, instance: <id>)
      ...>   dispatch(<cmd>, instance: <id>)
      ...>   dispatch(<cmd>, instance: <id>)
      ...> end)
      #MultiResult<Success>
      ```
      """
      @spec multi!(fun, Keyword.t()) :: Kvasir.Command.RemoteDispatcher.Multi.Result.t()
      def multi!(callback, opts \\ []) when is_function(callback, 0) do
        {_, m} = multi(callback, opts)
        m
      end

      @spec multi_context :: Kvasir.Command.RemoteDispatcher.Multi.t() | nil
      defp multi_context, do: Process.get(__MODULE__)
    end
  end

  defmodule Pass do
    @moduledoc false

    @doc false
    @spec do_dispatch(term) :: term
    def do_dispatch(cmd), do: cmd
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
        :discard -> placeholder_backend(opts)
        :log -> log_backend(opts)
        :placeholder -> placeholder_backend(opts)
        :test -> test_backend(opts)
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
    if CodeX.ensure_loaded?(HTTPX) do
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
  @spec log_backend(Keyword.t()) :: term
  def log_backend(opts) do
    level = opts[:log_level] || :debug

    quote do
      @doc false
      @spec do_dispatch(Kvasir.Command.t()) :: {:ok, Kvasir.Command.t()} | {:error, atom}
      def do_dispatch(command) do
        require Logger

        cmd = unquote(__MODULE__).set_relevant_timestamps(command)

        {:ok, %{meta: %{scope: [:instance, i]}, payload: p, type: t}} =
          unquote(Kvasir.Command).encode(cmd)

        Logger.log(
          unquote(level),
          "#{inspect(__MODULE__ |> Module.split() |> Enum.slice(0..-2) |> Module.concat())}<#{i}>: #{
            inspect(cmd)
          }",
          instance: i,
          command: t,
          payload: p
        )

        {:ok, cmd}
      end
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
      case Agent.start(fn -> %{hook: nil, commands: %{}} end, name: backend) do
        {:ok, p} -> p
        {:error, {:already_started, p}} -> p
      end
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
