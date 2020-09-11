defmodule Kvasir.Agent.Instance do
  use GenServer
  require Logger
  alias Kvasir.Offset
  @keep_alive 15 * 60_000
  @keep_hibernated 5 * @keep_alive

  def start_agent(agent, partition, id, opts) do
    config =
      :config
      |> agent.__agent__()
      |> Map.put(:id, id)
      |> Map.put(:partition, partition)
      |> Map.update!(:cache, &elem(&1, 0))

    GenServer.start_link(__MODULE__, config, opts)
  end

  def pre_start_agent(agent, partition, id, offset, state, cache, opts \\ []) do
    config = %{model: m} = agent.__agent__(:config)

    with {:ok, s} <- m.__decode__(state) do
      c =
        config
        |> Map.put(:id, id)
        |> Map.put(:partition, partition)
        |> Map.put(:agent_state, s)
        |> Map.put(:offset, offset)
        |> Map.put(:cache, cache)
        |> Map.put(:callbacks, %{})

      GenServer.start_link(__MODULE__, {:preload, c}, opts)
    end
  end

  @impl GenServer
  def init({:preload, state}) do
    Logger.debug(fn -> "Agent<#{state.id}>: Preloaded-Init (#{inspect(self())})" end)
    initialize(state)
  end

  def init(
        state = %{
          source: source,
          agent: agent,
          partition: partition,
          id: id,
          cache: cache_mod,
          topic: topic,
          model: model
        }
      ) do
    Logger.debug(fn -> "Agent<#{state.id}>: Init (#{inspect(self())})" end)

    with {:ok, c} <- cache_mod.cache(agent, partition, id),
         cache = {cache_mod, c},
         {:ok, {offset, agent_state}} <- load_state(source, cache, topic, model, id) do
      state
      |> Map.put(:agent_state, agent_state)
      |> Map.put(:offset, offset)
      |> Map.put(:cache, cache)
      |> Map.put(:callbacks, %{})
      |> initialize()
    end
  end

  @spec initialize(map) :: {:ok, map}
  defp initialize(state) do
    Logger.debug(fn -> "Agent<#{state.id}>: Initialized" end)

    keep_alive =
      if @keep_alive != :infinity,
        do: Process.send_after(self(), {:hibernate, :keep_alive}, @keep_alive)

    {:ok, state |> Map.put(:hibernate, nil) |> Map.put(:keep_alive, keep_alive)}
  end

  defp load_state(source, {cache_m, cache_i}, topic, model, id) do
    case cache_m.load(cache_i) do
      :no_previous_state ->
        Logger.debug(fn -> "Agent<#{id}>: State Loaded: No State, Setup New" end)
        {:ok, {Kvasir.Offset.create(), model.base(id)}}

      {:ok, offset, state} ->
        Logger.debug(fn -> "Agent<#{id}>: State Loaded: #{inspect(offset)}" end)
        # build_state(source, topic, model, id, offset, state)
        with {:ok, s} <- model.__decode__(state), do: {:ok, {offset, s}}

      {:error, :corrupted_state} ->
        Logger.warn(fn ->
          "Agent<#{id}>: State Load Failed: Corrupted State"
        end)

        with r = {:ok, {offset, agent_state}} <-
               build_state(source, topic, model, id, nil, model.base(id)) do
          cache_m.save(cache_i, model.__encode__(agent_state), offset)
          r
        end

      {:error, reason} ->
        Logger.error(fn -> "Agent<#{id}>: State Load Failed: #{reason}" end)
        build_state(source, topic, model, id, nil, model.base(id))
    end
  end

  defp build_state(source, topic, model, id, offset, original_state) do
    base = {offset || Kvasir.Offset.create(), original_state, false}

    with {:ok, {a, b, _}} <-
           topic
           |> source.stream(from: offset, to: :last, key: id)
           |> Stream.filter(&is_map/1)
           |> EnumX.reduce_while(base, &state_reducer(model, &1, &2)),
         do: {:ok, {a, b}}
  end

  defp state_reducer(_model, err = {:error, _}, _), do: err

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

  defp state_reducer(_model, _event, err), do: err

  @impl GenServer
  def handle_info(
        {:command, from, command},
        state = %{
          agent_state: agent_state,
          cache: {cache_m, cache_i},
          model: model,
          partition: p
        }
      ) do
    pause_keep_alive(state)
    Logger.debug(fn -> "Agent<#{state.id}>: Command: #{inspect(command)}" end)

    ref = command.__meta__.id

    response =
      case model.execute(agent_state, command) do
        {:ok, events} when is_list(events) ->
          :ok = cache_m.track_command(cache_i)
          commit_events(state, events, ref)

        {:ok, event} ->
          :ok = cache_m.track_command(cache_i)
          commit_events(state, [event], ref)

        :ok ->
          :ok

        error ->
          error
      end

    case response do
      {:ok, events} ->
        send(from, {:command, ref, {:ok, Offset.create(p, List.last(events).__meta__.offset)}})

        with {:ok, state} <- apply_events(events, state),
             do: {:noreply, reset_keep_alive(state)}

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

  def handle_info({:hibernate, reason}, state) do
    Logger.debug(fn -> "Agent<#{state.id}>: Hibernate (#{inspect(reason)})" end)

    hibernate =
      if @keep_hibernated != :infinity,
        do: Process.send_after(self(), {:shutdown, :hibernated}, @keep_hibernated)

    {:noreply, %{state | hibernate: hibernate}, :hibernate}
  end

  def handle_info({:shutdown, reason}, state) do
    Logger.debug(fn -> "Agent<#{state.id}>: Shutdown (#{inspect(reason)})" end)
    {:stop, :shutdown, state}
  end

  @impl GenServer
  def handle_call(:inspect, _from, state) do
    {:reply, state.agent_state, state}
  end

  def handle_call(:rebuild, _from, state) do
    %{source: source, cache: {cache_m, cache_i}, topic: topic, model: model, id: id} = state

    Logger.debug(fn ->
      "Agent<#{id}>: Forced State Rebuild"
    end)

    with {:ok, {offset, agent_state}} <-
           build_state(source, topic, model, id, nil, model.base(id)) do
      cache_m.save(cache_i, model.__encode__(agent_state), offset)

      updated_state =
        state
        |> Map.put(:agent_state, agent_state)
        |> Map.put(:offset, offset)

      {:reply, :ok, updated_state}
    else
      {:ok, {_, _, false}} -> {:reply, :ok, state}
      err -> {:reply, err, state}
    end
  end

  defp apply_events(events, state) do
    with {:ok, new_state = %{offset: o}, updated} <- do_apply_events(events, state) do
      if updated do
        %{cache: {cache_m, cache_i}, model: model, agent_state: agent_state} = new_state
        :ok = cache_m.save(cache_i, model.__encode__(agent_state), o)
      end

      notify_offset_callbacks(new_state, o)

      {:ok, new_state}
    end
  end

  defp do_apply_events(events, state, updated \\ false)

  defp do_apply_events([], state, updated), do: {:ok, state, updated}

  defp do_apply_events([event | events], state = %{offset: o}, updated) do
    Logger.debug(fn -> "Agent<#{state.id}>: Incoming Event (#{inspect(event)})" end)
    %{offset: offset, partition: partition} = event.__meta__

    if Offset.empty?(o) or Offset.get(o, event.__meta__.partition) < offset do
      case state.model.apply(state.agent_state, event) do
        :ok ->
          new_state = %{state | offset: Offset.set(state.offset, partition, offset)}
          do_apply_events(events, new_state, true)

        {:ok, updated_state} ->
          updated_offset = Offset.set(state.offset, partition, offset)
          new_state = %{state | offset: updated_offset, agent_state: updated_state}
          do_apply_events(events, new_state, true)

        {:error, reason} ->
          if Kvasir.Event.on_error(event) == :halt do
            Logger.error(fn -> "Agent<#{state.id}>: Event error (#{inspect(reason)})" end)
            {:stop, :invalid_event, state}
          else
            Logger.warn(fn -> "Agent<#{state.id}>: Event error (#{inspect(reason)})" end)
            # Should this be true? We updated by skipping I guess
            do_apply_events(events, state, true)
          end
      end
    else
      do_apply_events(events, state, updated)
    end
  end

  defp pause_keep_alive(%{hibernate: h_ref, keep_alive: a_ref}) do
    h_ref && Process.cancel_timer(h_ref)
    a_ref && Process.cancel_timer(a_ref)

    :ok
  end

  defp reset_keep_alive(state = %{keep_alive: nil}), do: state

  defp reset_keep_alive(state) do
    pause_keep_alive(state)

    %{
      state
      | hibernate: nil,
        keep_alive: Process.send_after(self(), {:hibernate, :keep_alive}, @keep_alive)
    }
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
