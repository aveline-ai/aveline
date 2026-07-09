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

      {:ok, rs} =
        DataSources.create(ws.id, "rs", "redshift://u:<password>@c.redshift.amazonaws.com:5439/db", "x", user.id)

      assert rs.adapter == "redshift"

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
      Fixtures.query_fixture(ws, user, "ones", "select 1 as one", source: "self")

      {:ok, doc} =
        Docs.create_doc(%{
          workspace_id: ws.id,
          owner_id: user.id,
          actor_user_id: user.id,
          actor_type: "agent",
          title: "Dash",
          blocks: [Fixtures.chart_block("ones")],
          intent: "test"
        })

      {:ok, renamed} = DataSources.edit(ds, %{name: "analytics"}, user.id)
      assert renamed.name == "analytics"

      # The query pinned the source's base id — still resolves and runs.
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
      base = %{"type" => "chart", "query_ref" => "q"}

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

    test "spec validation: nulls are gaps, not non-numeric (forecast series)" do
      # `actual` is null past the real data; `forecast` spans all rows —
      # a valid combo, nulls render as gaps.
      result = %{
        "columns" => ["day", "actual", "forecast"],
        "rows" => [["2026-07-08", 1, -0.37], ["2026-07-09", nil, -4.31], ["2026-07-10", nil, -8.26]]
      }

      viz = %{
        "type" => "combo",
        "x" => "day",
        "series" => [%{"y" => "actual", "type" => "bar"}, %{"y" => "forecast", "type" => "line"}]
      }

      assert {:ok, _} = AvelineWeb.ChartRenderer.spec(result, viz)

      # An all-null column is still nothing to plot.
      all_null = %{result | "rows" => Enum.map(result["rows"], fn [d, _a, f] -> [d, nil, f] end)}
      assert {:error, msg} = AvelineWeb.ChartRenderer.spec(all_null, viz)
      assert msg =~ "actual"
    end
  end

  describe "chart block validation" do
    test "valid chart normalizes; echoes stripped" do
      assert {:ok, out} =
               Block.validate(
                 %{
                   "type" => "chart",
                   "query_ref" => "docs_per_day",
                   "viz" => %{"type" => "line", "x" => "a", "y" => "b", "junk" => true},
                   "result" => %{"rows" => [["stale"]]},
                   "source" => %{"name" => "forged"},
                   "query_sql" => "select stale"
                 },
                 mint_id?: true
               )

      assert out["query_ref"] == "docs_per_day"
      assert out["viz"] == %{"type" => "line", "x" => "a", "y" => "b"}
      refute Map.has_key?(out, "result")
      refute Map.has_key?(out, "source")
      refute Map.has_key?(out, "query_sql")
    end

    test "query_ref is required and must be a query name; inline SQL is rejected" do
      assert {:error, msg} =
               Block.validate(%{"type" => "chart", "data_source_id" => Ecto.UUID.generate(), "query" => "select 1"}, mint_id?: true)

      assert msg =~ "query_ref"

      assert {:error, msg} =
               Block.validate(%{"type" => "chart", "query_ref" => "Bad Name"}, mint_id?: true)

      assert msg =~ "query_ref"
    end

    test "viz validation" do
      base = %{"type" => "chart", "query_ref" => "q"}

      assert {:ok, out} = Block.validate(base, mint_id?: true)
      assert out["viz"] == %{"type" => "table"}

      assert {:error, msg} = Block.validate(Map.put(base, "viz", %{"type" => "pie"}), mint_id?: true)
      assert msg =~ "viz.type"

      assert {:error, msg} = Block.validate(Map.put(base, "viz", %{"type" => "line"}), mint_id?: true)
      assert msg =~ "needs x and y"
    end
  end

  describe "resolution" do
    test "query_ref resolves; unknown query rejected at write time" do
      %{user: user, ws: ws} = setup_ws()
      create_self!(ws, user)
      Fixtures.query_fixture(ws, user, "ones", "select 1 as one", source: "self")

      {:ok, doc} =
        Docs.create_doc(%{
          workspace_id: ws.id,
          owner_id: user.id,
          actor_user_id: user.id,
          actor_type: "agent",
          title: "Dash",
          blocks: [Fixtures.chart_block("ones")],
          intent: "test"
        })

      assert [%{"query_ref" => "ones"}] = doc.blocks

      assert {:error, :query_not_found, _} =
               Docs.create_doc(%{
                 workspace_id: ws.id,
                 owner_id: user.id,
                 actor_user_id: user.id,
                 actor_type: "agent",
                 title: "Bad",
                 blocks: [Fixtures.chart_block("ghost_query")],
                 intent: "test"
               })
    end
  end

  describe "runner + enrichment" do
    test "runs a real query and echoes columns/rows + source + sql" do
      %{user: user, ws: ws} = setup_ws()
      create_self!(ws, user)
      Fixtures.query_fixture(ws, user, "series", "select generate_series(1, 3) as n", source: "self")

      {:ok, doc} =
        Docs.create_doc(%{
          workspace_id: ws.id,
          owner_id: user.id,
          actor_user_id: user.id,
          actor_type: "agent",
          title: "Dash",
          blocks: [Fixtures.chart_block("series")],
          intent: "test"
        })

      assert [%{"result" => result, "source" => source, "query_sql" => sql}] =
               Docs.enrich_blocks(doc.blocks, ws.id)

      assert result["columns"] == ["n"]
      assert result["rows"] == [[1], [2], [3]]
      assert source["credential"] == "live"
      assert sql =~ "generate_series"
    end

    test "row cap truncates and flags" do
      %{user: user, ws: ws} = setup_ws()
      ds = create_self!(ws, user)

      assert {:ok, result} = Runner.run(ds, "select generate_series(1, 2000) as n")
      assert length(result["rows"]) == Runner.row_cap()
      assert result["truncated"] == true
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

      Fixtures.query_fixture(ws, user, "dead", "select 1", source: "ghost")

      {:ok, doc} =
        Docs.create_doc(%{
          workspace_id: ws.id,
          owner_id: user.id,
          actor_user_id: user.id,
          actor_type: "agent",
          title: "Dead host dash",
          blocks: [Fixtures.chart_block("dead")],
          intent: "test"
        })

      # The whole point: enrichment survives, doc renders, error on the block.
      assert [%{"result" => %{"error" => msg2}}] = Docs.enrich_blocks(doc.blocks, ws.id)
      assert msg2 =~ "connection failed" or msg2 =~ "timed out"
      assert ghost.adapter == "postgres"
    end

    test "bad SQL is an error state, not a raise" do
      %{user: user, ws: ws} = setup_ws()
      create_self!(ws, user)
      Fixtures.query_fixture(ws, user, "broken", "select nope from nowhere", source: "self")

      {:ok, doc} =
        Docs.create_doc(%{
          workspace_id: ws.id,
          owner_id: user.id,
          actor_user_id: user.id,
          actor_type: "agent",
          title: "Dash",
          blocks: [Fixtures.chart_block("broken")],
          intent: "test"
        })

      assert [%{"result" => %{"error" => msg}}] = Docs.enrich_blocks(doc.blocks, ws.id)
      assert msg =~ "nowhere"
    end
  end
end
