defmodule Kvasir.Agent.Instance do
  use GenServer
  require Logger
  alias Kvasir.Offset
  @keep_alive 60_000

  def start_agent(agent, partition, id, opts) do
    config =
      :config
      |> agent.__agent__()
      |> Map.put(:id, id)
      |> Map.put(:partition, partition)
      |> Map.update!(:cache, &elem(&1, 0))

    GenServer.start_link(__MODULE__, config, opts)
  end

  @impl GenServer
  def init(
        state = %{
          source: source,
          agent: agent,
          partition: partition,
          id: id,
          cache: cache,
          topic: topic,
          model: model
        }
      ) do
    Logger.debug(fn -> "Agent<#{state.id}>: Init (#{inspect(self())})" end)

    with {:ok, {offset, agent_state, _}} <-
           load_state(source, cache, topic, model, agent, partition, id) do
      state =
        state
        |> Map.put(:agent_state, agent_state)
        |> Map.put(:offset, offset)
        |> Map.put(:callbacks, %{})

      keep_alive = Process.send_after(self(), {:shutdown, :keep_alive}, @keep_alive)
      {:ok, Map.put(state, :keep_alive, keep_alive)}
    end
  end

  defp load_state(source, cache, topic, model, agent, partition, id) do
    case cache.load(agent, partition, id) do
      {:ok, offset, nil} ->
        Logger.debug(fn -> "Agent<#{id}>: State Loaded: No State, Setup New" end)
        {:ok, {offset, model.base(id), :no_tracking}}

      {:ok, offset, state} ->
        Logger.debug(fn -> "Agent<#{id}>: State Loaded: #{inspect(offset)}" end)
        # build_state(source, topic, model, id, offset, state)
        {:ok, {offset, state, :no_tracking}}

      {:error, :state_counter_mismatch, correct, loaded} ->
        Logger.debug(fn ->
          "Agent<#{id}>: State Load Failed: Command Counter Mismatch #{correct} != #{loaded} (tracked, state)"
        end)

        with r = {:ok, {offset, agent_state, _}} <-
               build_state(source, topic, model, id, nil, model.base(id)) do
          cache.save(agent, partition, id, agent_state, offset, correct)
          r
        end

      {:error, reason} ->
        Logger.debug(fn -> "Agent<#{id}>: State Load Failed: #{reason}" end)
        build_state(source, topic, model, id, nil, model.base(id))
    end
  end

  defp build_state(source, topic, model, id, offset, original_state) do
    base = {offset || Kvasir.Offset.create(), original_state, false}

    topic
    |> source.stream(from: offset, to: :last, key: id)
    |> EnumX.reduce_while(base, &state_reducer(model, &1, &2))
  end

  defp state_reducer(model, event, {offset, state, true}) do
    with {:ok, updated_state} <- model.apply(state, event) do
      {:ok,
       {Offset.set(offset, event.__meta__.partition, event.__meta__.offset), updated_state, true}}
    end
  end

  defp state_reducer(model, event, {offset, state, false}) do
    if Offset.empty?(offset) or
         Offset.get(offset, event.__meta__.partition) < event.__meta__.offset do
      state_reducer(model, event, {offset, state, true})
    else
      {:ok, {offset, state, false}}
    end
  end

  @impl GenServer
  def handle_info(
        {:command, from, command},
        state = %{
          agent: agent,
          agent_state: agent_state,
          cache: cache,
          id: id,
          model: model,
          partition: p
        }
      ) do
    {:ok, counter} = cache.track_command(agent, p, id)
    pause_keep_alive(state)
    Logger.debug(fn -> "Agent<#{state.id}>: Command<#{counter}>: #{inspect(command)}" end)

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

        with {:ok, state} <- apply_events(events, state, counter),
             do: {:noreply, reset_keep_alive(state)}

      _ ->
        send(from, {:command, ref, response})
        {:noreply, reset_keep_alive(state)}
    end
  end

  def handle_info({:event, event}, state = %{agent: agent, cache: cache, id: id, partition: p}) do
    with {:ok, counter} <- cache.command_track(agent, p, id),
         {:ok, state} <- apply_events([event], state, counter),
         do: {:noreply, state}
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

  defp apply_events(events, state, counter, offset \\ nil)

  defp apply_events([], state, counter, offset),
    do: {:ok, if(offset, do: notify_offset_callbacks(state, offset), else: state)}

  defp apply_events([event | events], state = %{offset: o}, counter, c_offset) do
    Logger.debug(fn -> "Agent<#{state.id}>: Incoming Event (#{inspect(event)})" end)
    %{offset: offset, partition: partition} = event.__meta__

    if Offset.empty?(o) or Offset.get(o, event.__meta__.partition) < offset do
      case state.model.apply(state.agent_state, event) do
        {:ok, updated_state} ->
          updated_offset = Offset.set(state.offset, partition, offset)
          # Ian:
          #  OK, so on new command, generate events, then set a transaction.
          #  This transaction indicates new events.
          #  If the state then shows that the transaction is incomplete.
          #  Only then needs the eventsource be read.
          if events == [] do
            state.cache.save(
              state.agent,
              partition,
              state.id,
              updated_state,
              updated_offset,
              counter
            )
          end

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

  defp prepare_event(event, _ref, %{id: id, partition: partition}) do
    # meta = %{event.__meta__ | command: ref, partition: partition, key: id}
    meta = %{event.__meta__ | partition: partition, key: id}
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
