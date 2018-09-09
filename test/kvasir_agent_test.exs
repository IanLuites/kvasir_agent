defmodule Kvasir.AgentTest do
  use ExUnit.Case
  doctest Kvasir.Agent

  test "greets the world" do
    assert Kvasir.Agent.hello() == :world
  end
end
