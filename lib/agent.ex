defmodule Kvasir.Agent do
  @moduledoc """
  Documentation for Kvasir.Agent.
  """

  defmacro __using__(opts \\ []) do
    source =
      Macro.expand(opts[:source], __CALLER__) || raise "Need to pass the Kvasir EventSource."

    topic = Macro.expand(opts[:topic], __CALLER__) || raise "Need to pass the Kafka topic."
    model = opts[:model] || raise "Need to pass a Kvasir model."
    {cache, cache_opts} = Macro.expand(Kvasir.Agent.Config.cache!(opts), __CALLER__)
    registry = Kvasir.Agent.Config.registry!(opts)
    partitions = source.__topics__()[topic].partitions

    # Disabled environments
    unless Mix.env() in (opts[:disable] || []) do
      quote do
        use Kvasir.Command.Dispatcher
        alias Kvasir.Agent
        alias Kvasir.Agent.{Manager, Supervisor}
        @compile {:inline, __agent__: 1}
        require unquote(source)

        @source unquote(source)
        @topic unquote(topic)
        @cache unquote({cache, Macro.escape(cache_opts)})
        @registry unquote(registry)
        @model unquote(model)
        @key @source.__topics__()[@topic].key
        @partitions unquote(partitions)

        @doc false
        @spec child_spec(Keyword.t()) :: map
        def child_spec(_opts \\ []), do: Agent.child_spec(__agent__(:config))

        @doc false
        @spec do_dispatch(Kvasir.Command.t()) :: {:ok, Kvasir.Command.t()} | {:error, atom}
        @impl Kvasir.Command.Dispatcher
        def do_dispatch(command) do
          Manager.dispatch(__MODULE__, @registry, command)
        end

        @doc ~S"""
        Dispatch a command, raises on failure.

        ## Examples

        ```elixir
        iex> dispatch!(<cmd>, instance: <id>)
        <cmd>
        ```
        """
        @spec dispatch!(Kvasir.Command.t(), Keyword.t()) :: Kvasir.Command.t() | no_return
        def dispatch!(command, opts \\ []) do
          case dispatch(command, opts) do
            {:ok, cmd} -> cmd
            {:error, err} -> raise "Command dispatch failed: #{inspect(err)}."
          end
        end

        @doc ~S"""
        Start and return the pid of an agent instance.

        ## Examples

        ```elixir
        iex> open(<id>)
        {:ok, #PID<0.109.0>}
        ```
        """
        @spec open(any) :: {:ok, pid} | {:error, atom}
        def open(id),
          do: Supervisor.open(unquote(registry), __MODULE__, @key.partition!(id, @partitions), id)

        @doc ~S"""
        Inspect the current state of an agent instance.

        The agent is opened based on the given id.

        ## Examples

        ```elixir
        iex> inspect(<id>)
        {:ok, <state>}
        ```
        """
        @spec inspect(any) :: {:ok, term} | {:error, atom}
        def inspect(id),
          do: Manager.inspect(unquote(registry), __MODULE__, @key.partition!(id, @partitions), id)

        @doc ~S"""
        The current amount of active agent instances.

        ## Examples

        ```elixir
        iex> count()
        4
        ```
        """
        @spec count :: non_neg_integer
        def count, do: Supervisor.count(__MODULE__, @partitions)

        @doc ~S"""
        List the IDs of the currently active agent instances.

        ## Examples

        ```elixir
        iex> list()
        [<id>, <id>]
        ```
        """
        @spec list :: [term]
        def list, do: Supervisor.list(__MODULE__, @partitions)

        @doc ~S"""
        Get the agent instance process pid.

        ## Examples

        ```elixir
        iex> whereis(<id>)
        <pid>
        ```
        """
        @spec whereis(any) :: pid | nil
        def whereis(id),
          do: Supervisor.whereis(__MODULE__, @key.partition!(id, @partitions), id)

        @doc ~S"""
        Checks whether a given agent instance is currently active.

        ## Examples

        ```elixir
        iex> alive?(<id>)
        true
        ```
        """
        @spec alive?(any) :: boolean
        def alive?(id),
          do: Supervisor.alive?(__MODULE__, @key.partition!(id, @partitions), id)

        @doc ~S"""
        Forces an agent instance to sleep.

        (Shuts down the process.)

        ## Examples

        ```elixir
        iex> sleep(<id>)
        :ok
        ```

        Optionally allows to pass a reason for sleep:
        ```elixir
        iex> sleep(<id>, :testing)
        :ok
        ```
        """
        @spec sleep(id :: any, reason :: atom) :: :ok
        def sleep(id, reason \\ :sleep) do
          if pid = whereis(id), do: send(pid, {:shutdown, reason})

          :ok
        end

        @doc ~S"""
        Dynamically configure specific components.

        ## Examples

        ```elixir
        iex> config(:source, [])
        {:ok, []}
        ```
        """
        @spec config(component :: atom, opts :: Keyword.t()) :: Keyword.t()
        def config(_component, opts), do: opts

        defoverridable config: 2

        @doc false
        @spec __agent__(atom) :: term
        def __agent__(:config),
          do: %{
            agent: __MODULE__,
            cache: @cache,
            source: @source,
            model: @model,
            registry: @registry,
            topic: @topic,
            key: @key
          }

        def __agent__(:topic), do: @topic
        def __agent__(:key), do: @key

        @doc false
        @spec __supervisor__(non_neg_integer) :: module
        unquote(
          Enum.reduce(0..(partitions - 1), nil, fn i, acc ->
            quote do
              unquote(acc)
              def __supervisor__(unquote(i)), do: unquote(:"#{__CALLER__.module}.Supervisor#{i}")
            end
          end)
        )

        @doc false
        @spec __registry__(non_neg_integer) :: module
        unquote(
          Enum.reduce(0..(partitions - 1), nil, fn i, acc ->
            quote do
              unquote(acc)
              def __registry__(unquote(i)), do: unquote(:"#{__CALLER__.module}.Registry#{i}")
            end
          end)
        )

        @doc false
        @spec __manager__(non_neg_integer) :: module
        unquote(
          Enum.reduce(0..(partitions - 1), nil, fn i, acc ->
            quote do
              unquote(acc)
              def __manager__(unquote(i)), do: unquote(:"#{__CALLER__.module}.Manager#{i}")
            end
          end)
        )

        @doc false
        @spec __key__(term) :: {:ok, term, non_neg_integer} | {:error, term}
        def __key__(id) do
          with {:ok, k} <- @key.parse(id, []),
               {:ok, p} <- @key.partition(k, @partitions),
               do: {:ok, k, p}
        end
      end
    end
  end

  def child_spec(config = %{agent: agent}) do
    Kvasir.Command.RegistryGenerator.create()

    %{
      id: agent,
      start: {Kvasir.Agent.Supervisor, :start_link, [config]},
      type: :supervisor
    }
  end
end
