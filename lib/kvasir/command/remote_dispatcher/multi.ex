defmodule Kvasir.Command.RemoteDispatcher.Multi do
  @moduledoc ~S"""
  Remote dispatch multiple commands through a single HTTP request.
  """

  defmodule Result do
    @type t :: %__MODULE__{}
    defstruct succeeded: [], failed: %{}

    defimpl Inspect, for: __MODULE__ do
      import Inspect.Algebra

      def inspect(result, _opts) do
        concat([
          "#MultiResult<",
          if(result.failed == %{}, do: "Success", else: "Failed"),
          ">"
        ])
      end
    end

    defimpl Jason.Encoder, for: __MODULE__ do
      def encode(%Kvasir.Command.RemoteDispatcher.Multi.Result{succeeded: s, failed: f}, opts) do
        Jason.Encode.map(
          %{
            succeeded: s,
            failed: Enum.map(f, fn {k, v} -> %{command: k, result: inspect(v)} end)
          },
          opts
        )
      end
    end
  end

  @type t :: %__MODULE__{}
  defstruct commands: %{}

  def new, do: %__MODULE__{}

  def add(m = %__MODULE__{commands: c}, command = %{__meta__: meta}) do
    p = partition(meta)
    %{m | commands: Map.update(c, p, [command], &[command | &1])}
  end

  defp partition(%{scope: {:instance, i = %t{}}}) do
    {:ok, p} = t.partition(i, 10)
    p
  rescue
    _ -> 0
  end

  defp partition(_), do: 0

  def exec(%__MODULE__{commands: c}, dispatch, success?, false) do
    {s, f} = do_exec(c, dispatch, success?)
    result = %Result{succeeded: s, failed: f}

    if f == %{}, do: {:ok, result}, else: {:error, result}
  end

  def exec(%__MODULE__{commands: c}, dispatch, success?, retry),
    do: exec_retry(c, dispatch, success?, retry, [], %{})

  defp exec_retry(commands, dispatch, success?, {timeout, attempts, only}, success, failed) do
    {s, f, retry} =
      if attempts > 1 do
        do_exec(commands, dispatch, success?, only)
      else
        {s, f} = do_exec(commands, dispatch, success?)
        {s, f, %{}}
      end

    done = success ++ s
    fail = Map.merge(failed, f)

    if retry == %{} do
      result = %Result{succeeded: done, failed: fail}
      if f == %{}, do: {:ok, result}, else: {:error, result}
    else
      :timer.sleep(timeout)
      exec_retry(retry, dispatch, success?, {timeout * 2, attempts - 1, only}, done, fail)
    end
  end

  defp do_exec(commands, dispatch, success?) do
    me = self()

    commands
    |> Enum.map(fn p ->
      spawn_link(fn -> send(me, {:ok, exec_partition(p, dispatch, success?)}) end)
    end)
    |> Enum.reduce({[], %{}}, fn _, {x, y} ->
      receive do
        {:ok, {a, b}} -> {a ++ x, Map.merge(b, y)}
      end
    end)
  end

  defp do_exec(commands, dispatch, success?, retry) do
    me = self()

    commands
    |> Enum.map(fn p ->
      spawn_link(fn ->
        send(me, {:ok, exec_partition(p, dispatch, success?, retry)})
        p
      end)
    end)
    |> Enum.reduce({[], %{}, %{}}, fn p, {x, y, z} ->
      receive do
        {:ok, {a, b, c}} -> {a ++ x, Map.merge(b, y), if(c == [], do: z, else: Map.put(z, p, c))}
      end
    end)
  end

  defp exec_partition({_partition, commands}, dispatch, success?) do
    Enum.reduce(commands, {[], %{}}, fn command, {success, failure} ->
      case dispatch.(command) do
        {:ok, c} ->
          {[c | success], failure}

        err = {:error, reason} ->
          if success?.(reason),
            do: {[command | success], failure},
            else: {success, Map.put(failure, command, err)}

        err ->
          {success, Map.put(failure, command, err)}
      end
    end)
  end

  defp exec_partition({_partition, commands}, dispatch, success?, retry?) do
    Enum.reduce(commands, {[], %{}, []}, fn command, {success, failure, retry} ->
      case dispatch.(command) do
        {:ok, c} ->
          {[c | success], failure, retry}

        err = {:error, reason} ->
          cond do
            success?.(reason) -> {[command | success], failure, retry}
            retry?.(reason) -> {success, failure, [command | retry]}
            :error -> {success, Map.put(failure, command, err), retry}
          end

        err ->
          {success, Map.put(failure, command, err), retry}
      end
    end)
  end

  defimpl Inspect, for: __MODULE__ do
    import Inspect.Algebra

    def inspect(result, opts) do
      count =
        result.commands |> Enum.map(fn {_, v} -> Enum.count(v) end) |> Enum.sum() |> to_doc(opts)

      concat(["#Multi<", count, ">"])
    end
  end
end
