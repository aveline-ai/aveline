defmodule Aveline.DataSourcesTest do
  use Aveline.DataCase, async: false

  alias Aveline.Blocks.Block
  alias Aveline.DataSources
  alias Aveline.DataSources.Runner
  alias Aveline.Docs
  alias Aveline.Fixtures

  # The test database itself — the runner opens a real second
  # connection, so queries must not depend on sandboxed rows.
  defp self_template do
    "postgres://#{System.get_env("PGUSER") || "postgres"}:<password>@#{System.get_env("PGHOST") || "localhost"}/aveline_test#{System.get_env("MIX_TEST_PARTITION")}"
  end

  defp self_password, do: System.get_env("PGPASSWORD") || "postgres"

  defp setup_ws do
    user = Fixtures.user_fixture()
    ws = Fixtures.workspace_fixture(user)
    %{user: user, ws: ws}
  end

  defp create_self!(ws, user, name \\ "self") do
    {:ok, ds} = DataSources.create(ws.id, name, self_template(), self_password(), user.id)
    ds
  end

  describe "create + template validation" do
    test "adapter derives from the template scheme" do
      %{user: user, ws: ws} = setup_ws()

      {:ok, pg} = DataSources.create(ws.id, "pg", "postgres://u:<password>@h/db", "x", user.id)
      assert pg.adapter == "postgres"

      {:ok, my} = DataSources.create(ws.id, "my", "mysql://u:<password>@h:3306/db", "x", user.id)
      assert my.adapter == "mysql"

      assert {:error, :invalid_data_source_url, msg} =
               DataSources.create(ws.id, "bad", "http://u:<password>@h/db", "x", user.id)

      assert msg =~ "unsupported scheme"
    end

    test "template must carry the placeholder exactly once" do
      %{user: user, ws: ws} = setup_ws()

      assert {:error, :invalid_data_source_url, msg} =
               DataSources.create(ws.id, "none", "postgres://u:realpass@h/db", "x", user.id)

      assert msg =~ "<password>"

      assert {:error, :invalid_data_source_url, _} =
               DataSources.create(
                 ws.id,
                 "twice",
                 "postgres://<password>:<password>@h/db",
                 "x",
                 user.id
               )
    end

    test "the password is encrypted at rest; the template is plain and echoed" do
      %{user: user, ws: ws} = setup_ws()
      template = "postgres://metrics_ro:<password>@db.example.com:5432/prod"
      {:ok, ds} = DataSources.create(ws.id, "prod", template, "hunter2-secret", user.id)

      %{rows: [[raw_template, raw_password]]} =
        Repo.query!("SELECT url_template, password_encrypted FROM data_sources WHERE id = $1", [
          Ecto.UUID.dump!(ds.id)
        ])

      # Template stored verbatim (no secret in it); password only as ciphertext.
      assert raw_template == template
      refute raw_password == nil
      refute raw_password =~ "hunter2-secret"

      safe = DataSources.safe_map(ds)
      assert safe["url"] == template
      assert safe["credential"] == "live"
      refute Map.has_key?(safe, "password")
    end
  end

  describe "dial_url/1" do
    test "substitutes the URL-encoded password" do
      %{user: user, ws: ws} = setup_ws()

      {:ok, ds} =
        DataSources.create(
          ws.id,
          "enc",
          "postgres://u:<password>@h:5432/db?sslmode=require",
          "p@ss w/slash",
          user.id
        )

      assert DataSources.dial_url(ds) ==
               "postgres://u:p%40ss+w%2Fslash@h:5432/db?sslmode=require"
    end
  end

  describe "TLS option mapping" do
    alias Aveline.DataSources.TLS

    test "query params become driver ssl options and are stripped from the url" do
      # No params: plaintext, url unchanged.
      assert {"postgres://u:p@h:5432/db", nil} = TLS.split("postgres://u:p@h:5432/db")

      # require: encrypt without verification.
      assert {"postgres://u:p@h:5432/db", [verify: :verify_none]} =
               TLS.split("postgres://u:p@h:5432/db?sslmode=require")

      # generic ssl=true / mysql ssl-mode.
      assert {_, [verify: :verify_none]} = TLS.split("mysql://u:p@h/db?ssl=true")
      assert {_, [verify: :verify_none]} = TLS.split("mysql://u:p@h/db?ssl-mode=REQUIRED")

      # verify-full: real verification against system roots + hostname check.
      assert {_, opts} = TLS.split("postgres://u:p@db.example.com/db?sslmode=verify-full")
      assert opts[:verify] == :verify_peer
      assert opts[:server_name_indication] == ~c"db.example.com"
      assert is_list(opts[:cacerts]) and opts[:cacerts] != []

      # disable and explicit false: plaintext.
      assert {_, nil} = TLS.split("postgres://u:p@h/db?sslmode=disable")
      assert {_, nil} = TLS.split("mysql://u:p@h/db?ssl=false")

      # Unknown params never leak toward the driver.
      assert {"postgres://u:p@h/db", nil} = TLS.split("postgres://u:p@h/db?application_name=x")
    end

    test "dial still works end to end with an explicit sslmode=disable" do
      %{user: user, ws: ws} = setup_ws()

      {:ok, ds} =
        DataSources.create(
          ws.id,
          "nossl",
          self_template() <> "?sslmode=disable",
          self_password(),
          user.id
        )

      assert {:ok, %{"rows" => [[1]]}} = Runner.run(ds, "select 1")
    end
  end

  describe "edit" do
    test "password-only rotation mints a version and scrubs the old secret" do
      %{user: user, ws: ws} = setup_ws()
      ds = create_self!(ws, user)

      {:ok, v2} = DataSources.edit(ds, %{password: self_password()}, user.id)
      assert v2.version_number == 2
      assert v2.base_data_source_id == ds.base_data_source_id
      assert v2.url_template == ds.url_template

      # Old row: superseded, secret destroyed. Template intact for audit.
      %{rows: [[superseded, raw_password, raw_template]]} =
        Repo.query!(
          "SELECT superseded, password_encrypted, url_template FROM data_sources WHERE id = $1",
          [Ecto.UUID.dump!(ds.id)]
        )

      assert superseded == true
      assert raw_password == nil
      assert raw_template == ds.url_template

      # Still dials fine on the new version.
      assert {:ok, %{"rows" => [[1]]}} = Runner.run(v2, "select 1")
    end

    test "rename alone is fine and never breaks chart blocks" do
      %{user: user, ws: ws} = setup_ws()
      ds = create_self!(ws, user)

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

      {:ok, renamed} = DataSources.edit(ds, %{name: "analytics"}, user.id)
      assert renamed.name == "analytics"

      # The block pinned the base id — still resolves and runs.
      assert [%{"result" => %{"rows" => [[1]]}, "source" => %{"name" => "analytics"}}] =
               Docs.enrich_blocks(doc.blocks, ws.id)
    end

    test "template change without the password is refused" do
      %{user: user, ws: ws} = setup_ws()
      ds = create_self!(ws, user)

      assert {:error, :password_required, msg} =
               DataSources.edit(
                 ds,
                 %{url: "postgres://u:<password>@evil.example.com/db"},
                 user.id
               )

      assert msg =~ "requires supplying the password"

      # With the password it goes through (destination + secret written together).
      assert {:ok, v2} =
               DataSources.edit(
                 ds,
                 %{url: self_template(), password: self_password()},
                 user.id
               )

      assert v2.version_number == 2
    end
  end

  describe "chart spec validation (renderer contract)" do
    test "valid result + viz produce the hook spec" do
      result = %{"columns" => ["day", "n"], "rows" => [["2026-07-04", 1], ["2026-07-05", 3]]}
      viz = %{"type" => "line", "x" => "day", "y" => "n"}

      assert {:ok, spec} = AvelineWeb.ChartRenderer.spec(result, viz)
      assert spec["viz"] == viz
      assert spec["rows"] == result["rows"]
    end

    test "unknown columns, non-numeric y, empty rows, and query errors are states" do
      viz = %{"type" => "bar", "x" => "day", "y" => "n"}

      assert {:error, msg} =
               AvelineWeb.ChartRenderer.spec(%{"columns" => ["other"], "rows" => [[1]]}, viz)

      assert msg =~ "not in result"

      assert {:error, msg2} =
               AvelineWeb.ChartRenderer.spec(
                 %{"columns" => ["day", "n"], "rows" => [["mon", "not-a-number"]]},
                 viz
               )

      assert msg2 =~ "numeric"

      assert {:error, "query returned no rows"} =
               AvelineWeb.ChartRenderer.spec(%{"columns" => ["day", "n"], "rows" => []}, viz)

      assert {:error, "boom"} = AvelineWeb.ChartRenderer.spec(%{"error" => "boom"}, viz)
    end
  end

  describe "combo viz" do
    test "block validation: series shape, unknown keys stripped" do
      uuid = Ecto.UUID.generate()
      base = %{"type" => "chart", "data_source_id" => uuid, "query" => "select 1"}

      viz = %{
        "type" => "combo",
        "x" => "day",
        "series" => [
          %{"y" => "signups", "type" => "bar", "junk" => 1},
          %{"y" => "total", "type" => "line", "axis" => "right"}
        ]
      }

      assert {:ok, out} = Block.validate(Map.put(base, "viz", viz), mint_id?: true)

      assert out["viz"] == %{
               "type" => "combo",
               "x" => "day",
               "series" => [
                 %{"y" => "signups", "type" => "bar"},
                 %{"y" => "total", "type" => "line", "axis" => "right"}
               ]
             }

      # Bad shapes rejected.
      for bad <- [
            %{"type" => "combo", "x" => "day"},
            %{"type" => "combo", "x" => "day", "series" => []},
            %{"type" => "combo", "x" => "day", "series" => [%{"y" => "a", "type" => "pie"}]},
            %{"type" => "combo", "x" => "day", "series" => [%{"y" => "a", "type" => "bar", "axis" => "top"}]}
          ] do
        assert {:error, msg} = Block.validate(Map.put(base, "viz", bad), mint_id?: true)
        assert msg =~ "combo"
      end
    end

    test "spec validation: all series columns must exist and be numeric" do
      result = %{"columns" => ["day", "signups", "total"], "rows" => [["2026-07-04", 1, 5]]}

      viz = %{
        "type" => "combo",
        "x" => "day",
        "series" => [
          %{"y" => "signups", "type" => "bar"},
          %{"y" => "total", "type" => "line", "axis" => "right"}
        ]
      }

      assert {:ok, spec} = AvelineWeb.ChartRenderer.spec(result, viz)
      assert spec["viz"] == viz

      bad_col = put_in(viz, ["series", Access.at(1), "y"], "ghost")
      assert {:error, msg} = AvelineWeb.ChartRenderer.spec(result, bad_col)
      assert msg =~ "ghost"

      bad_rows = %{result | "rows" => [["2026-07-04", 1, "not-a-number"]]}
      assert {:error, msg2} = AvelineWeb.ChartRenderer.spec(bad_rows, viz)
      assert msg2 =~ "numeric"
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

      assert {:ok, out} = Block.validate(base, mint_id?: true)
      assert out["viz"] == %{"type" => "table"}

      assert {:error, msg} =
               Block.validate(Map.put(base, "viz", %{"type" => "pie"}), mint_id?: true)

      assert msg =~ "viz.type"

      assert {:error, msg} =
               Block.validate(Map.put(base, "viz", %{"type" => "line"}), mint_id?: true)

      assert msg =~ "needs x and y"
    end
  end

  describe "resolution" do
    test "source name resolves to the base id; unknown and cross-workspace rejected" do
      %{user: user, ws: ws} = setup_ws()
      ds = create_self!(ws, user)

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

      assert [%{"data_source_id" => id}] = doc.blocks
      assert id == ds.base_data_source_id

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

      other = Fixtures.workspace_fixture(user)

      assert {:error, :data_source_not_found, _} =
               Docs.create_doc(%{
                 workspace_id: other.id,
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
      create_self!(ws, user)

      {:ok, doc} =
        Docs.create_doc(%{
          workspace_id: ws.id,
          owner_id: user.id,
          actor_user_id: user.id,
          actor_type: "agent",
          title: "Dash",
          blocks: [
            %{"type" => "chart", "source" => "self", "query" => "select generate_series(1, 3) as n"}
          ],
          intent: "test"
        })

      assert [%{"result" => result, "source" => source}] = Docs.enrich_blocks(doc.blocks, ws.id)
      assert result["columns"] == ["n"]
      assert result["rows"] == [[1], [2], [3]]
      assert source["credential"] == "live"
      assert source["url"] =~ "<password>"
    end

    test "row cap truncates and flags; writes are refused" do
      %{user: user, ws: ws} = setup_ws()
      ds = create_self!(ws, user)

      assert {:ok, result} = Runner.run(ds, "select generate_series(1, 2000) as n")
      assert length(result["rows"]) == Runner.row_cap()
      assert result["truncated"] == true

      assert {:error, msg} = Runner.run(ds, "CREATE TABLE pwned (id int)")
      assert msg =~ "read-only"
    end

    test "unreachable hosts are error states, not raises (the prod regression)" do
      %{user: user, ws: ws} = setup_ws()

      # Closed port: connection refused fast.
      {:ok, refused} =
        DataSources.create(ws.id, "refused", "postgres://u:<password>@localhost:1/db", "x", user.id)

      assert {:error, msg} = Runner.run(refused, "select 1")
      assert msg =~ "connection failed" or msg =~ "timed out"

      # Nonexistent domain: nxdomain (what happened in prod).
      {:ok, ghost} =
        DataSources.create(
          ws.id,
          "ghost",
          "postgres://u:<password>@does-not-exist.invalid:5432/db",
          "x",
          user.id
        )

      {:ok, doc} =
        Docs.create_doc(%{
          workspace_id: ws.id,
          owner_id: user.id,
          actor_user_id: user.id,
          actor_type: "agent",
          title: "Dead host dash",
          blocks: [%{"type" => "chart", "source" => "ghost", "query" => "select 1"}],
          intent: "test"
        })

      # The whole point: enrichment survives, doc renders, error on the block.
      assert [%{"result" => %{"error" => msg2}}] = Docs.enrich_blocks(doc.blocks, ws.id)
      assert msg2 =~ "connection failed" or msg2 =~ "timed out"
      assert ghost.adapter == "postgres"
    end

    test "bad SQL and deleted sources are error states, not raises" do
      %{user: user, ws: ws} = setup_ws()
      ds = create_self!(ws, user)

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

      assert [%{"result" => %{"error" => msg2}, "source" => source}] =
               Docs.enrich_blocks(doc.blocks, ws.id)

      assert msg2 =~ "deleted"
      assert source["deleted"] == true
      assert source["credential"] == "redacted"
      # The template survives the scrub — audit still shows where it pointed.
      assert source["url"] =~ "<password>"
    end
  end
end
