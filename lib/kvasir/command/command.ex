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

  defmacro field(name, type \\ :string, opts \\ []) do
    quote do
      Module.put_attribute(
        __MODULE__,
        :command_fields,
        {unquote(name), unquote(type), unquote(opts)}
      )
    end
  end

  defmacro command(do: block) do
    quote do
      Module.register_attribute(__MODULE__, :command_fields, accumulate: true)

      try do
        import Kvasir.Command, only: [field: 1, field: 2, field: 3]
        unquote(block)
      after
        :ok
      end

      @struct_fields Enum.reverse(@command_fields)
      @instance_id Enum.find_value(
                     @command_fields,
                     :global,
                     &if(elem(&1, 2)[:instance_id], do: elem(&1, 0))
                   )
      defstruct Enum.map(@struct_fields, &elem(&1, 0)) ++ [__meta__: %Kvasir.Command.Meta{}]

      @behaviour Kvasir.Command

      @doc false
      @impl Kvasir.Command
      def __command__(:fields), do: @struct_fields
      def __command__(:instance_id), do: @instance_id

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

      defimpl Jason.Encoder, for: __MODULE__ do
        alias Jason.EncodeError
        alias Jason.Encoder.Map
        alias Kvasir.Command.Encoder

        def encode(value, opts) do
          case Encoder.encode(value, encoding: :raw) do
            {:ok, data} -> Map.encode(data, opts)
            {:error, error} -> %EncodeError{message: "Command Encoding Error: #{error}"}
          end
        end
      end
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
  rescue
    KeyError -> {:error, :invalid_command_data}
  end

  def create!(command, data) do
    with {:ok, result} <- create(command, data) do
      result
    else
      {:error, reason} -> raise "Failed to create #{command}, reason: #{reason}"
    end
  end

  def is_command?(command) when is_atom(command), do: true
  def is_command?(_), do: false

  defdelegate decode(value, meta \\ %Kvasir.Command.Meta{}), to: Kvasir.Command.Decoder
end
