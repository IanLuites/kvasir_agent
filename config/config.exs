use Mix.Config

config :kvasir, :agent,
  registry: Kvasir.Agent.Registry.Local,
  cache: Kvasir.Agent.Cache.ETS
