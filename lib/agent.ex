defmodule Kvasir.Agent do
  @moduledoc """
  Documentation for Kvasir.Agent.
  """

  defmacro __using__(opts \\ []) do
    source = opts[:source] || raise "Need to pass the Kvasir EventSource."
    topic = opts[:topic] || raise "Need to pass the Kafka topic."
    model = opts[:model] || raise "Need to pass a Kvasir model."
    {cache, cache_opts} = Macro.expand(Kvasir.Agent.Config.cache!(opts), __CALLER__)
    registry = Kvasir.Agent.Config.registry!(opts)

    # Disabled environments
    if Mix.env() in (opts[:disable] || []) do
      nil
    else
      quote do
        use Kvasir.Command.Dispatcher
        alias Kvasir.Agent
        alias Kvasir.Agent.{Manager, Supervisor}

        @source unquote(source)
        @topic unquote(topic)
        @cache unquote({cache, Macro.escape(cache_opts)})
        @registry unquote(registry)
        @model unquote(model)

        @doc false
        @spec child_spec(Keyword.t()) :: map
        def child_spec(_opts \\ []), do: Agent.child_spec(__agent__(:config))

        @doc false
        @spec do_dispatch(Kvasir.Command.t()) :: {:ok, Kvasir.Command.t()} | {:error, atom}
        @impl Kvasir.Command.Dispatcher
        def do_dispatch(command), do: Manager.dispatch(__MODULE__, command)

        @doc ~S"""
        Start and return the pid of an agent instance.
        """
        @spec open(any) :: {:ok, pid} | {:error, atom}
        def open(id), do: Supervisor.open(__agent__(:config), id)

        @doc ~S"""
        Inspect the current state of an agent instance.
        """
        @spec inspect(any) :: {:ok, term} | {:error, atom}
        def inspect(id), do: Manager.inspect(__agent__(:config), id)

        @doc ~S"""
        Dynamically configure specific components.
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
            topic: @topic
          }

        def __agent__(:topic), do: @topic
      end
    end
  end

  def child_spec(config = %{agent: agent}) do
    Kvasir.Command.RegistryGenerator.create()

    %{
      id: agent,
      start: {Kvasir.Agent.Supervisor, :start_link, [config]}
    }
  end
end
