module Page.DataSources exposing (Model, Msg, init, update, view)

{-| The workspace's data layer on one page, ported from
lib/aveline\_web/live/data\_sources\_live.ex: source cards (incl.
soft-deleted, dimmed), the milestone timeline strip, and the query
catalog with source filter, text search, and a per-query modal showing
description, SQL, and the dependency graph (built on / feeds /
charted in) whose chips jump query to query.

Bootstrapped in one roundtrip from GET /data-sources-overview. Main
content region only; the coordinator adds the sidebar chrome.

Deliberate deltas from the LV (see port report): SQL in the modal is
shown unformatted (the sql-formatter hook lives in LV-owned JS), the
open query is page state rather than a ?query= URL param, and Escape
doesn't close the modal (pages have no subscriptions yet).

-}

import Api
import DataSources.Overview as Overview exposing (Milestone, Overview, Query, Source)
import Dict exposing (Dict)
import Html exposing (Html, button, code, div, h1, li, p, pre, span, strong, text)
import Html.Attributes exposing (attribute, autocomplete, class, classList, href, id, name, placeholder, style, title, type_, value)
import Html.Events exposing (onClick, onInput, preventDefaultOn, stopPropagationOn)
import Json.Decode as Decode
import Session exposing (Session)
import Svg
import Svg.Attributes as SvgAttr
import Task
import Time exposing (Posix)
import TimeFmt exposing (CivilDate)
import Url.Builder


type alias Model =
    { session : Session
    , slug : String
    , today : Maybe CivilDate
    , state : State
    }


type State
    = Loading
    | Failed Api.Error
    | Loaded Loaded_


type alias Loaded_ =
    { data : Overview
    , q : String
    , sourceFilter : Maybe String
    , selected : Maybe String
    }


type Msg
    = GotNow Posix
    | GotOverview (Result Api.Error Overview)
    | Search String
    | FilterSource String
    | OpenQuery String
    | CloseQuery
    | Noop


