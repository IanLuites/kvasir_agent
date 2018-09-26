defmodule Kvasir.Command.Registry do
  @moduledoc ~S"""
  Command registry stub.

  Overloaded with actual module at startup.
  """

  @doc ~S"""
  Lookup commands.
  """
  @spec lookup(String.t()) :: module | nil
  def lookup(_type), do: nil

  @doc ~S"""
  List all commands.
  """
  @spec list :: [module]
  def list, do: []

  @doc ~S"""
  List all commands matching the filter.
  """
  @spec list(filter :: Keyword.t()) :: [module]
  def list(_filter), do: []

  @doc ~S"""
  All available commands indexed on type.
  """
  @spec commands :: map
  def commands, do: %{}
end
