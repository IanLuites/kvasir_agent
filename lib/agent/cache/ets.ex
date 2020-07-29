defmodule Kvasir.Agent.Cache.ETS do
  @behaviour Kvasir.Agent.Cache
  @storage_table __MODULE__

  @impl Kvasir.Agent.Cache
  def init(_agent, _partition, _) do
    ensure_storage_table_created()
  end

  @impl Kvasir.Agent.Cache
  def cache(agent, _partition, id), do: {:ok, {agent, id}}

  @impl Kvasir.Agent.Cache
  def track_command(cache) do
    ensure_storage_table_created()

    case load(cache) do
      {:ok, offset, data} ->
        :ets.insert(@storage_table, {cache, true, data, offset})

      :no_previous_state ->
        :ets.insert(@storage_table, {cache, true})

      err ->
        err
    end
  end

  @impl Kvasir.Agent.Cache
  def save(cache, data, offset) do
    ensure_storage_table_created()

    :ets.insert(@storage_table, {cache, false, data, offset})
    :ok
  end

  @impl Kvasir.Agent.Cache
  def load(cache) do
    ensure_storage_table_created()

    case :ets.lookup(@storage_table, cache) do
      [] ->
        :no_previous_state

      [{_, true}] ->
        {:error, :corrupted_state}

      [{_, processing, data, offset}] ->
        if processing do
          {:error, :corrupted_state}
        else
          {:ok, offset, data}
        end

      _ ->
        {:ok, Kvasir.Offset.create(), nil}
    end
  end

  @impl Kvasir.Agent.Cache
  def delete(cache) do
    ensure_storage_table_created()
    :ets.delete(@storage_table, cache)

    :ok
  end

  @spec ensure_storage_table_created :: :ok
  defp ensure_storage_table_created do
    case :ets.info(@storage_table) do
      :undefined -> :ets.new(@storage_table, [:set, :public, :named_table])
      _ -> @storage_table
    end
  end
end
