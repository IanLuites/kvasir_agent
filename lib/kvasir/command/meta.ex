defmodule Kvasir.Command.Meta do
  @type t :: %__MODULE__{
          id: String.t(),
          created: UTCDateTime.t(),
          dispatched: UTCDateTime.t(),
          executed: UTCDateTime.t(),
          applied: UTCDateTime.t(),
          scope: :global | {:instance, term},
          dispatch: :single | :multiple,
          wait: :dispatch | :execute | :apply,
          timeout: :infinity | pos_integer,
          offset: Kvasir.Offset.t()
        }

  defstruct [
    :id,
    :created,
    :dispatched,
    :executed,
    :applied,
    :scope,
    :dispatch,
    :wait,
    :timeout,
    :offset
  ]

  defimpl Inspect do
    def inspect(%{id: nil}, _opts), do: "#Kvasir.Command.Meta<NotDispatched>"
    def inspect(%{id: id}, _opts), do: "#Kvasir.Command.Meta<#{id}>"
  end

  @doc false
  @spec encode(t) :: map
  def encode(meta) do
    meta
    |> Map.from_struct()
    |> Enum.reject(&is_nil(elem(&1, 1)))
    |> Enum.map(fn {k, v} -> {k, if(is_tuple(v), do: Tuple.to_list(v), else: v)} end)
    |> Enum.into(%{})
  end

  @doc false
  @spec encode(map) :: t
  def decode(data, meta \\ %__MODULE__{})
  def decode(data, nil), do: decode(data)
  def decode(nil, meta), do: meta

  def decode(data, meta) when is_map(data) do
    struct!(
      __MODULE__,
      for(
        {key, val} when val != nil <- data,
        into: Map.from_struct(meta),
        do: parse_meta(to_string(key), val)
      )
    )
  end

  @spec parse_meta(String.t(), any) :: {atom, any}
  defp parse_meta("id", value), do: {:id, value}
  defp parse_meta("created", value), do: {:created, UTCDateTime.from_iso8601!(value)}
  defp parse_meta("dispatched", value), do: {:dispatched, UTCDateTime.from_iso8601!(value)}
  defp parse_meta("executed", value), do: {:executed, UTCDateTime.from_iso8601!(value)}
  defp parse_meta("applied", value), do: {:applied, UTCDateTime.from_iso8601!(value)}
  defp parse_meta("scope", "global"), do: {:scope, :global}
  defp parse_meta("scope", ["instance", value]), do: {:scope, {:instance, value}}
  defp parse_meta("dispatch", value), do: {:dispatch, String.to_existing_atom(value)}
  defp parse_meta("wait", wait), do: {:wait, String.to_existing_atom(wait)}
  defp parse_meta("timeout", "infinity"), do: {:timeout, :infinity}
  defp parse_meta("timeout", value) when is_integer(value), do: {:timeout, value}
  defp parse_meta("offset", nil), do: {:offset, nil}

  defp parse_meta("offset", offset),
    do:
      {:offset, Kvasir.Offset.create(Map.new(offset, fn {k, v} -> {String.to_integer(k), v} end))}
end
