defmodule Kvasir.Agent.Cache.ETS do
  @behaviour Kvasir.Agent.Cache
  @storage_table __MODULE__

  @impl Kvasir.Agent.Cache
  def save(module, id, data, offset) do
    ensure_storage_table_created()

    :ets.insert(@storage_table, {{module, id}, data, offset})
  end

  @impl Kvasir.Agent.Cache
  def load(module, id) do
    ensure_storage_table_created()

    case :ets.lookup(@storage_table, {module, id}) do
      [{_, cache, offset}] -> {:ok, offset, cache}
      _ -> {:error, :not_found}
    end
  end

  @spec ensure_storage_table_created :: module
  defp ensure_storage_table_created do
    case :ets.info(@storage_table) do
      :undefined -> :ets.new(@storage_table, [:set, :public, :named_table])
      _ -> @storage_table
    end
  end
end
