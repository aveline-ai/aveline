module DataSourcesOverviewTest exposing (suite)

{-| Decoder and index/filter coverage for the Data sources page
(DataSources.Overview), matching the wire shape of
GET /papi/workspaces/:slug/data-sources-overview.
-}

import DataSources.Overview as Overview
import Dict
import Expect
import Json.Decode as Decode
import Test exposing (Test, describe, test)
import Time


payload : String
payload =
    """
    {
      "ok": true,
      "sources": [
        {"base_id": "b-ws", "name": "derived", "adapter": "workspace",
         "url": "aveline://derived", "deleted": false,
         "created_by": null, "created_at": "2026-01-05T09:00:00Z"},
        {"base_id": "b-prod", "name": "prod", "adapter": "postgres",
         "url": "postgres://ro:<password>@db:5432/app", "deleted": false,
         "created_by": "arie", "created_at": "2026-02-01T09:00:00Z"},
        {"base_id": "b-old", "name": "legacy", "adapter": "mysql",
         "url": "mysql://x:<password>@old/db", "deleted": true,
         "created_by": "sam", "created_at": "2025-11-20T09:00:00Z"}
      ],
      "queries": [
        {"name": "signups", "description": "Daily signups.", "kind": "raw",
         "data_source_id": "b-prod", "sql": "select 1", "version_number": 3,
         "created_by": "arie", "created_at": "2026-02-02T10:00:00Z",
         "chart_count": 2, "charted_in": [{"slug": "kpis", "title": "KPIs"}],
         "built_on": []},
        {"name": "signups_weekly", "description": null, "kind": "derived",
         "data_source_id": null, "sql": "select * from signups", "version_number": 1,
         "created_by": null, "created_at": "2026-02-03T10:00:00Z",
         "chart_count": 0, "charted_in": [], "built_on": ["signups"]}
      ],
      "milestones": [
        {"id": "m-1", "name": "v1 shipped", "date": "2026-03-01", "description": "GA"},
        {"id": "m-2", "name": "pricing", "date": "2026-06-01", "description": null}
      ]
    }
    """


decoded : Result Decode.Error Overview.Overview
decoded =
    Decode.decodeString Overview.decoder payload


withDecoded : (Overview.Overview -> Expect.Expectation) -> Expect.Expectation
withDecoded check =
    case decoded of
        Ok overview ->
            check overview

        Err err ->
            Expect.fail (Decode.errorToString err)


