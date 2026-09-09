module ChartTest exposing (suite)

{-| Port-parity checks for `Doc.Chart.spec` against
`AvelineWeb.ChartRenderer` — every failure is a rendered state.
-}

import Doc.Blocks as Blocks exposing (Cell(..), ChartBlock, ChartResult(..), Viz(..))
import Doc.Chart as Chart
import Expect
import Json.Encode as Encode
import Test exposing (Test, describe, test)


result : List String -> List (List Cell) -> Blocks.RunResult
result columns rows =
    { columns = columns
    , rows = rows
    , truncated = False
    , truncatedInputs = []
    , rawRows = Encode.list identity []
    }


barViz : Viz
barViz =
    XYViz { kind = "bar", x = "day", y = "signups" }


chartBlock : ChartBlock
chartBlock =
    { id = Just "b_c"
    , queryRef = Nothing
    , dataSourceId = Nothing
    , inlineQuery = Nothing
    , querySql = Nothing
    , viz = TableViz
    , source = Nothing
    , result = Pending
    }


suite : Test
suite =
    describe "Doc.Chart"
        [ describe "spec"
            [ test "valid line/bar spec passes" <|
                \_ ->
                    Chart.spec (result [ "day", "signups" ] [ [ CellString "2026-01-01", CellNumber 3 ] ]) barViz
                        |> Result.map (always ())
                        |> Expect.equal (Ok ())
            , test "missing x column errors" <|
                \_ ->
                    Chart.spec (result [ "d", "signups" ] [ [ CellString "x", CellNumber 1 ] ]) barViz
                        |> Expect.equal (Err "column \"day\" not in result (has: d, signups)")
            , test "empty rows error" <|
                \_ ->
                    Chart.spec (result [ "day", "signups" ] []) barViz
                        |> Expect.equal (Err "query returned no rows")
            , test "non-numeric y errors" <|
                \_ ->
                    Chart.spec (result [ "day", "signups" ] [ [ CellString "a", CellString "many" ] ]) barViz
                        |> Expect.equal (Err "column \"signups\" must be numeric for line/bar charts")
            , test "numeric strings count as numeric" <|
                \_ ->
                    Chart.spec (result [ "day", "signups" ] [ [ CellString "a", CellString "3.5" ] ]) barViz
                        |> Result.map (always ())
                        |> Expect.equal (Ok ())
            , test "nulls are gaps but an all-null column is unplottable" <|
                \_ ->
                    Expect.all
                        [ \_ ->
                            Chart.spec
                                (result [ "day", "signups" ]
                                    [ [ CellString "a", CellNull ], [ CellString "b", CellNumber 1 ] ]
                                )
                                barViz
                                |> Result.map (always ())
                                |> Expect.equal (Ok ())
                        , \_ ->
                            Chart.spec (result [ "day", "signups" ] [ [ CellString "a", CellNull ] ]) barViz
                                |> Expect.equal (Err "column \"signups\" must be numeric for line/bar charts")
                        ]
                        ()
            , test "combo validates every series column" <|
                \_ ->
                    Chart.spec (result [ "day", "a" ] [ [ CellString "x", CellNumber 1 ] ])
                        (ComboViz
                            { x = "day"
                            , series =
                                [ { y = "a", seriesType = "bar", axis = Nothing }
                                , { y = "missing", seriesType = "line", axis = Just "right" }
                                ]
                            }
                        )
                        |> Expect.equal (Err "column \"missing\" not in result (has: day, a)")
            , test "table viz renders nothing here" <|
                \_ ->
                    Chart.spec (result [ "a" ] [ [ CellNumber 1 ] ]) TableViz
                        |> Expect.equal (Err "nothing to render")
            ]
        , describe "chartKey"
            [ test "query_ref charts key on the ref" <|
                \_ ->
                    Chart.chartKey { chartBlock | queryRef = Just "daily_growth" }
                        |> Expect.equal (Just "ref:daily_growth")
            , test "legacy inline charts key on source + sql" <|
                \_ ->
                    Chart.chartKey { chartBlock | dataSourceId = Just "ds1", inlineQuery = Just "select 1" }
                        |> Expect.equal (Just "inline:ds1:select 1")
            , test "keyless charts have no run" <|
                \_ ->
                    Chart.chartKey chartBlock |> Expect.equal Nothing
            ]
        , describe "captions and dialects"
            [ test "raw query caption" <|
                \_ ->
                    Chart.caption
                        { chartBlock
                            | queryRef = Just "growth"
                            , source = Just { name = Just "prod", adapter = Just "postgres" }
                        }
                        |> Expect.equal "prod · postgres · growth"
            , test "derived query caption" <|
                \_ ->
                    Chart.caption
                        { chartBlock
                            | queryRef = Just "growth"
                            , source = Just { name = Just "workspace", adapter = Just "workspace" }
                        }
                        |> Expect.equal "derived · duckdb · growth"
            , test "legacy inline caption" <|
                \_ ->
                    Chart.caption
                        { chartBlock | source = Just { name = Just "prod", adapter = Just "mysql" } }
                        |> Expect.equal "prod · mysql · inline"
            , test "sql dialects" <|
                \_ ->
                    List.map (\a -> Chart.sqlDialect (Just { name = Nothing, adapter = Just a }))
                        [ "postgres", "redshift", "mysql", "workspace", "sqlite" ]
                        |> Expect.equal [ "postgresql", "redshift", "mysql", "postgresql", "sql" ]
            ]
        ]
