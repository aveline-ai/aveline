defmodule Aveline.ContractTest do
  @moduledoc """
  The contract is a promise to agents about block/op shapes. These tests
  keep the promise honest: coverage must match the real type/op lists,
  and every example must pass the real validator. Drift breaks the test,
  not the agent.
  """
  use ExUnit.Case, async: true

  alias Aveline.Blocks.Block
  alias Aveline.Blocks.Operation
  alias Aveline.Contract

  test "block_types cover exactly the real Block.types/0" do
    assert Enum.sort(Contract.block_type_names()) == Enum.sort(Block.types())
  end

  test "operations cover exactly the real Operation.ops/0" do
    assert Enum.sort(Contract.operation_names()) == Enum.sort(Operation.ops())
  end

  test "every block example validates against Block.validate/2" do
    for example <- Contract.block_examples() do
      assert {:ok, _} = Block.validate(example, mint_id?: true),
             "block example did not validate: #{inspect(example)}"
    end
  end

  test "every op example validates against Operation.validate/1" do
    for example <- Contract.operation_examples() do
      assert {:ok, _} = Operation.validate(example),
             "op example did not validate: #{inspect(example)}"
    end
  end

  test "write_contract is JSON-encodable and has the top-level sections" do
    contract = Contract.write_contract()
    assert {:ok, _json} = Jason.encode(contract)

    for key <- ~w(overview ids inline_spans block_types operations edit_modes dispositions) do
      assert Map.has_key?(contract, key), "missing contract section: #{key}"
    end
  end
end
