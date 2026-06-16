defmodule Aveline.Comments.DispositionTest do
  use ExUnit.Case, async: true

  alias Aveline.Comments.Disposition

  describe "cast/1" do
    test "resolve requires a non-empty reply body" do
      assert {:error, {:missing_field, "reply"}} =
               Disposition.cast(%{"comment_id" => "c1", "action" => "resolve"})

      assert {:error, {:missing_field, "reply"}} =
               Disposition.cast(%{"comment_id" => "c1", "action" => "resolve", "reply" => "   "})

      assert {:ok, %Disposition{action: "resolve", reply: "thanks, fixed"}} =
               Disposition.cast(%{
                 "comment_id" => "c1",
                 "action" => "resolve",
                 "reply" => "  thanks, fixed  "
               })
    end

    test "reanchor requires a new_block_id; leave needs no extras" do
      assert {:error, {:missing_field, "new_block_id"}} =
               Disposition.cast(%{"comment_id" => "c1", "action" => "reanchor"})

      assert {:ok, %Disposition{action: "reanchor", new_block_id: "b_xyz"}} =
               Disposition.cast(%{
                 "comment_id" => "c1",
                 "action" => "reanchor",
                 "new_block_id" => "b_xyz"
               })

      assert {:ok, %Disposition{action: "leave", reply: nil, new_block_id: nil}} =
               Disposition.cast(%{"comment_id" => "c1", "action" => "leave"})
    end

    test "unknown actions are rejected" do
      assert {:error, {:invalid_action, "bogus"}} =
               Disposition.cast(%{"comment_id" => "c1", "action" => "bogus"})
    end
  end

  describe "validate/4" do
    defp resolve(id, reply \\ "ok"),
      do: %Disposition{comment_id: id, action: "resolve", reply: reply}

    defp leave(id), do: %Disposition{comment_id: id, action: "leave"}

    defp reanchor(id, target),
      do: %Disposition{comment_id: id, action: "reanchor", new_block_id: target}

    test "coverage applies only to required comment ids" do
      # c1 is required (its block was touched), c2 is optional — not in the
      # required set, so it's fine if absent.
      assert :ok = Disposition.validate([resolve("c1")], ["c1"], [], ["b1", "b2"])

      assert {:error, {:disposition_missing, ["c1"]}} =
               Disposition.validate([], ["c1"], [], ["b1"])
    end

    test "extra dispositions on untouched comments are allowed" do
      # An agent opportunistically resolving a doc-level comment alongside
      # the required ones should succeed.
      assert :ok =
               Disposition.validate(
                 [resolve("c1"), resolve("c-extra")],
                 ["c1"],
                 [],
                 ["b1"]
               )
    end

    test "leave is illegal on a comment whose block was deleted" do
      assert {:error, {:leave_on_deleted_block, "c1"}} =
               Disposition.validate([leave("c1")], ["c1"], ["c1"], [])

      assert :ok =
               Disposition.validate(
                 [resolve("c1")],
                 ["c1"],
                 ["c1"],
                 []
               )
    end

    test "reanchor target must exist in the new version's blocks" do
      assert {:error, {:reanchor_target_missing, "c1", "b_gone"}} =
               Disposition.validate([reanchor("c1", "b_gone")], ["c1"], [], ["b1", "b2"])

      assert :ok =
               Disposition.validate([reanchor("c1", "b2")], ["c1"], [], ["b1", "b2"])
    end

    test "duplicates are rejected" do
      assert {:error, {:duplicate_dispositions, ["c1"]}} =
               Disposition.validate(
                 [resolve("c1"), leave("c1")],
                 ["c1"],
                 [],
                 ["b1"]
               )
    end
  end
end