suite : Test
suite =
    describe "DataSources.Overview"
        [ describe "decoder"
            [ test "decodes sources, incl. the soft-deleted one" <|
                \_ ->
                    withDecoded
                        (\o ->
                            List.map (\s -> ( s.baseId, s.deleted, s.createdBy )) o.sources
                                |> Expect.equal
                                    [ ( "b-ws", False, Nothing )
                                    , ( "b-prod", False, Just "arie" )
                                    , ( "b-old", True, Just "sam" )
                                    ]
                        )
            , test "decodes query usage, lineage, and timestamps" <|
                \_ ->
                    withDecoded
                        (\o ->
                            List.map
                                (\q -> ( q.name, ( q.chartCount, q.builtOn ), ( q.dataSourceId, q.createdAt ) ))
                                o.queries
                                |> Expect.equal
                                    [ ( "signups"
                                      , ( 2, [] )
                                      , ( Just "b-prod", Time.millisToPosix 1770026400000 )
                                      )
                                    , ( "signups_weekly"
                                      , ( 0, [ "signups" ] )
                                      , ( Nothing, Time.millisToPosix 1770112800000 )
                                      )
                                    ]
                        )
            , test "decodes milestone calendar dates" <|
                \_ ->
                    withDecoded
                        (\o ->
                            List.map (\m -> ( m.name, m.date, m.description )) o.milestones
                                |> Expect.equal
                                    [ ( "v1 shipped", { year = 2026, month = 3, day = 1 }, Just "GA" )
                                    , ( "pricing", { year = 2026, month = 6, day = 1 }, Nothing )
                                    ]
                        )
            , test "rejects a malformed milestone date" <|
                \_ ->
                    Decode.decodeString Overview.decoder
                        """{"sources": [], "queries": [], "milestones": [{"id": "m", "name": "x", "date": "soon", "description": null}]}"""
                        |> Result.mapError (\_ -> "failed")
                        |> Expect.equal (Err "failed")
            ]
        , describe "indexes"
            [ test "wsBase finds the built-in source" <|
                \_ ->
                    withDecoded (\o -> Overview.wsBase o.sources |> Expect.equal (Just "b-ws"))
            , test "dependentsIndex inverts built_on" <|
                \_ ->
                    withDecoded
                        (\o ->
                            Overview.dependentsIndex o.queries
                                |> Dict.toList
                                |> Expect.equal [ ( "signups", [ "signups_weekly" ] ) ]
                        )
            , test "sourceRollup counts raw against its source, derived against the workspace" <|
                \_ ->
                    withDecoded
                        (\o ->
                            Overview.sourceRollup o.sources o.queries
                                |> Dict.toList
                                |> Expect.equal
                                    [ ( "b-prod", { queries = 1, charts = 2 } )
                                    , ( "b-ws", { queries = 1, charts = 0 } )
                                    ]
                        )
            ]
        , describe "visibleQueries"
            [ test "no filters shows everything" <|
                \_ ->
                    withDecoded
                        (\o ->
                            Overview.visibleQueries
                                { sourceFilter = Nothing, wsBase_ = Just "b-ws", q = "" }
                                o.queries
                                |> List.map .name
                                |> Expect.equal [ "signups", "signups_weekly" ]
                        )
            , test "the workspace filter catches derived queries" <|
                \_ ->
                    withDecoded
                        (\o ->
                            Overview.visibleQueries
                                { sourceFilter = Just "b-ws", wsBase_ = Just "b-ws", q = "" }
                                o.queries
                                |> List.map .name
                                |> Expect.equal [ "signups_weekly" ]
                        )
            , test "text search matches name, description, or SQL, case-insensitively" <|
                \_ ->
                    withDecoded
                        (\o ->
                            ( Overview.visibleQueries
                                { sourceFilter = Nothing, wsBase_ = Just "b-ws", q = "DAILY" }
                                o.queries
                                |> List.map .name
                            , Overview.visibleQueries
                                { sourceFilter = Nothing, wsBase_ = Just "b-ws", q = "from signups" }
                                o.queries
                                |> List.map .name
                            )
                                |> Expect.equal ( [ "signups" ], [ "signups_weekly" ] )
                        )
            , test "source filter and search compose" <|
                \_ ->
                    withDecoded
                        (\o ->
                            Overview.visibleQueries
                                { sourceFilter = Just "b-prod", wsBase_ = Just "b-ws", q = "weekly" }
                                o.queries
                                |> Expect.equal []
                        )
            ]
        , describe "timeline"
            [ test "positions span earliest milestone to today, labels alternating rows" <|
                \_ ->
                    withDecoded
                        (\o ->
                            let
                                today =
                                    { year = 2026, month = 9, day = 8 }
                            in
                            Overview.timelinePositions today o.milestones
                                |> List.map (\( m, pct, row ) -> ( m.id, pct, row ))
                                |> Expect.equal
                                    -- span: Mar 1 → Sep 8 = 191 days; Jun 1 is day 92.
                                    [ ( "m-1", 4.0, 0 )
                                    , ( "m-2", 4.0 + 92.0 / 191.0 * 92.0 |> roundTo2, 1 )
                                    ]
                        )
            , test "a future milestone extends the span past today" <|
                \_ ->
                    let
                        milestones =
                            [ { id = "a", name = "a", date = { year = 2026, month = 1, day = 1 }, description = Nothing }
                            , { id = "b", name = "b", date = { year = 2027, month = 1, day = 1 }, description = Nothing }
                            ]
                    in
                    Overview.timelinePositions { year = 2026, month = 9, day = 8 } milestones
                        |> List.map (\( _, pct, _ ) -> pct)
                        |> Expect.equal [ 4.0, 96.0 ]
            , test "a single milestone today collapses to the minimum 1-day span" <|
                \_ ->
                    let
                        m =
                            { id = "a", name = "a", date = { year = 2026, month = 9, day = 8 }, description = Nothing }
                    in
                    Overview.timelinePositions { year = 2026, month = 9, day = 8 } [ m ]
                        |> Expect.equal [ ( m, 4.0, 0 ) ]
            ]
        ]


roundTo2 : Float -> Float
roundTo2 x =
    toFloat (round (x * 100)) / 100
