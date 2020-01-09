defmodule Kvasir.Command do
  @moduledoc ~S"""
  """
  alias Kvasir.Command.{Encoder, Meta}
  import NaiveDateTime, only: [utc_now: 0]

  @typedoc @moduledoc
  @type t :: struct

  @callback __command__(atom) :: any
  # @callback create(any) :: {:ok, t} | {:error, atom}
  # @callback create!(any) :: {:ok, t} | {:error, atom}
  # @callback factory(any) :: {:ok, map} | {:error, atom}
  @callback validate(t) :: :ok | {:error, atom}

  @doc @moduledoc
  defmacro __using__(_opts \\ []) do
    quote location: :keep do
      require Kvasir.Command
      import Kvasir.Command, only: [command: 2]
      # import Kvasir.Command.Encodings.Raw, only: [decode: 2]
    end
  end

  defmacro field(name, type \\ :string, opts \\ []) do
    opts = Keyword.put_new(opts, :sensitive, false)

    quote do
      Module.put_attribute(
        __MODULE__,
        :command_fields,
        {unquote(name), unquote(Kvasir.Type.lookup(type)),
         unquote(opts)
         |> Keyword.put_new_lazy(:doc, fn ->
           case Module.delete_attribute(__MODULE__, :doc) do
             {_, doc} -> doc
             _ -> nil
           end
         end)}
      )
    end
  end

  defmacro command(type, do: block) do
    quote location: :keep do
      @command_type unquote(Kvasir.Util.name(type))
      @before_compile Kvasir.Command
      Module.register_attribute(__MODULE__, :command_fields, accumulate: true)

      try do
        import Kvasir.Command, only: [field: 1, field: 2, field: 3]
        unquote(block)
      after
        :ok
      end

      Module.register_attribute(__MODULE__, :__command__, persist: true)
      Module.put_attribute(__MODULE__, :__command__, unquote(Kvasir.Util.name(type)))

      @sensitive_fields @command_fields
                        |> Enum.filter(fn {_, _, o} -> o[:sensitive] end)
                        |> Enum.map(&elem(&1, 0))
      @struct_fields Enum.reverse(@command_fields)
      @instance_id Enum.find_value(
                     @command_fields,
                     :global,
                     &if(elem(&1, 2)[:instance_id], do: elem(&1, 0))
                   )
      defstruct Enum.map(@struct_fields, &elem(&1, 0)) ++ [__meta__: %Kvasir.Command.Meta{}]

      defimpl Jason.Encoder, for: __MODULE__ do
        alias Jason.EncodeError
        alias Jason.Encoder.Map
        alias Kvasir.Command.Encoder

        def encode(value, opts) do
          case Encoder.encode(value) do
            {:ok, data} -> Map.encode(data, opts)
            {:error, error} -> %EncodeError{message: "Command Encoding Error: #{error}"}
          end
        end
      end

      @doc false
      @impl Kvasir.Command
      @spec validate(struct) :: :ok | {:error, atom}
      def validate(command), do: :ok

      @behaviour Kvasir.Command
      defoverridable validate: 1

      @doc false
      @spec create_from(map) :: {:ok, Kvasir.Command.t()} | {:error, atom}
      def create_from(data),
        do: Kvasir.Command.Encoder.decode(%{payload: data, type: __MODULE__}, process: :create)
    end
  end

  defmacro __before_compile__(env) do
    config = Mix.Project.config()
    app = Keyword.get(config, :app)
    version = Keyword.get(config, :version)
    docs = Keyword.get(config, :docs, [])
    package = Keyword.get(config, :package, [])
    dep_depth = config |> Keyword.get(:deps_path) |> Path.split() |> Enum.count()
    path = __CALLER__.file |> Path.split() |> Enum.slice((dep_depth + 1)..-1) |> Path.join()

    {hex, hexdocs} =
      case {Keyword.get(package, :name), Keyword.get(package, :organization)} do
        {nil, _} ->
          nil

        {app, nil} ->
          {"https://hex.pm/packages/#{app}/#{version}",
           "https://hexdocs.pm/#{app}/#{version}/#{inspect(__CALLER__.module)}.html"}

        {app, org} ->
          {"https://hex.pm/packages/#{org}/#{app}/#{version}",
           "https://#{org}.hexdocs.pm/#{app}/#{version}/#{inspect(__CALLER__.module)}.html"}
      end

    source =
      case {Keyword.get(docs, :source_url), Keyword.get(docs, :source_ref)} do
        {nil, _} -> nil
        {url, nil} -> url <> "/src/#{path}"
        {url, ref} -> url <> "/src/#{ref}/#{path}"
      end

    arities =
      env.module
      |> Module.definitions_in(:def)
      |> Enum.filter(&(elem(&1, 0) == :factory))
      |> Enum.map(&elem(&1, 1))
      |> Enum.sort()

    quote location: :keep do
      unquote(creation(arities))

      @doc false
      @impl Kvasir.Command
      @spec __command__(atom) :: term
      def __command__(:type), do: @command_type
      def __command__(:fields), do: @struct_fields
      def __command__(:instance_id), do: @instance_id
      def __command__(:create), do: unquote(arities)
      def __command__(:sensitive), do: @sensitive_fields
      def __command__(:app), do: {unquote(app), unquote(version)}
      def __command__(:doc), do: @moduledoc
      def __command__(:hex), do: unquote(hex)
      def __command__(:hexdocs), do: unquote(hexdocs)
      def __command__(:source), do: unquote(source)

      @field_type Map.new(@struct_fields, fn {k, v, _} -> {k, v} end)
      @doc false
      @spec __command__(atom, atom) :: term
      def __command__(:type, field), do: @field_type[field]

      defimpl Inspect, for: __MODULE__ do
        import Inspect.Algebra

        def inspect(data = %event{}, opts) do
          a =
            data
            |> Map.drop(~w(__meta__ __struct__)a)
            |> Map.new(fn {k, v} ->
              if v != nil and k in event.__command__(:sensitive) do
                {k, %Kvasir.Event.Sensitive{value: v, type: event.__command__(:type, k)}}
              else
                {k, v}
              end
            end)

          concat([
            {:doc_color, :doc_nil, [:reset]},
            "⊰",
            inspect(data.__struct__),
            {:doc_color, :doc_nil, [:italic, :yellow]},
            "<",
            data.__meta__.id || "NotDispatched",
            ">",
            {:doc_color, :doc_nil, :reset},
            remove(to_doc(a, opts)),
            {:doc_color, :doc_nil, :reset},
            "⊱"
          ])
        end

        defp remove({a, "%{", c}), do: {a, "{", c}
        defp remove({a, b, c}), do: {a, remove(b), c}
        defp remove({a, b, c, d}), do: {a, remove(b), c, d}
      end
    end
  end

  defp creation([]) do
    quote do
      @doc ~S"""
      Create this command based on the given data.

      ## Example

      ```elixir
      iex> create(key: value)
      {:ok, <command>}
      ```
      """
      # @impl Kvasir.Command
      @spec create(term) :: {:ok, struct} | {:error, term}
      def create(data), do: Kvasir.Command.create(__MODULE__, [data])

      @doc ~S"""
      Create this command based on the given data.
      See: `create/1`.

      ## Example

      ```elixir
      iex> create!(key: value)
      <command>
      ```
      """
      # @impl Kvasir.Command
      @spec create!(term) :: struct | no_return
      def create!(data), do: Kvasir.Command.create!(__MODULE__, [data])

      @doc false
      # @impl Kvasir.Command
      @spec factory(term) :: {:ok, term} | {:error, term}
      def factory(payload) when is_list(payload), do: {:ok, Map.new(payload)}
      def factory(payload), do: {:ok, payload}
    end
  end

  defp creation(arities) do
    Enum.reduce(arities, nil, fn arity, acc ->
      data = 1..arity |> Enum.map(&Macro.var(:"arg#{&1}", nil))

      spec_create =
        {:@, [context: Elixir, import: Kernel],
         [
           {:spec, [context: Elixir],
            [
              {:"::", [],
               [
                 {:create, [], Enum.map(1..arity, fn _ -> {:term, [], Elixir} end)},
                 {:|, [], [ok: {:struct, [], Elixir}, error: {:term, [], Elixir}]}
               ]}
            ]}
         ]}

      spec_create! =
        {:@, [context: Elixir, import: Kernel],
         [
           {:spec, [context: Elixir],
            [
              {:"::", [],
               [
                 {:create!, [], Enum.map(1..arity, fn _ -> {:term, [], Elixir} end)},
                 {:|, [], [{:struct, [], Elixir}, error: {:term, [], Elixir}]}
               ]}
            ]}
         ]}

      quote do
        unquote(acc)

        @doc """
        Create this command based on the given data.

        ## Example

        ```elixir
        iex> create(#{unquote(1..arity |> Enum.map(&"arg#{&1}") |> Enum.join(", "))})
        {:ok, <command>}
        ```

        ## Note


        """
        # @impl Kvasir.Command
        unquote(spec_create)
        def create(unquote_splicing(data)), do: Kvasir.Command.create(__MODULE__, unquote(data))

        @doc """
        Create this command based on the given data.

        See: `create/#{unquote(arity)}`.

        ## Example

        ```elixir
        iex> create!(#{unquote(1..arity |> Enum.map(&"arg#{&1}") |> Enum.join(", "))})
        <command>
        ```
        """
        # @impl Kvasir.Command
        unquote(spec_create!)
        def create!(unquote_splicing(data)), do: Kvasir.Command.create!(__MODULE__, unquote(data))
      end
    end)
  end

  @doc ~S"""
  Create a command by passing the command module and payload.
  """
  def create(command, data) do
    with {:ok, payload} <- apply(command, :factory, data),
         {:ok, result} <- decode(command, payload, %Meta{created: utc_now()}),
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

  def set_executed(command), do: update_meta(command, :executed, utc_now())
  def set_applied(command), do: update_meta(command, :applied, utc_now())
  def set_offset(command, offset), do: update_meta(command, :offset, offset)

  defp update_meta(command = %{__meta__: meta}, field, value),
    do: %{command | __meta__: Map.put(meta, field, value)}

  defdelegate encode(value, opts \\ []), to: Encoder
  defdelegate decode(value, opts \\ []), to: Encoder
  defdelegate decode(command, payload, meta), to: Encoder
end
