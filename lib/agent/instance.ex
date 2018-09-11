defmodule Kvasir.Agent.Instance do
  use GenServer
  require Logger
  @keep_alive 60_000

  def start_agent(config, id, opts) do
    GenServer.start_link(__MODULE__, Map.put(config, :id, id), opts)
  end

  @impl GenServer
  def init(state = %{client: client, agent: agent, id: id, cache: cache, topic: topic}) do
    Logger.debug(fn -> "Agent<#{state.id}>: Init (#{inspect(self())})" end)

    agent_state = cache.load(agent, id) || Map.put(agent.base(id), :offset, :earliest)

    {offset, from} =
      if is_integer(agent_state.offset),
        do: {agent_state.offset, agent_state.offset + 1},
        else: {-1, agent_state.offset}

    agent_state = Map.delete(agent_state, :offset)

    {offset, agent_state} =
      topic
      |> client.stream(from: from, to: :last)
      |> Stream.filter(&(&1.__meta__.key == id))
      |> Enum.reduce({offset, agent_state}, fn event, {_offset, state} ->
        with {:ok, updated_state} <- agent.apply(state, event) do
          {event.__meta__.offset, updated_state}
        end
      end)

    cache.save(agent, id, Map.put(agent_state, :offset, offset))
    state = state |> Map.put(:agent_state, agent_state) |> Map.put(:offset, offset)

    keep_alive = Process.send_after(self(), {:shutdown, :keep_alive}, @keep_alive)
    {:ok, Map.put(state, :keep_alive, keep_alive)}
  end

  @impl GenServer
  def handle_info(
        {:command, from, command},
        state = %{agent: agent, agent_state: agent_state}
      ) do
    pause_keep_alive(state)
    Logger.debug(fn -> "Agent<#{state.id}>: Command: #{inspect(command)}" end)

    ref = command.__meta__.id

    response =
      case agent.execute(agent_state, command) do
        {:ok, events} when is_list(events) ->
          commit_events(state, events, ref)

        {:ok, event} ->
          commit_events(state, [event], ref)

        :ok ->
          :ok

        error ->
          error
      end

    send(from, {:command, ref, response})

    {:noreply, reset_keep_alive(state)}
  end

  def handle_info({:event, event}, state) do
    Logger.debug(fn -> "Agent<#{state.id}>: Incoming Event (#{inspect(event)})" end)
    offset = event.__meta__.offset

    case state.offset < offset && state.agent.apply(state.agent_state, event) do
      {:ok, updated_state} ->
        state.cache.save(state.agent, state.id, Map.put(updated_state, :offset, offset))
        {:noreply, %{state | offset: offset, agent_state: updated_state}}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:shutdown, reason}, state) do
    Logger.debug(fn -> "Agent<#{state.id}>: Shutdown (#{inspect(reason)})" end)
    {:stop, :shutdown, state}
  end

  @impl GenServer
  def handle_call(:inspect, _from, state) do
    {:reply, state.agent_state, state}
  end

  defp pause_keep_alive(%{keep_alive: nil}), do: :ok
  defp pause_keep_alive(%{keep_alive: ref}), do: Process.cancel_timer(ref)

  defp reset_keep_alive(state = %{keep_alive: nil}), do: state

  defp reset_keep_alive(state) do
    %{state | keep_alive: Process.send_after(self(), {:shutdown, :keep_alive}, @keep_alive)}
  end

  defp commit_events(%{client: client, topic: topic, id: id}, events, ref) do
    client.produce(topic, 0, id, Enum.map(events, &prepare_event(&1, ref)))
  end

  defp prepare_event(event, ref), do: %{event | __meta__: %{event.__meta__ | command: ref}}
end
