defmodule Kvasir.Agent.Cache.ETS do
  @behaviour Kvasir.Agent.Cache
  @storage_table __MODULE__
  @tracker_table __MODULE__.Tracks

  @impl Kvasir.Agent.Cache
  def init(_agent, _partition, _) do
    ensure_storage_table_created()
  end

  @impl Kvasir.Agent.Cache
  def track_command(agent, _partition, id) do
    ensure_storage_table_created()
    counter = command_count(agent, id) + 1

    :ets.insert(@tracker_table, {{agent, id}, counter})

    {:ok, counter}
  end

  @impl Kvasir.Agent.Cache
  def save(module, _partition, id, data, offset, command_counter) do
    ensure_storage_table_created()

    :ets.insert(@storage_table, {{module, id}, data, offset, command_counter})
  end

  @impl Kvasir.Agent.Cache
  def load(module, _partition, id) do
    ensure_storage_table_created()
    counter = command_count(module, id)

    case :ets.lookup(@storage_table, {module, id}) do
      [{_, data, offset, commands}] ->
        if counter == commands do
          {:ok, offset, data}
        else
          {:error, :state_counter_mismatch, counter, commands}
        end

      _ ->
        {:ok, Kvasir.Offset.create(), nil}
    end
  end

  @impl Kvasir.Agent.Cache
  def delete(module, _partition, id) do
    ensure_storage_table_created()
    :ets.delete(@storage_table, {module, id})
    :ets.delete(@tracker_table, {module, id})

    :ok
  end

  @spec command_count(module, term) :: non_neg_integer()
  defp command_count(module, id) do
    case :ets.lookup(@tracker_table, {module, id}) do
      [{_, command_counter}] -> command_counter
      _ -> 0
    end
  end

  @spec ensure_storage_table_created :: :ok
  defp ensure_storage_table_created do
    case :ets.info(@storage_table) do
      :undefined -> :ets.new(@storage_table, [:set, :public, :named_table])
      _ -> @storage_table
    end

    case :ets.info(@tracker_table) do
      :undefined -> :ets.new(@tracker_table, [:set, :public, :named_table])
      _ -> @tracker_table
    end
  end
end
