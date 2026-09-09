module DataSources.Overview exposing
    ( DocRef
    , Milestone
    , Overview
    , Query
    , Rollup
    , Source
    , decoder
    , dependentsIndex
    , dialectLabel
    , sourceRollup
    , timelinePositions
    , timelineStart
    , visibleQueries
    , wsBase
    )

{-| Data layer for the Data sources page: the wire shape of
GET /papi/workspaces/:slug/data-sources-overview (a one-shot bootstrap
mirroring DataSourcesLive.mount/3) and the pure index/filter logic
ported from that LV. Chart usage and derived-query lineage (`built_on`)
arrive precomputed from the server — deriving them needs doc blocks and
the analytics engine's SQL parser.
-}

import Dict exposing (Dict)
import Iso8601
import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Extra as DecodeExtra
import Time exposing (Posix)
import TimeFmt exposing (CivilDate)


type alias Overview =
    { sources : List Source
    , queries : List Query
    , milestones : List Milestone
    }


type alias Source =
    { baseId : String
    , name : String
    , adapter : String
    , url : String
    , deleted : Bool
    , createdBy : Maybe String
    , createdAt : Posix
    }


type alias Query =
    { name : String
    , description : Maybe String
    , kind : String
    , dataSourceId : Maybe String
    , sql : String
    , versionNumber : Int
    , createdBy : Maybe String
    , createdAt : Posix
    , chartCount : Int
    , chartedIn : List DocRef
    , builtOn : List String
    }


type alias DocRef =
    { slug : String
    , title : String
    }


type alias Milestone =
    { id : String
    , name : String
    , date : CivilDate
    , description : Maybe String
    }



-- ===== Decoders =====


decoder : Decoder Overview
decoder =
    Decode.map3 Overview
        (Decode.field "sources" (Decode.list sourceDecoder))
        (Decode.field "queries" (Decode.list queryDecoder))
        (Decode.field "milestones" (Decode.list milestoneDecoder))


sourceDecoder : Decoder Source
sourceDecoder =
    Decode.map7 Source
        (Decode.field "base_id" Decode.string)
        (Decode.field "name" Decode.string)
        (Decode.field "adapter" Decode.string)
        (Decode.field "url" Decode.string)
        (Decode.field "deleted" Decode.bool)
        (Decode.field "created_by" (Decode.nullable Decode.string))
        (Decode.field "created_at" Iso8601.decoder)


queryDecoder : Decoder Query
queryDecoder =
    Decode.succeed Query
        |> DecodeExtra.andMap (Decode.field "name" Decode.string)
        |> DecodeExtra.andMap (Decode.field "description" (Decode.nullable Decode.string))
        |> DecodeExtra.andMap (Decode.field "kind" Decode.string)
        |> DecodeExtra.andMap (Decode.field "data_source_id" (Decode.nullable Decode.string))
        |> DecodeExtra.andMap (Decode.field "sql" Decode.string)
        |> DecodeExtra.andMap (Decode.field "version_number" Decode.int)
        |> DecodeExtra.andMap (Decode.field "created_by" (Decode.nullable Decode.string))
        |> DecodeExtra.andMap (Decode.field "created_at" Iso8601.decoder)
        |> DecodeExtra.andMap (Decode.field "chart_count" Decode.int)
        |> DecodeExtra.andMap (Decode.field "charted_in" (Decode.list docRefDecoder))
        |> DecodeExtra.andMap (Decode.field "built_on" (Decode.list Decode.string))


docRefDecoder : Decoder DocRef
docRefDecoder =
    Decode.map2 DocRef
        (Decode.field "slug" Decode.string)
        (Decode.field "title" Decode.string)


milestoneDecoder : Decoder Milestone
milestoneDecoder =
    Decode.map4 Milestone
        (Decode.field "id" Decode.string)
        (Decode.field "name" Decode.string)
        (Decode.field "date" civilDateDecoder)
        (Decode.field "description" (Decode.nullable Decode.string))


civilDateDecoder : Decoder CivilDate
civilDateDecoder =
    Decode.string
        |> Decode.andThen
            (\raw ->
                case TimeFmt.parseCivilDate raw of
                    Just date ->
                        Decode.succeed date

                    Nothing ->
                        Decode.fail ("expected ISO date, got: " ++ raw)
            )



-- ===== Indexes (ported from DataSourcesLive) =====


{-| Base id of the built-in "workspace" source, if present.
-}
wsBase : List Source -> Maybe String
wsBase sources =
    sources
        |> List.filter (\s -> s.adapter == "workspace")
        |> List.head
        |> Maybe.map .baseId


