defmodule Kvasir.Agent.Manager do
  use GenServer
  import Kvasir.Agent.Helpers, only: [manager: 1]
  alias Kvasir.Command

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: manager(config.agent))
  end

  def dispatch(agent, command = %{__meta__: meta = %{scope: {:instance, id}}}) do
    with {:ok, id} <- agent.__agent__(:key).parse(id, []),
         command = %{command | __meta__: %{meta | scope: {:instance, id}}},
         :ok <- GenServer.call(manager(agent), {:command, id, command}) do
      after_dispatch(agent, command, command.__meta__.wait)
    end
  end

  def dispatch(_, _), do: {:error, :requires_instance}

  defp after_dispatch(_agent, command, :dispatch), do: {:ok, command}

  defp after_dispatch(_agent, command, :execute) do
    timeout = command.__meta__.timeout
    ref = command.__meta__.id

    receive do
      {:command, ^ref, response} ->
        case response do
          :ok -> {:ok, Command.set_executed(command)}
          {:ok, offset} -> {:ok, Command.set_offset(Command.set_executed(command), offset)}
          error -> error
        end
    after
      timeout -> {:error, :execute_timeout}
    end
  end

  defp after_dispatch(agent, command, :apply) do
    with {:ok, command} <- after_dispatch(agent, command, :execute),
         ref <- command.__meta__.id,
         %{__meta__: %{offset: offset, scope: {:instance, id}}} <- command,
         :ok <- GenServer.call(manager(agent), {:offset_callback, id, ref, offset}) do
      timeout = command.__meta__.timeout

      receive do
        {:offset_reached, ^ref, ^offset} -> {:ok, Command.set_applied(command)}
      after
        timeout -> {:error, :apply_timeout}
      end
    end
  end

  def inspect(config, id) do
    with {:ok, agent} <- Kvasir.Agent.Supervisor.open(config, id) do
      GenServer.call(agent, :inspect)
    end
  end

  @impl GenServer
  def init(config), do: {:ok, config}

  @impl GenServer
  def handle_call({:command, id, command}, {from, _ref}, config) do
    with {:ok, agent} <- Kvasir.Agent.Supervisor.open(config, id) do
      send(agent, {:command, from, command})
      {:reply, :ok, config}
    else
      error -> {:reply, error, config}
    end
  end

  def handle_call({:offset_callback, id, ref, offset}, {from, _ref}, config) do
    with {:ok, agent} <- Kvasir.Agent.Supervisor.open(config, id) do
      send(agent, {:offset_callback, from, ref, offset})
      {:reply, :ok, config}
    else
      error -> {:reply, error, config}
    end
  end
end
