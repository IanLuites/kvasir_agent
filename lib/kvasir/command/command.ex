defmodule Kvasir.Command do
  defstruct [
    :command,
    __meta__: %__MODULE__.Meta{}
  ]

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

  defmacro instance(name) do
    quote do
      Module.put_attribute(__MODULE__, :command_instance, unquote(name))
    end
  end

  defmacro command(do: block) do
    quote do
      Module.register_attribute(__MODULE__, :command_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :command_instance, accumulate: false)

      try do
        import Kvasir.Command, only: [instance: 1, field: 1]
        unquote(block)
      after
        :ok
      end

      @struct_fields Enum.reverse(@command_fields)
      if @command_instance do
        defstruct [@command_instance] ++ @struct_fields ++ [__meta__: %Kvasir.Command.Meta{}]
      else
        defstruct @struct_fields ++ [__meta__: %Kvasir.Command.Meta{}]
      end

      @doc false
      def __command__(:instance), do: @command_instance

      def create(data), do: Kvasir.Command.create(__MODULE__, data)

      def validate(command), do: {:ok, command}
      defoverridable validate: 1
    end
  end

  def create(command, data) do
    data =
      Map.put(data, :__meta__, %Kvasir.Command.Meta{
        id: generate_id(),
        created: DateTime.utc_now()
      })

    command
    |> struct!(data)
    |> command.validate()
  end

  @epoch_time "2018-09-01T00:00:00Z"
              |> DateTime.from_iso8601()
              |> elem(1)
              |> DateTime.to_unix()
              |> Kernel.*(1_000_000)

  @spec generate_id :: non_neg_integer
  defp generate_id do
    micro = :os.system_time(:microsecond) - @epoch_time
    random = :crypto.strong_rand_bytes(8)
    Base.encode64(<<micro::integer-unsigned-64>> <> random, padding: false)
  end
end
