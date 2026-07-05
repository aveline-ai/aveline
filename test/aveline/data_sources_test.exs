defmodule Aveline.DataSourcesTest do
  use Aveline.DataCase, async: false

  alias Aveline.Blocks.Block
  alias Aveline.DataSources
  alias Aveline.DataSources.Runner
  alias Aveline.Docs
  alias Aveline.Fixtures

  # The test database itself — the runner opens a real second
  # connection, so queries must not depend on sandboxed rows.
  defp self_url do
    "postgres://#{System.get_env("PGUSER") || "postgres"}:#{System.get_env("PGPASSWORD") || "postgres"}@#{System.get_env("PGHOST") || "localhost"}/aveline_test#{System.get_env("MIX_TEST_PARTITION")}"
  end

  defp setup_ws do
    user = Fixtures.user_fixture()
    ws = Fixtures.workspace_fixture(user)
    %{user: user, ws: ws}
  end

  describe "context" do
    test "create derives adapter from the URL scheme" do
      %{user: user, ws: ws} = setup_ws()

      {:ok, pg} = DataSources.create(ws.id, "pg", "postgres://u:p@h:5432/db", user.id)
      assert pg.adapter == "postgres"

      {:ok, pg2} = DataSources.create(ws.id, "pg2", "postgresql://u:p@h/db", user.id)
      assert pg2.adapter == "postgres"

      {:ok, my} = DataSources.create(ws.id, "my", "mysql://u:p@h:3306/db", user.id)
      assert my.adapter == "mysql"

      assert {:error, :invalid_data_source_url, msg} =
               DataSources.create(ws.id, "bad", "http://h/db", user.id)

      assert msg =~ "unsupported scheme"

      assert {:error, :invalid_data_source_url, _} =
               DataSources.create(ws.id, "bad2", "not a url", user.id)
    end

    test "the URL is encrypted at rest and never in safe_map" do
      %{user: user, ws: ws} = setup_ws()
      url = "postgres://secret_user:secret_pass@db.example.com:5432/prod"
      {:ok, ds} = DataSources.create(ws.id, "prod", url, user.id)

      # Raw column is ciphertext, not the plaintext.
      %{rows: [[raw]]} =
        Repo.query!("SELECT url_encrypted FROM data_sources WHERE id = $1", [
          Ecto.UUID.dump!(ds.id)
        ])

      refute raw =~ "secret_pass"
      refute raw == url

      # Schema read decrypts transparently.
      assert DataSources.get_current_by_name(ws.id, "prod").url == url

      # The read surface never carries it.
      safe = DataSources.safe_map(ds)
      refute Map.has_key?(safe, "url")
      assert safe["host"] == "db.example.com"
      assert safe["database"] == "prod"
      assert safe["adapter"] == "postgres"
    end

    test "delete keeps the audit row but hard-deletes the credential" do
      %{user: user, ws: ws} = setup_ws()
      {:ok, ds} = DataSources.create(ws.id, "prod", "postgres://u:secret@h/db", user.id)

      assert {:error, %Ecto.Changeset{}} =
               DataSources.create(ws.id, "prod", "postgres://u:p@h/db2", user.id)

      {:ok, deleted} = DataSources.delete(ds, user.id)
      assert DataSources.get_current_by_name(ws.id, "prod") == nil

      # The credential is GONE at the storage layer, not just hidden.
      %{rows: [[raw]]} =
        Repo.query!("SELECT url_encrypted FROM data_sources WHERE id = $1", [
          Ecto.UUID.dump!(ds.id)
        ])

      assert raw == nil
      assert deleted.url == nil

      # The audit trail survives.
      [row] = DataSources.list_all_for_workspace(ws.id)
      assert row.name == "prod"
      assert row.adapter == "postgres"
      assert row.deleted_at

      # No restore concept — but the name frees up for a replacement.
      {:ok, replacement} = DataSources.create(ws.id, "prod", "postgres://u:new@h/db", user.id)
      assert replacement.base_data_source_id != ds.base_data_source_id
    end
  end

  describe "chart block validation" do
    test "valid chart normalizes; echoes stripped" do
      uuid = Ecto.UUID.generate()

      assert {:ok, out} =
               Block.validate(
                 %{
                   "type" => "chart",
                   "data_source_id" => uuid,
                   "query" => "select 1",
                   "viz" => %{"type" => "line", "x" => "a", "y" => "b", "junk" => true},
                   "result" => %{"rows" => [["stale"]]},
                   "source" => %{"name" => "forged"}
                 },
                 mint_id?: true
               )

      assert out["data_source_id"] == uuid
      assert out["viz"] == %{"type" => "line", "x" => "a", "y" => "b"}
      refute Map.has_key?(out, "result")
      refute Map.has_key?(out, "source")
    end

    test "viz validation" do
      uuid = Ecto.UUID.generate()
      base = %{"type" => "chart", "data_source_id" => uuid, "query" => "select 1"}

      # Default viz is table.
      assert {:ok, out} = Block.validate(base, mint_id?: true)
      assert out["viz"] == %{"type" => "table"}

      assert {:error, msg} =
               Block.validate(Map.put(base, "viz", %{"type" => "pie"}), mint_id?: true)

      assert msg =~ "viz.type"

      assert {:error, msg} =
               Block.validate(Map.put(base, "viz", %{"type" => "line"}), mint_id?: true)

      assert msg =~ "needs x and y"

      assert {:error, _} = Block.validate(Map.put(base, "query", "   "), mint_id?: true)
    end
  end

  describe "resolution" do
    test "source name resolves to the base id; unknown name rejected" do
      %{user: user, ws: ws} = setup_ws()
      {:ok, ds} = DataSources.create(ws.id, "self", self_url(), user.id)

      {:ok, doc} =
        Docs.create_doc(%{
          workspace_id: ws.id,
          owner_id: user.id,
          actor_user_id: user.id,
          actor_type: "agent",
          title: "Dash",
          blocks: [%{"type" => "chart", "source" => "self", "query" => "select 1 as one"}],
          intent: "test"
        })

      assert [%{"data_source_id" => id} = blk] = doc.blocks
      assert id == ds.base_data_source_id
      refute Map.has_key?(blk, "source")

      assert {:error, :data_source_not_found, _} =
               Docs.create_doc(%{
                 workspace_id: ws.id,
                 owner_id: user.id,
                 actor_user_id: user.id,
                 actor_type: "agent",
                 title: "Bad",
                 blocks: [%{"type" => "chart", "source" => "ghost", "query" => "select 1"}],
                 intent: "test"
               })
    end

    test "data source from another workspace is rejected" do
      %{user: user, ws: ws} = setup_ws()
      other = Fixtures.workspace_fixture(user)
      {:ok, ds} = DataSources.create(other.id, "theirs", "postgres://u:p@h/db", user.id)

      assert {:error, :data_source_not_found, _} =
               Docs.create_doc(%{
                 workspace_id: ws.id,
                 owner_id: user.id,
                 actor_user_id: user.id,
                 actor_type: "agent",
                 title: "Cross",
                 blocks: [
                   %{
                     "type" => "chart",
                     "data_source_id" => ds.base_data_source_id,
                     "query" => "select 1"
                   }
                 ],
                 intent: "test"
               })
    end
  end

  describe "runner + enrichment" do
    test "runs a real query and echoes columns/rows" do
      %{user: user, ws: ws} = setup_ws()
      {:ok, _} = DataSources.create(ws.id, "self", self_url(), user.id)

      {:ok, doc} =
        Docs.create_doc(%{
          workspace_id: ws.id,
          owner_id: user.id,
          actor_user_id: user.id,
          actor_type: "agent",
          title: "Dash",
          blocks: [
            %{
              "type" => "chart",
              "source" => "self",
              "query" => "select generate_series(1, 3) as n"
            }
          ],
          intent: "test"
        })

      assert [%{"result" => result, "source" => source}] = Docs.enrich_blocks(doc.blocks, ws.id)
      assert result["columns"] == ["n"]
      assert result["rows"] == [[1], [2], [3]]
      assert source["name"] == "self"
      refute Map.has_key?(source, "url")
    end

    test "row cap truncates and flags" do
      %{user: user, ws: ws} = setup_ws()
      {:ok, ds} = DataSources.create(ws.id, "self", self_url(), user.id)

      assert {:ok, result} = Runner.run(ds, "select generate_series(1, 2000) as n")
      assert length(result["rows"]) == Runner.row_cap()
      assert result["truncated"] == true
    end

    test "writes are refused by the read-only session" do
      %{user: user, ws: ws} = setup_ws()
      {:ok, ds} = DataSources.create(ws.id, "self", self_url(), user.id)

      assert {:error, msg} = Runner.run(ds, "CREATE TABLE pwned (id int)")
      assert msg =~ "read-only"
    end

    test "bad SQL and deleted sources are error states, not raises" do
      %{user: user, ws: ws} = setup_ws()
      {:ok, ds} = DataSources.create(ws.id, "self", self_url(), user.id)

      {:ok, doc} =
        Docs.create_doc(%{
          workspace_id: ws.id,
          owner_id: user.id,
          actor_user_id: user.id,
          actor_type: "agent",
          title: "Dash",
          blocks: [%{"type" => "chart", "source" => "self", "query" => "select nope from nowhere"}],
          intent: "test"
        })

      assert [%{"result" => %{"error" => msg}}] = Docs.enrich_blocks(doc.blocks, ws.id)
      assert msg =~ "nowhere"

      {:ok, _} = DataSources.delete(ds, user.id)

      assert [%{"result" => %{"error" => msg2}, "source" => %{"deleted" => true}}] =
               Docs.enrich_blocks(doc.blocks, ws.id)

      assert msg2 =~ "deleted"
    end
  end
end