init : Session -> String -> ( Model, Cmd Msg )
init session slug =
    ( { session = session
      , slug = slug
      , today = Nothing
      , state = Loading
      }
    , Cmd.batch
        [ Task.perform GotNow Time.now
        , Api.get session
            (Url.Builder.absolute
                [ "papi", "workspaces", slug, "data-sources-overview" ]
                []
            )
            Overview.decoder
            GotOverview
        ]
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        mapLoaded f =
            case model.state of
                Loaded loaded ->
                    ( { model | state = Loaded (f loaded) }, Cmd.none )

                _ ->
                    ( model, Cmd.none )
    in
    case msg of
        GotNow now ->
            ( { model | today = Just (TimeFmt.civilFromPosix now) }, Cmd.none )

        GotOverview (Ok data) ->
            ( { model
                | state =
                    Loaded { data = data, q = "", sourceFilter = Nothing, selected = Nothing }
              }
            , Cmd.none
            )

        GotOverview (Err err) ->
            ( { model | state = Failed err }, Cmd.none )

        Search q ->
            mapLoaded (\loaded -> { loaded | q = String.trim q })

        FilterSource base ->
            mapLoaded
                (\loaded ->
                    { loaded
                        | sourceFilter =
                            if loaded.sourceFilter == Just base then
                                Nothing

                            else
                                Just base
                    }
                )

        OpenQuery queryName ->
            mapLoaded (\loaded -> { loaded | selected = Just queryName })

        CloseQuery ->
            mapLoaded (\loaded -> { loaded | selected = Nothing })

        Noop ->
            ( model, Cmd.none )



-- ===== View =====


view : Model -> Html Msg
view model =
    div [ class "content" ]
        (h1 [ class "page-title" ] [ text "Data sources" ]
            :: p [ class "page-subtitle" ]
                [ text "External databases this workspace can chart from, and the named queries built on them. Connected and managed through the CLI; credentials are encrypted at rest and never shown." ]
            :: (case model.state of
                    Loading ->
                        []

                    Failed err ->
                        [ div [ class "empty" ] [ text (Api.errorMessage err) ] ]

                    Loaded loaded ->
                        viewLoaded model loaded
               )
        )


viewLoaded : Model -> Loaded_ -> List (Html Msg)
viewLoaded model loaded =
    if List.isEmpty loaded.data.sources then
        [ viewEmpty ]

    else
        let
            sourceByBase =
                loaded.data.sources
                    |> List.map (\s -> ( s.baseId, s ))
                    |> Dict.fromList

            rollup =
                Overview.sourceRollup loaded.data.sources loaded.data.queries

            dependents =
                Overview.dependentsIndex loaded.data.queries
        in
        [ div [ class "ds-grid" ]
            (List.map (viewSourceCard loaded.sourceFilter rollup) loaded.data.sources)
        , viewTimelineLabel loaded.data.milestones
        ]
            ++ viewTimeline model.today loaded.data.milestones
            ++ viewCatalog sourceByBase dependents loaded
            ++ viewModal model.slug sourceByBase dependents loaded


snippet : String
snippet =
    "aveline create-data-source --name prod \\\n  --url \"postgres://metrics_ro:<password>@your-db-host:5432/your_db\" \\\n  --password \"...\""


viewEmpty : Html Msg
viewEmpty =
    div [ class "ds-empty" ]
        [ div [ class "ds-empty-icon", attribute "aria-hidden" "true" ]
            [ dbGlyph "1.6" ]
        , div [ class "ds-empty-title" ] [ text "Chart your data, right in your docs" ]
        , p [ class "ds-empty-copy" ]
            [ text "Connect a Postgres or MySQL database and any doc can carry live charts over it. Your agent writes the SQL; the doc stays current on every read. Ask your agent to run:" ]
        , pre [ class "blk-code ds-empty-code" ] [ code [] [ text snippet ] ]
        , p [ class "ds-empty-copy ds-empty-fine" ]
            [ text "Use a read-only database user, and put the literal placeholder in the template where the password goes. The template stays visible so you always know where a source points; the password is encrypted at rest and can never be read back. Queries are forced read-only and time-capped server-side either way." ]
        ]



-- ===== Source cards =====


viewSourceCard : Maybe String -> Dict String Overview.Rollup -> Source -> Html Msg
viewSourceCard sourceFilter rollup ds =
    let
        active =
            sourceFilter == Just ds.baseId

        roll =
            Dict.get ds.baseId rollup
                |> Maybe.withDefault { queries = 0, charts = 0 }
    in
    button
        [ type_ "button"
        , onClick (FilterSource ds.baseId)
        , classList
            [ ( "ds-card", True )
            , ( "ds-card-deleted", ds.deleted )
            , ( "ds-card-active", active )
            ]
        , title
            (if active then
                "Show all queries"

             else
                "Show only this source's queries"
            )
        ]
        [ div [ class "ds-card-head" ]
            (List.filterMap identity
                [ Just
                    (span
                        [ class ("ds-glyph ds-glyph-" ++ ds.adapter)
                        , attribute "aria-hidden" "true"
                        ]
                        [ if ds.adapter == "workspace" then
                            gridGlyph

                          else
                            dbGlyph "1.7"
                        ]
                    )
                , Just (span [ class "ds-card-name" ] [ text ds.name ])
                , Just
                    (span [ class ("ds-chip ds-chip-" ++ ds.adapter) ]
                        [ text (Overview.dialectLabel ds.adapter) ]
                    )
                , if ds.adapter == "workspace" then
                    Just (span [ class "ds-chip ds-chip-quiet" ] [ text "built-in" ])

                  else
                    Nothing
                , if ds.deleted then
                    Just (span [ class "ds-chip ds-chip-danger" ] [ text "deleted" ])

                  else
                    Nothing
                ]
            )
        , div [ class "ds-card-body" ]
            [ if ds.adapter == "workspace" then
                text "Your named queries as tables, composed in the analytics engine."

              else
                span [ class "ds-conn" ] [ text ds.url ]
            ]
        , div [ class "ds-card-foot" ]
            [ span []
                [ strong [] [ text (String.fromInt roll.queries) ]
                , text (" " ++ pluralize roll.queries "query" "queries")
                ]
            , span [ class "ds-foot-dot" ] [ text "·" ]
            , span []
                [ strong [] [ text (String.fromInt roll.charts) ]
                , text (" " ++ pluralize roll.charts "chart" "charts")
                ]
            , span [ class "ds-foot-right" ]
                (List.filterMap identity
                    [ if ds.adapter /= "workspace" then
                        Just
                            (span []
                                [ text
                                    (Maybe.withDefault "unknown" ds.createdBy
                                        ++ " · "
                                        ++ TimeFmt.monthDay (TimeFmt.civilFromPosix ds.createdAt)
                                    )
                                ]
                            )

                      else
                        Nothing
                    , if active then
                        Just (span [ class "ds-filter-on" ] [ text "filtering ✕" ])

                      else
                        Nothing
                    ]
                )
            ]
        ]



-- ===== Timeline strip =====


viewTimelineLabel : List Milestone -> Html Msg
viewTimelineLabel milestones =
    div [ class "section-label", style "margin-top" "32px" ]
        [ text "Timeline "
        , span [ class "count" ] [ text (String.fromInt (List.length milestones)) ]
        ]


viewTimeline : Maybe CivilDate -> List Milestone -> List (Html Msg)
viewTimeline today milestones =
    if List.isEmpty milestones then
        [ div [ class "qc-none", style "padding" "16px 0" ]
            [ text "No milestones yet. "
            , span [ class "mono" ]
                [ text "aveline create-milestone --name \"v1.4 shipped\" --date 2026-07-06" ]
            , text " marks one; every time-series chart in range annotates itself."
            ]
        ]

    else
        case today of
            Nothing ->
                []

            Just today_ ->
                [ div [ class "tl-strip" ]
                    (div [ class "tl-line", attribute "aria-hidden" "true" ] []
                        :: List.map viewMarker (Overview.timelinePositions today_ milestones)
                        ++ [ span [ class "tl-edge tl-edge-left" ]
                                [ text
                                    (Overview.timelineStart milestones
                                        |> Maybe.map TimeFmt.monthDay
                                        |> Maybe.withDefault ""
                                    )
                                ]
                           , span [ class "tl-edge tl-edge-right" ] [ text "today" ]
                           ]
                    )
                ]


viewMarker : ( Milestone, Float, Int ) -> Html Msg
viewMarker ( m, pct, row ) =
    div
        [ classList [ ( "tl-marker", True ), ( "tl-marker-high", row == 1 ) ]
        , style "left" (String.fromFloat pct ++ "%")
        ]
        (List.filterMap identity
            [ Just (span [ class "tl-marker-label" ] [ text m.name ])
            , Just (span [ class "tl-marker-dot", attribute "aria-hidden" "true" ] [])
            , Just
                (div [ class "tl-tip" ]
                    (List.filterMap identity
                        [ Just (div [ class "tl-tip-name" ] [ text m.name ])
                        , Just (div [ class "tl-tip-date" ] [ text (TimeFmt.monthDayYear m.date) ])
                        , m.description
                            |> Maybe.map (\d -> div [ class "tl-tip-desc" ] [ text d ])
                        ]
                    )
                )
            ]
        )



-- ===== Query catalog =====


viewCatalog : Dict String Source -> Dict String (List String) -> Loaded_ -> List (Html Msg)
viewCatalog sourceByBase dependents loaded =
    let
        wsBase_ =
            Overview.wsBase loaded.data.sources

        shown =
            Overview.visibleQueries
                { sourceFilter = loaded.sourceFilter, wsBase_ = wsBase_, q = loaded.q }
                loaded.data.queries
    in
    [ div [ class "qc-header" ]
        [ div [ class "section-label", style "margin" "0" ]
            (text "Query catalog "
                :: span [ class "count" ]
                    [ text (String.fromInt (List.length loaded.data.queries)) ]
                :: (case loaded.sourceFilter of
                        Just base ->
                            [ button
                                [ type_ "button"
                                , class "qc-filter-chip"
                                , onClick (FilterSource base)
                                ]
                                [ text
                                    ((Dict.get base sourceByBase
                                        |> Maybe.map .name
                                        |> Maybe.withDefault "?"
                                     )
                                        ++ " ✕"
                                    )
                                ]
                            ]

                        Nothing ->
                            []
                   )
            )
        , Html.form
            [ class "qc-search-form"
            , preventDefaultOn "submit" (Decode.succeed ( Noop, True ))
            ]
            [ searchIcon
            , Html.input
                [ type_ "text"
                , name "q"
                , value loaded.q
                , placeholder "Search queries…"
                , autocomplete False
                , class "qc-search"
                , onInput Search
                ]
                []
            ]
        ]
    , if List.isEmpty loaded.data.queries then
        div [ class "qc-none" ]
            [ text "No queries yet. "
            , span [ class "mono" ] [ text "aveline create-query --name … --description … --sql …" ]
            , text " names the first one."
            ]

      else if List.isEmpty shown then
        div [ class "qc-none" ] [ text "Nothing matches." ]

      else
        div [ class "qc-grid" ]
            (List.map (viewQueryCard sourceByBase dependents) shown)
    ]


viewQueryCard : Dict String Source -> Dict String (List String) -> Query -> Html Msg
viewQueryCard sourceByBase dependents query =
    let
        ( chipLabel, chipAdapter ) =
            sourceChip sourceByBase query

        feeds =
            Dict.get query.name dependents |> Maybe.withDefault []
    in
    button
        [ type_ "button", onClick (OpenQuery query.name), class "qc-card" ]
        [ div [ class "qc-card-head" ]
            [ span [ class "qc-name" ] [ text query.name ]
            , span [ class ("ds-chip ds-chip-" ++ chipAdapter) ] [ text chipLabel ]
            ]
        , div
            [ classList
                [ ( "qc-desc", True )
                , ( "qc-desc-missing", query.description == Nothing )
                ]
            ]
            [ text (Maybe.withDefault "No description yet." query.description) ]
        , div [ class "qc-foot" ]
            (List.filterMap identity
                [ if query.chartCount > 0 then
                    Just
                        (span []
                            [ strong [] [ text (String.fromInt query.chartCount) ]
                            , text (" " ++ pluralize query.chartCount "chart" "charts")
                            ]
                        )

                  else
                    Just (span [ class "qc-unused" ] [ text "unused" ])
                , if not (List.isEmpty query.builtOn) then
                    Just
                        (span []
                            [ span [ class "ds-foot-dot" ] [ text "·" ]
                            , text " on "
                            , strong [] [ text (String.fromInt (List.length query.builtOn)) ]
                            ]
                        )

                  else
                    Nothing
                , if not (List.isEmpty feeds) then
                    Just
                        (span []
                            [ span [ class "ds-foot-dot" ] [ text "·" ]
                            , text " feeds "
                            , strong [] [ text (String.fromInt (List.length feeds)) ]
                            ]
                        )

                  else
                    Nothing
                , Just
                    (span [ class "qc-foot-by" ]
                        [ text
                            (Maybe.withDefault "unknown" query.createdBy
                                ++ " · "
                                ++ TimeFmt.monthDay (TimeFmt.civilFromPosix query.createdAt)
                            )
                        ]
                    )
                ]
            )
        ]



-- ===== Query modal =====


viewModal : String -> Dict String Source -> Dict String (List String) -> Loaded_ -> List (Html Msg)
viewModal workspaceSlug sourceByBase dependents loaded =
    case
        loaded.selected
            |> Maybe.andThen
                (\selectedName ->
                    loaded.data.queries
                        |> List.filter (\q -> q.name == selectedName)
                        |> List.head
                )
    of
        Nothing ->
            []

        Just query ->
            let
                ( chipLabel, chipAdapter ) =
                    sourceChip sourceByBase query

                feeds =
                    Dict.get query.name dependents |> Maybe.withDefault []

                chartedIn =
                    List.sortBy .title query.chartedIn

                depsRow label deps =
                    if List.isEmpty deps then
                        Nothing

                    else
                        Just
                            (div [ class "qm-deps" ]
                                (span [ class "qm-deps-label" ] [ text label ]
                                    :: List.map
                                        (\dep ->
                                            button
                                                [ type_ "button"
                                                , class "qm-dep-chip"
                                                , onClick (OpenQuery dep)
                                                ]
                                                [ text dep ]
                                        )
                                        deps
                                )
                            )
            in
            [ div
                [ class "modal-backdrop", onClick CloseQuery ]
                [ div
                    [ class "modal-card qm-card"
                    , stopPropagationOn "click" (Decode.succeed ( Noop, True ))
                    ]
                    (List.filterMap identity
                        [ Just
                            (div [ class "qm-head" ]
                                [ span [ class "qc-name qm-name" ] [ text query.name ]
                                , span [ class ("ds-chip ds-chip-" ++ chipAdapter) ] [ text chipLabel ]
                                , span [ class "ds-chip ds-chip-quiet" ]
                                    [ text ("v" ++ String.fromInt query.versionNumber) ]
                                , button
                                    [ type_ "button"
                                    , class "qm-close"
                                    , onClick CloseQuery
                                    , attribute "aria-label" "Close"
                                    ]
                                    [ text "✕" ]
                                ]
                            )
                        , Just
                            (p
                                [ classList
                                    [ ( "qm-desc", True )
                                    , ( "qm-desc-missing", False )
                                    , ( "qc-desc-missing", query.description == Nothing )
                                    ]
                                ]
                                (case query.description of
                                    Just desc ->
                                        [ text desc ]

                                    Nothing ->
                                        [ text "No description yet. "
                                        , span [ class "mono" ]
                                            [ text ("aveline edit-query " ++ query.name ++ " --description \"…\"") ]
                                        ]
                                )
                            )
                        , depsRow "built on" query.builtOn
                        , depsRow "feeds" feeds
                        , if List.isEmpty chartedIn then
                            Nothing

                          else
                            Just
                                (div [ class "qm-deps" ]
                                    (span [ class "qm-deps-label" ] [ text "charted in" ]
                                        :: List.map
                                            (\doc ->
                                                Html.a
                                                    [ href ("/w/" ++ workspaceSlug ++ "/d/" ++ doc.slug)
                                                    , class "qm-doc-link"
                                                    ]
                                                    [ text doc.title ]
                                            )
                                            chartedIn
                                    )
                                )
                        , Just
                            (pre
                                [ id ("qm-sql-" ++ query.name)
                                , class "q-sql qm-sql"
                                , attribute "data-dialect" (formatterDialect sourceByBase query)
                                ]
                                [ code [ class "language-sql" ] [ text query.sql ] ]
                            )
                        , Just
                            (div [ class "qm-meta" ]
                                [ text
                                    (query.kind
                                        ++ " query · created by "
                                        ++ Maybe.withDefault "unknown" query.createdBy
                                        ++ " · "
                                        ++ TimeFmt.monthDayYear (TimeFmt.civilFromPosix query.createdAt)
                                    )
                                ]
                            )
                        ]
                    )
                ]
            ]



-- ===== Helpers =====


{-| DataSourcesLive.source\_chip/1: the chip on a query names its raw
source, or "derived / workspace" when it composes the catalog.
-}
sourceChip : Dict String Source -> Query -> ( String, String )
sourceChip sourceByBase query =
    case query.dataSourceId |> Maybe.andThen (\base -> Dict.get base sourceByBase) of
        Just source ->
            ( source.name, source.adapter )

        Nothing ->
            ( "derived", "workspace" )


{-| DataSourcesLive.formatter\_dialect/2 — kept as a data attribute so a
future SQL-formatter element can pick it up.
-}
formatterDialect : Dict String Source -> Query -> String
formatterDialect sourceByBase query =
    if query.kind == "derived" then
        "postgresql"

    else
        case query.dataSourceId |> Maybe.andThen (\base -> Dict.get base sourceByBase) of
            Just source ->
                case source.adapter of
                    "mysql" ->
                        "mysql"

                    "redshift" ->
                        "redshift"

                    _ ->
                        "postgresql"

            Nothing ->
                "postgresql"


pluralize : Int -> String -> String -> String
pluralize n singular plural =
    if n == 1 then
        singular

    else
        plural


dbGlyph : String -> Html Msg
dbGlyph strokeWidth =
    Svg.svg
        [ SvgAttr.viewBox "0 0 24 24"
        , SvgAttr.fill "none"
        , SvgAttr.stroke "currentColor"
        , SvgAttr.strokeWidth strokeWidth
        , SvgAttr.strokeLinecap "round"
        , SvgAttr.strokeLinejoin "round"
        ]
        [ Svg.ellipse [ SvgAttr.cx "12", SvgAttr.cy "5", SvgAttr.rx "9", SvgAttr.ry "3" ] []
        , Svg.path [ SvgAttr.d "M3 5v14a9 3 0 0 0 18 0V5" ] []
        , Svg.path [ SvgAttr.d "M3 12a9 3 0 0 0 18 0" ] []
        ]


gridGlyph : Html Msg
gridGlyph =
    Svg.svg
        [ SvgAttr.viewBox "0 0 24 24"
        , SvgAttr.fill "none"
        , SvgAttr.stroke "currentColor"
        , SvgAttr.strokeWidth "1.7"
        , SvgAttr.strokeLinecap "round"
        , SvgAttr.strokeLinejoin "round"
        ]
        [ Svg.rect [ SvgAttr.x "3", SvgAttr.y "3", SvgAttr.width "7", SvgAttr.height "7", SvgAttr.rx "1.5" ] []
        , Svg.rect [ SvgAttr.x "14", SvgAttr.y "3", SvgAttr.width "7", SvgAttr.height "7", SvgAttr.rx "1.5" ] []
        , Svg.rect [ SvgAttr.x "3", SvgAttr.y "14", SvgAttr.width "7", SvgAttr.height "7", SvgAttr.rx "1.5" ] []
        , Svg.rect [ SvgAttr.x "14", SvgAttr.y "14", SvgAttr.width "7", SvgAttr.height "7", SvgAttr.rx "1.5" ] []
        ]


searchIcon : Html Msg
searchIcon =
    Svg.svg
        [ SvgAttr.class "qc-search-icon"
        , SvgAttr.viewBox "0 0 24 24"
        , SvgAttr.fill "none"
        , SvgAttr.stroke "currentColor"
        , SvgAttr.strokeWidth "2"
        , SvgAttr.strokeLinecap "round"
        , SvgAttr.strokeLinejoin "round"
        ]
        [ Svg.circle [ SvgAttr.cx "11", SvgAttr.cy "11", SvgAttr.r "8" ] []
        , Svg.line [ SvgAttr.x1 "21", SvgAttr.y1 "21", SvgAttr.x2 "16.65", SvgAttr.y2 "16.65" ] []
        ]
