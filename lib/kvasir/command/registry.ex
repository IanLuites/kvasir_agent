defmodule Kvasir.Command.RegistryGenerator do
  @moduledoc false

  @spec is_command?(module) :: boolean
  defp is_command?(module) do
    Keyword.has_key?(module.__info__(:attributes), :__command__)
  rescue
    _ -> false
  end

  @spec command_type(module) :: String.t()
  defp command_type(module), do: List.first(module.__info__(:attributes)[:__command__])

  @doc ~S"""
  Index all events and other registries.
  """
  @spec create :: :ok
  def create do
    commands = Enum.filter(ApplicationX.modules(), &is_command?/1)
    ensure_unique_commands!(commands)
    registry = Enum.into(commands, %{}, &{command_type(&1), &1})

    lookup =
      Enum.reduce(registry, nil, fn {k, v}, acc ->
        quote do
          unquote(acc)
          def lookup(unquote(k)), do: unquote(v)
        end
      end)

    Code.compiler_options(ignore_module_conflict: true)

    Module.create(
      Kvasir.Command.Registry,
      quote do
        @moduledoc ~S"""
        Kvasir Command Registry.
        """

        @doc ~S"""
        Lookup a command by a given `type`.

        ## Examples

        ```elixir
        iex> lookup("some-command")
        <cmd>
        iex> lookup("none-existing")
        nil
        ```
        """
        @spec lookup(String.t()) :: module | nil
        def lookup(type)
        unquote(lookup)
        def lookup(_), do: nil

        @doc ~S"""
        List all commands.

        ## Examples

        ```elixir
        iex> list()
        [<cmd>]
        ```
        """
        @spec list :: [module]
        def list, do: Map.values(commands())

        @doc ~S"""
        List all commands matching the filter.

        ## Examples

        ```elixir
        iex> list(namespace: "...")
        [<cmd>]
        ```
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

        ## Examples

        ```elixir
        iex> commands()
        [<cmd>]
        ```
        """
        @spec commands :: map
        def commands, do: unquote(Macro.escape(registry))
      end,
      Macro.Env.location(__ENV__)
    )

    Code.compiler_options(ignore_module_conflict: false)

    :ok
  end

  defp ensure_unique_commands!(commands) do
    duplicates =
      commands
      |> Enum.group_by(&command_type(&1))
      |> Enum.filter(&(Enum.count(elem(&1, 1)) > 1))

    if duplicates == [] do
      :ok
    else
      error =
        duplicates
        |> Enum.map(fn {k, v} ->
          "  \"#{k}\":\n#{v |> Enum.map(&"    * #{inspect(&1)}") |> Enum.join("\n")}"
        end)
        |> Enum.join("\n\n")

      raise "Duplicate Command Types\n\n" <> error
    end
  end
end

Kvasir.Command.RegistryGenerator.create()
