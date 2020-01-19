defmodule Kvasir.Agent.Instance do
  use GenServer
  require Logger
  alias Kvasir.Offset
  @keep_alive 60_000

  def start_agent(config, id, opts) do
    t = config.source.__topics__()[config.topic]
    {:ok, p} = t.key.partition(id, t.partitions)

    config =
      config
      |> Map.put(:id, id)
      |> Map.put(:partition, p)
      |> Map.update!(:cache, &elem(&1, 0))

    GenServer.start_link(__MODULE__, config, opts)
  end

  @impl GenServer
  def init(
        state = %{
          source: source,
          agent: agent,
          id: id,
          cache: cache,
          topic: topic,
          model: model
        }
      ) do
    Logger.debug(fn -> "Agent<#{state.id}>: Init (#{inspect(self())})" end)
    {offset, agent_state} = load_state(source, cache, topic, model, agent, id)
    cache.save(agent, id, agent_state, offset)

    state =
      state
      |> Map.put(:agent_state, agent_state)
      |> Map.put(:offset, offset)
      |> Map.put(:callbacks, %{})

    keep_alive = Process.send_after(self(), {:shutdown, :keep_alive}, @keep_alive)
    {:ok, Map.put(state, :keep_alive, keep_alive)}
  end

  defp load_state(source, cache, topic, model, agent, id) do
    case cache.load(agent, id) do
      {:ok, offset, state} ->
        Logger.debug(fn -> "Agent<#{id}>: State Loaded: #{inspect(offset)}" end)
        build_state(source, topic, model, id, offset, state)

      {:error, reason} ->
        Logger.debug(fn -> "Agent<#{id}>: No State Loaded: #{reason}" end)
        build_state(source, topic, model, id, nil, model.base(id))
    end
  end

  defp build_state(source, topic, model, id, offset, original_state) do
    topic
    |> source.stream(from: offset, to: :last, key: id)
    |> Enum.reduce({offset || Kvasir.Offset.create(), original_state}, fn event,
                                                                          {offset, state} ->
      with {:ok, updated_state} <- model.apply(state, event) do
        {Offset.set(offset, event.__meta__.partition, event.__meta__.offset), updated_state}
      end
    end)
  end

  @impl GenServer
  def handle_info(
        {:command, from, command},
        state = %{agent_state: agent_state, model: model, partition: p}
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

    case response do
      {:ok, events} ->
        send(from, {:command, ref, {:ok, Offset.create(p, List.last(events).__meta__.offset)}})
        with {:ok, state} <- apply_events(events, state), do: {:noreply, reset_keep_alive(state)}

      _ ->
        send(from, {:command, ref, response})
        {:noreply, reset_keep_alive(state)}
    end
  end

  def handle_info({:event, event}, state) do
    with {:ok, state} <- apply_events([event], state), do: {:noreply, state}
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

  defp apply_events(events, state, offset \\ nil)

  defp apply_events([], state, offset),
    do: {:ok, if(offset, do: notify_offset_callbacks(state, offset), else: state)}

  defp apply_events([event | events], state, c_offset) do
    Logger.debug(fn -> "Agent<#{state.id}>: Incoming Event (#{inspect(event)})" end)
    %{offset: offset, partition: partition} = event.__meta__

    if Offset.get(state.offset, event.__meta__.partition) < offset do
      case state.model.apply(state.agent_state, event) do
        {:ok, updated_state} ->
          updated_offset = Offset.set(state.offset, partition, offset)
          state.cache.save(state.agent, state.id, updated_state, updated_offset)
          state = %{state | offset: updated_offset, agent_state: updated_state}
          apply_events(events, state, updated_offset)

        :ok ->
          apply_events(events, state, c_offset)

        {:error, reason} ->
          if Kvasir.Event.on_error(:on_error) == :halt do
            Logger.error(fn -> "Agent<#{state.id}>: Event error (#{inspect(reason)})" end)
            {:stop, :invalid_event, state}
          else
            Logger.warn(fn -> "Agent<#{state.id}>: Event error (#{inspect(reason)})" end)
            apply_events(events, state, c_offset)
          end
      end
    else
      apply_events(events, state, c_offset)
    end
  end

  defp pause_keep_alive(%{keep_alive: nil}), do: :ok
  defp pause_keep_alive(%{keep_alive: ref}), do: Process.cancel_timer(ref)

  defp reset_keep_alive(state = %{keep_alive: nil}), do: state

  defp reset_keep_alive(state) do
    %{state | keep_alive: Process.send_after(self(), {:shutdown, :keep_alive}, @keep_alive)}
  end

  defp commit_events(state = %{source: source, topic: topic}, events, ref) do
    events
    |> Enum.map(&prepare_event(&1, ref, state))
    |> EnumX.map(&source.publish(topic, &1))
  end

  defp prepare_event(event, ref, %{id: id, partition: partition}) do
    meta = %{event.__meta__ | command: ref, partition: partition, key: id}
    %{event | __meta__: meta}
  end

  defp add_offset_callback(state = %{callbacks: callbacks, offset: now}, l = {pid, ref}, offset) do
    if Offset.compare(now, offset) == :lt do
      callbacks = Map.update(callbacks, offset, [l], &[l | &1])

      %{state | callbacks: callbacks}
    else
      send(pid, {:offset_reached, ref, offset})
      state
    end
  end

  def notify_offset_callbacks(state = %{callbacks: callbacks}, offset) do
    grouped = Enum.group_by(callbacks, &(Offset.compare(elem(&1, 0), offset) != :lt))

    Enum.each(Map.get(grouped, true, []), fn {off, listeners} ->
      Enum.each(listeners, fn {pid, ref} -> send(pid, {:offset_reached, ref, off}) end)
    end)

    %{state | callbacks: Enum.into(Map.get(grouped, false, []), %{})}
  end
end
