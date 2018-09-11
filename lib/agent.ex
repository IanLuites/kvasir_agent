defmodule Kvasir.Agent do
  @moduledoc """
  Documentation for Kvasir.Agent.
  """

  defmacro __using__(opts \\ []) do
    client = opts[:client] || raise "Need to pass the Kvasir client."
    cache = Kvasir.Agent.Config.cache!(opts)
    registry = Kvasir.Agent.Config.registry!(opts)

    quote do
      use Kvasir.Command.Dispatcher
      import Kvasir.Agent, only: [agent: 2]
      alias Kvasir.Agent
      alias Kvasir.Agent.{Manager, Supervisor}

      @client unquote(client)
      @cache unquote(cache)
      @registry unquote(registry)

      def child_spec(_opts \\ []), do: Agent.child_spec(__agent__(:config))

      def open(id), do: Supervisor.open(__agent__(:config), id)
      def do_dispatch(command), do: Manager.dispatch(__MODULE__, command)
      def inspect(id), do: Manager.inspect(__agent__(:config), id)

      def base(_id), do: struct(__MODULE__, %{})

      defoverridable base: 1
    end
  end

  defmacro field(name, type) do
    quote do
      Module.put_attribute(__MODULE__, :agent_fields, {unquote(name), unquote(type)})
    end
  end

  defmacro agent(topic, do: block) do
    quote do
      Module.register_attribute(__MODULE__, :agent_fields, accumulate: true)

      try do
        import Kvasir.Agent, only: [field: 2]
        unquote(block)
      after
        :ok
      end

      @struct_fields Enum.reverse(@agent_fields)
      defstruct Enum.map(@struct_fields, &elem(&1, 0))

      @doc false
      def __agent__(:config),
        do: %{
          agent: __MODULE__,
          cache: @cache,
          client: @client,
          registry: @registry,
          topic: unquote(to_string(elem(topic, 0)))
        }

      def __agent__(:topic), do: unquote(to_string(elem(topic, 0)))
      def __agent__(:fields), do: @struct_fields

      defimpl Jason.Encoder, for: __MODULE__ do
        def encode(value, opts) do
          Jason.Encode.map(Map.from_struct(value), opts)
        end
      end
    end
  end

  def child_spec(config = %{agent: agent}) do
    %{
      id: agent,
      start: {Kvasir.Agent.Supervisor, :start_link, [config]}
    }
  end
end
