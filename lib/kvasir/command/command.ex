defmodule Kvasir.Command do
  @moduledoc ~S"""
  """

  @typedoc @moduledoc
  @type t :: term

  @callback __command__(atom) :: any
  @callback create(any) :: {:ok, t} | {:error, atom}
  @callback create!(any) :: {:ok, t} | {:error, atom}
  @callback factory(any) :: {:ok, map} | {:error, atom}
  @callback validate(t) :: :ok | {:error, atom}

  @doc @moduledoc
  defmacro __using__(_opts \\ []) do
    quote do
      require Kvasir.Command
      import Kvasir.Command, only: [command: 1]
    end
  end

  defmacro field(name) do
    quote do
      Module.put_attribute(__MODULE__, :command_fields, unquote(name))
    end
  end

  defmacro command(do: block) do
    quote do
      Module.register_attribute(__MODULE__, :command_fields, accumulate: true)

      try do
        import Kvasir.Command, only: [field: 1]
        unquote(block)
      after
        :ok
      end

      @struct_fields Enum.reverse(@command_fields)
      defstruct @struct_fields ++ [__meta__: %Kvasir.Command.Meta{}]

      @behaviour Kvasir.Command

      @doc false
      @impl Kvasir.Command
      def __command__(:instance), do: @command_instance

      @doc ~S"""
      Create this command.
      """
      @impl Kvasir.Command
      def create(data), do: Kvasir.Command.create(__MODULE__, data)

      @doc ~S"""
      See: `create/1`.
      """
      @impl Kvasir.Command
      def create!(data), do: Kvasir.Command.create!(__MODULE__, data)

      @doc false
      @impl Kvasir.Command
      def factory(payload), do: {:ok, payload}

      @doc false
      @impl Kvasir.Command
      def validate(command), do: :ok

      defoverridable validate: 1, factory: 1
    end
  end

  @doc ~S"""
  Create a command by passing the command module and payload.
  """
  def create(command, data) do
    meta = %Kvasir.Command.Meta{
      created: DateTime.utc_now()
    }

    with {:ok, payload} <- command.factory(data),
         result <- struct!(command, Map.put(payload, :__meta__, meta)),
         :ok <- command.validate(result) do
      {:ok, result}
    end
  end

  def create!(command, data) do
    with {:ok, result} <- create(command, data) do
      result
    else
      {:error, reason} -> raise "Failed to create #{command}, reason: #{reason}"
    end
  end
end
