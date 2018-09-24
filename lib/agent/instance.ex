defmodule Kvasir.Agent.Instance do
  use GenServer
  require Logger
  alias Kvasir.Offset
  @keep_alive 60_000

  def start_agent(config, id, opts) do
    config = Map.put(config, :partition, 0)
    GenServer.start_link(__MODULE__, Map.put(config, :id, id), opts)
  end

  @impl GenServer
  def init(
        state = %{
          client: client,
          agent: agent,
          id: id,
          cache: cache,
          topic: topic,
          model: model
        }
      ) do
    Logger.debug(fn -> "Agent<#{state.id}>: Init (#{inspect(self())})" end)
    {offset, agent_state} = load_state(client, cache, topic, model, agent, id)
    cache.save(agent, id, agent_state, offset)

    state =
      state
      |> Map.put(:agent_state, agent_state)
      |> Map.put(:offset, offset)
      |> Map.put(:callbacks, %{})

    keep_alive = Process.send_after(self(), {:shutdown, :keep_alive}, @keep_alive)
    {:ok, Map.put(state, :keep_alive, keep_alive)}
  end

  defp load_state(client, cache, topic, model, agent, id) do
    case cache.load(agent, id) do
      {:ok, offset, state} ->
        Logger.debug(fn -> "Agent<#{id}>: State Loaded: #{offset}" end)
        build_state(client, topic, model, id, offset, state)

      {:error, reason} ->
        Logger.debug(fn -> "Agent<#{id}>: No State Loaded: #{reason}" end)
        build_state(client, topic, model, id, :earliest, model.base(id))
    end
  end

  defp build_state(client, topic, model, id, offset, original_state) do
    topic
    |> client.stream(from: offset, to: :last)
    |> Stream.filter(&(&1.__meta__.key == id))
    |> Enum.reduce({offset, original_state}, fn event, {offset, state} ->
      with {:ok, updated_state} <- model.apply(state, event) do
        {Offset.set(offset, event.__meta__.offset), updated_state}
      end
    end)
  end

  @impl GenServer
  def handle_info(
        {:command, from, command},
        state = %{agent_state: agent_state, model: model}
      ) do
    pause_keep_alive(state)
    Logger.debug(fn -> "Agent<#{state.id}>: Command: #{inspect(command)}" end)

    ref = command.__meta__.id

    response =
      case model.execute(agent_state, command) do
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
    newer = Offset.compare(state.offset, offset) == :lt

    case newer && state.model.apply(state.agent_state, event) do
      {:ok, updated_state} ->
        updated_offset = Offset.set(state.offset, offset)
        state.cache.save(state.agent, state.id, updated_state, updated_offset)
        state = %{state | offset: updated_offset, agent_state: updated_state}
        {:noreply, notify_offset_callbacks(state, updated_offset)}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:offset_callback, from, ref, offset}, state) do
    Logger.debug(fn -> "Agent<#{state.id}>: Adding callback (#{inspect(offset)})" end)
    {:noreply, add_offset_callback(state, {from, ref}, offset)}
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

  defp commit_events(state = %{client: client, topic: topic, id: id}, events, ref) do
    client.produce(topic, 0, id, Enum.map(events, &prepare_event(&1, ref, state)))
  end

  defp prepare_event(event, ref, %{topic: topic, id: id, partition: partition}) do
    meta = %{event.__meta__ | command: ref, topic: topic, partition: partition, key: id}
    %{event | __meta__: meta}
  end

  defp add_offset_callback(state = %{callbacks: callbacks}, pid, offset) do
    callbacks = Map.update(callbacks, offset, [pid], &[pid | &1])

    %{state | callbacks: callbacks}
  end

  def notify_offset_callbacks(state = %{callbacks: callbacks}, offset) do
    grouped = Enum.group_by(callbacks, &(Offset.compare(elem(&1, 0), offset) != :lt))

    Enum.each(Map.get(grouped, true, []), fn {off, listeners} ->
      Enum.each(listeners, fn {pid, ref} -> send(pid, {:offset_reached, ref, off}) end)
    end)

    %{state | callbacks: Enum.into(Map.get(grouped, false, []), %{})}
  end
end
