module Doc.Chart exposing
    ( Spec
    , caption
    , chartKey
    , encodeSpec
    , spec
    , sqlDialect
    , tablePrimary
    )

{-| Pure chart plumbing: validates a chart block's `result` echo against
its viz (port of `AvelineWeb.ChartRenderer`), builds the JSON spec the
`<aveline-chart>` custom element renders, and derives the run/dedup key

  - caption + SQL dialect the LiveView computed server-side.

-}

import Doc.Blocks as Blocks
    exposing
        ( Cell(..)
        , ChartBlock
        , RunResult
        , SeriesSpec
        , Source
        , Viz(..)
        )
import Json.Encode as Encode


type alias Spec =
    { result : RunResult
    , viz : Viz
    }


{-| A chart's run/dedup key: the named query it references (current), or
its inline {source, sql} (legacy historical charts). Charts sharing a
key share one run and never diverge.
-}
chartKey : ChartBlock -> Maybe String
chartKey block =
    case ( block.queryRef, ( block.dataSourceId, block.inlineQuery ) ) of
        ( Just ref, _ ) ->
            Just ("ref:" ++ ref)

        ( Nothing, ( Just baseId, Just sql ) ) ->
            Just ("inline:" ++ baseId ++ ":" ++ sql)

        _ ->
            Nothing


tablePrimary : ChartBlock -> Bool
tablePrimary block =
    block.viz == TableViz


{-| Returns Ok spec | Err message — every failure is a rendered state,
not a crash (port of `ChartRenderer.spec/2`).
-}
spec : RunResult -> Viz -> Result String Spec
spec result viz =
    case viz of
        XYViz xy ->
            specXY result viz xy.x [ xy.y ] "line/bar"

        ComboViz combo ->
            specXY result viz combo.x (List.map .y combo.series) "combo"

        _ ->
            Err "nothing to render"


specXY : RunResult -> Viz -> String -> List String -> String -> Result String Spec
specXY result viz x ys kindWord =
    let
        cols =
            result.columns

        missing =
            List.filter (\c -> not (List.member c cols)) (x :: ys)

        has =
            String.join ", " cols
    in
    if not (List.isEmpty missing) then
        case missing of
            [ one ] ->
                Err ("column \"" ++ one ++ "\" not in result (has: " ++ has ++ ")")

            many ->
                Err
                    ("columns "
                        ++ String.join ", " (List.map (\c -> "\"" ++ c ++ "\"") many)
                        ++ " not in result (has: "
                        ++ has
                        ++ ")"
                    )

    else if List.isEmpty result.rows then
        Err "query returned no rows"

    else
        case List.filter (\y -> not (numericSeries result y)) ys of
            [] ->
                Ok { result = result, viz = viz }

            badY :: _ ->
                Err ("column \"" ++ badY ++ "\" must be numeric for " ++ kindWord ++ " charts")


{-| A plottable numeric series: nulls allowed (gaps), every non-null
value numeric, at least one present.
-}
numericSeries : RunResult -> String -> Bool
numericSeries result y =
    case indexOf y result.columns of
        Nothing ->
            False

        Just yi ->
            let
                present =
                    result.rows
                        |> List.filterMap (\row -> List.head (List.drop yi row))
                        |> List.filter ((/=) CellNull)
            in
            not (List.isEmpty present) && List.all numericCell present


numericCell : Cell -> Bool
numericCell cell =
    case cell of
        CellNumber _ ->
            True

        CellString s ->
            String.toFloat s /= Nothing

        _ ->
            False


indexOf : a -> List a -> Maybe Int
indexOf needle list =
    list
        |> List.indexedMap Tuple.pair
        |> List.filterMap
            (\( i, v ) ->
                if v == needle then
                    Just i

                else
                    Nothing
            )
        |> List.head


{-| The JSON the `<aveline-chart>` element parses — same shape as the LV
Chart hook's `data-spec`: {columns, rows, viz, milestones}.
-}
encodeSpec : Spec -> List { a | name : String, date : String, description : Maybe String } -> Encode.Value
encodeSpec s milestones =
    Encode.object
        [ ( "columns", Encode.list Encode.string s.result.columns )
        , ( "rows", encodeRows s.result )
        , ( "viz", encodeViz s.viz )
        , ( "milestones"
          , Encode.list
                (\m ->
                    Encode.object
                        [ ( "name", Encode.string m.name )
                        , ( "date", Encode.string m.date )
                        , ( "description"
                          , m.description |> Maybe.map Encode.string |> Maybe.withDefault Encode.null
                          )
                        ]
                )
                milestones
          )
        ]


encodeRows : RunResult -> Encode.Value
encodeRows result =
    -- The raw server rows survive untouched (no lossy cell round-trip).
    result.rawRows


encodeViz : Viz -> Encode.Value
encodeViz viz =
    case viz of
        TableViz ->
            Encode.object [ ( "type", Encode.string "table" ) ]

        XYViz xy ->
            Encode.object
                [ ( "type", Encode.string xy.kind )
                , ( "x", Encode.string xy.x )
                , ( "y", Encode.string xy.y )
                ]

        ComboViz combo ->
            Encode.object
                [ ( "type", Encode.string "combo" )
                , ( "x", Encode.string combo.x )
                , ( "series", Encode.list encodeSeries combo.series )
                ]

        UnknownViz ->
            Encode.object []


encodeSeries : SeriesSpec -> Encode.Value
encodeSeries s =
    Encode.object
        (( "y", Encode.string s.y )
            :: ( "type", Encode.string s.seriesType )
            :: (case s.axis of
                    Just axis ->
                        [ ( "axis", Encode.string axis ) ]

                    Nothing ->
                        []
               )
        )


{-| Chart caption: "<where from> · <engine> · <query name>" (port of
`BlockRenderer.chart_caption/2`).
-}
caption : ChartBlock -> String
caption block =
    case ( block.queryRef, block.source ) of
        ( Just ref, Just source ) ->
            if source.adapter == Just "workspace" then
                "derived · duckdb · " ++ ref

            else
                case ( source.name, source.adapter ) of
                    ( Just name, Just adapter ) ->
                        name ++ " · " ++ adapter ++ " · " ++ ref

                    _ ->
                        "derived · duckdb · " ++ ref

        ( Just ref, Nothing ) ->
            "derived · duckdb · " ++ ref

        ( Nothing, Just source ) ->
            case ( source.name, source.adapter ) of
                ( Just name, Just adapter ) ->
                    name ++ " · " ++ adapter ++ " · inline"

                _ ->
                    ""

        _ ->
            ""


{-| sql-formatter dialect id from the source adapter echo (port of
`BlockRenderer.sql_dialect/1`).
-}
sqlDialect : Maybe Source -> String
sqlDialect source =
    case Maybe.andThen .adapter source of
        Just "postgres" ->
            "postgresql"

        Just "redshift" ->
            "redshift"

        Just "mysql" ->
            "mysql"

        Just "workspace" ->
            "postgresql"

        _ ->
            "sql"
