defmodule Kvasir.Agent.Config do
  def cache(opts) do
    case opts[:cache] || settings()[:cache] do
      {mod, opt} -> {mod, opt}
      mod -> {mod, []}
    end
  end

  def cache!(opts), do: cache(opts) || raise("Cache not set for agent or in config.")

  def registry(opts), do: opts[:registry] || settings()[:registry]
  def registry!(opts), do: registry(opts) || raise("Registry not set for agent or in config.")

  defp settings, do: Application.get_env(:kvasir, :agent, [])
end
