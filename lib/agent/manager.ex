defmodule Kvasir.Agent.Manager do
  use GenServer
  alias Kvasir.Command
  alias Kvasir.Agent.PartitionSupervisor

  def start_link(config, partition) do
    GenServer.start_link(__MODULE__, config, name: config.agent.__manager__(partition))
  end

  def dispatch(agent, registry, command = %{__meta__: meta = %{scope: {:instance, id}}}) do
    with {:ok, id, p} <- agent.__key__(id),
         command = %{command | __meta__: %{meta | scope: {:instance, id}}},
         {:ok, pid} <- PartitionSupervisor.open(registry, agent, p, id) do
      send(pid, {:command, self(), command})
      after_dispatch(pid, command, command.__meta__.wait)
    end
  end

  def dispatch(_, _, _), do: {:error, :requires_instance}

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
         %{__meta__: %{offset: offset}} <- command do
      send(agent, {:offset_callback, self(), ref, offset})
      timeout = command.__meta__.timeout

      receive do
        {:offset_reached, ^ref, ^offset} -> {:ok, Command.set_applied(command)}
      after
        timeout -> {:error, :apply_timeout}
      end
    end
  end

  def inspect(registry, agent, partition, id) do
    with {:ok, agent} <- PartitionSupervisor.open(registry, agent, partition, id) do
      GenServer.call(agent, :inspect)
    end
  end

  @impl GenServer
  def init(config), do: {:ok, config}

  # Agent Funneled Approach

  # @impl GenServer
  # def handle_call({:command, id, command}, {from, _ref}, config) do
  #   with {:ok, agent} <-
  #          PartitionSupervisor.open(config.registry, config.agent, config.partition, id) do
  #     send(agent, {:command, from, command})
  #     {:reply, :ok, config}
  #   else
  #     error -> {:reply, error, config}
  #   end
  # end

  # def handle_call({:offset_callback, id, ref, offset}, {from, _ref}, config) do
  #   with {:ok, agent} <-
  #          PartitionSupervisor.open(config.registry, config.agent, config.partition, id) do
  #     send(agent, {:offset_callback, from, ref, offset})
  #     {:reply, :ok, config}
  #   else
  #     error -> {:reply, error, config}
  #   end
  # end

  # def dispatch(agent, command = %{__meta__: meta = %{scope: {:instance, id}}}) do
  #   with {:ok, id, p} <- agent.__key__(id),
  #        command = %{command | __meta__: %{meta | scope: {:instance, id}}},
  #        :ok <- GenServer.call(agent.__manger__(p), {:command, id, command}) do
  #     after_dispatch(agent, p, command, command.__meta__.wait)
  #   end
  # end

  # def dispatch(_, _), do: {:error, :requires_instance}

  # defp after_dispatch(_agent, command, :dispatch), do: {:ok, command}

  # defp after_dispatch(_agent, command, :execute) do
  #   timeout = command.__meta__.timeout
  #   ref = command.__meta__.id

  #   receive do
  #     {:command, ^ref, response} ->
  #       case response do
  #         :ok -> {:ok, Command.set_executed(command)}
  #         {:ok, offset} -> {:ok, Command.set_offset(Command.set_executed(command), offset)}
  #         error -> error
  #       end
  #   after
  #     timeout -> {:error, :execute_timeout}
  #   end
  # end

  # defp after_dispatch(agent, partition, command, :apply) do
  #   with {:ok, command} <- after_dispatch(agent, command, :execute),
  #        ref <- command.__meta__.id,
  #        %{__meta__: %{offset: offset, scope: {:instance, id}}} <- command,
  #        :ok <- GenServer.call(agent.__manger__(partition), {:offset_callback, id, ref, offset}) do
  #     timeout = command.__meta__.timeout

  #     receive do
  #       {:offset_reached, ^ref, ^offset} -> {:ok, Command.set_applied(command)}
  #     after
  #       timeout -> {:error, :apply_timeout}
  #     end
  #   end
  # end
end
