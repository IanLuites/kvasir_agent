defmodule Kvasir.Agent.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = []

    create_command_registry()
    Kvasir.Agent.Cache.ETS.load(nil, nil)

    opts = [strategy: :one_for_one, name: Kvasir.Agent.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp create_command_registry do
    commands =
      :application.loaded_applications()
      |> Enum.flat_map(fn {app, _, _} ->
        case :application.get_key(app, :modules) do
          :undefined -> []
          {:ok, modules} -> modules
        end
      end)
      |> Enum.filter(&String.starts_with?(to_string(&1), "Elixir.Kvasir.Command.Registry."))

    ensure_unique_commands!(commands)
    registry = Enum.into(commands, %{}, &{&1.type(), &1.module()})

    Code.compiler_options(ignore_module_conflict: true)

    Module.create(
      Kvasir.Command.Registry,
      quote do
        @moduledoc ~S"""
        Kvasir Command Regsitry.
        """

        @doc ~S"""
        Lookup commands.
        """
        @spec lookup(String.t()) :: module | nil
        def lookup(type), do: Map.get(commands(), type)

        @doc ~S"""
        List all commands.
        """
        @spec list :: [module]
        def list, do: Map.values(commands())

        @doc ~S"""
        List all commands matching the filter.
        """
        @spec list(filter :: Keyword.t()) :: [module]
        def list(filter) do
          commands = commands()

          commands =
            if ns = filter[:namespace] do
              ns = to_string(ns) <> "."
              Enum.filter(commands, &String.starts_with?(to_string(elem(&1, 1)), ns))
            else
              commands
            end

          commands =
            if ns = filter[:type_namespace] do
              ns = ns <> "."
              Enum.filter(commands, &String.starts_with?(elem(&1, 0), ns))
            else
              commands
            end

          Enum.map(commands, &elem(&1, 1))
        end

        @doc ~S"""
        All available commands indexed on type.
        """
        @spec commands :: map
        def commands, do: unquote(Macro.escape(registry))
      end,
      Macro.Env.location(__ENV__)
    )

    Code.compiler_options(ignore_module_conflict: false)
  end

  defp ensure_unique_commands!(commands) do
    duplicates =
      commands
      |> Enum.group_by(& &1.type)
      |> Enum.filter(&(Enum.count(elem(&1, 1)) > 1))

    if duplicates == [] do
      :ok
    else
      error =
        duplicates
        |> Enum.map(fn {k, v} ->
          "  \"#{k}\":\n#{v |> Enum.map(&"    * #{inspect(&1.module)}") |> Enum.join("\n")}"
        end)
        |> Enum.join("\n\n")

      raise "Duplicate Command Types\n\n" <> error
    end
  end
end