{-| query name => derived query names referencing it (downstream —
what breaks if you change it). Inverted from `built_on`.
-}
dependentsIndex : List Query -> Dict String (List String)
dependentsIndex queries =
    List.foldl
        (\q acc ->
            List.foldl
                (\ref inner ->
                    Dict.update ref
                        (\existing ->
                            Just (List.sort (q.name :: Maybe.withDefault [] existing))
                        )
                        inner
                )
                acc
                q.builtOn
        )
        Dict.empty
        queries


type alias Rollup =
    { queries : Int
    , charts : Int
    }


{-| base source id => usage counts. Raw queries count against their
source; derived queries against the workspace catalog.
-}
sourceRollup : List Source -> List Query -> Dict String Rollup
sourceRollup sources queries =
    let
        ws =
            wsBase sources
    in
    List.foldl
        (\q acc ->
            case
                case q.dataSourceId of
                    Just id ->
                        Just id

                    Nothing ->
                        ws
            of
                Just key ->
                    Dict.update key
                        (\existing ->
                            let
                                e =
                                    Maybe.withDefault { queries = 0, charts = 0 } existing
                            in
                            Just { queries = e.queries + 1, charts = e.charts + q.chartCount }
                        )
                        acc

                Nothing ->
                    acc
        )
        Dict.empty
        queries


{-| Source-filter then text-filter — DataSourcesLive.visible\_queries/1.
-}
visibleQueries : { sourceFilter : Maybe String, wsBase_ : Maybe String, q : String } -> List Query -> List Query
visibleQueries { sourceFilter, wsBase_, q } queries =
    queries
        |> filterBySource sourceFilter wsBase_
        |> filterByText q


filterBySource : Maybe String -> Maybe String -> List Query -> List Query
filterBySource sourceFilter wsBase_ queries =
    case sourceFilter of
        Nothing ->
            queries

        Just base ->
            List.filter
                (\q ->
                    (case q.dataSourceId of
                        Just id ->
                            Just id

                        Nothing ->
                            wsBase_
                    )
                        == Just base
                )
                queries


filterByText : String -> List Query -> List Query
filterByText q queries =
    if q == "" then
        queries

    else
        let
            needle =
                String.toLower q

            matches query =
                String.contains needle (String.toLower query.name)
                    || String.contains needle (String.toLower (Maybe.withDefault "" query.description))
                    || String.contains needle (String.toLower query.sql)
        in
        List.filter matches queries



-- ===== Timeline strip =====


{-| Each milestone's horizontal position (percent) along a span from
the earliest milestone to today (or the latest future milestone),
padded so edge dots don't clip. Labels alternate rows 0/1.
-}
timelinePositions : CivilDate -> List Milestone -> List ( Milestone, Float, Int )
timelinePositions today milestones =
    case timelineStart milestones of
        Nothing ->
            []

        Just start ->
            let
                stop =
                    timelineStop today milestones

                span =
                    max (TimeFmt.diffDays stop start) 1
            in
            List.indexedMap
                (\i m ->
                    let
                        pct =
                            4.0 + toFloat (TimeFmt.diffDays m.date start) / toFloat span * 92.0
                    in
                    ( m, toFloat (round (pct * 100)) / 100, modBy 2 i )
                )
                milestones


{-| Earliest milestone date (milestones arrive date-ascending, but we
don't rely on it).
-}
timelineStart : List Milestone -> Maybe CivilDate
timelineStart milestones =
    milestones
        |> List.map .date
        |> minimumBy


timelineStop : CivilDate -> List Milestone -> CivilDate
timelineStop today milestones =
    case maximumBy (List.map .date milestones) of
        Just latest ->
            if TimeFmt.diffDays latest today > 0 then
                latest

            else
                today

        Nothing ->
            today


minimumBy : List CivilDate -> Maybe CivilDate
minimumBy dates =
    case dates of
        [] ->
            Nothing

        first :: rest ->
            Just
                (List.foldl
                    (\d best ->
                        if TimeFmt.diffDays d best < 0 then
                            d

                        else
                            best
                    )
                    first
                    rest
                )


maximumBy : List CivilDate -> Maybe CivilDate
maximumBy dates =
    case dates of
        [] ->
            Nothing

        first :: rest ->
            Just
                (List.foldl
                    (\d best ->
                        if TimeFmt.diffDays d best > 0 then
                            d

                        else
                            best
                    )
                    first
                    rest
                )


{-| DataSources.dialect\_label/1: the built-in source speaks duckdb.
-}
dialectLabel : String -> String
dialectLabel adapter =
    if adapter == "workspace" then
        "duckdb"

    else
        adapter
