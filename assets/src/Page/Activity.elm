module Page.Activity exposing (Model, Msg, init, update, view)

{-| Workspace audit timeline, ported from
lib/aveline\_web/live/activity\_live.ex. One compact row per event —
who, what, when, link to the target — over GET /papi events with
`before_id` keyset pagination ("Load older").

Main content region only; the coordinator adds the sidebar chrome.

-}

import Activity.Feed as Feed exposing (Event)
import Api
import Html exposing (Html, button, div, h1, li, ol, p, span, text)
import Html.Attributes exposing (class, href, title, type_)
import Html.Events exposing (onClick)
import Session exposing (Session)
import Svg
import Svg.Attributes as SvgAttr
import Task
import Time exposing (Posix)
import TimeFmt
import Url.Builder


type alias Model =
    { session : Session
    , slug : String
    , now : Maybe Posix
    , state : State
    }


type State
    = Loading
    | Failed Api.Error
    | Loaded Loaded_


type alias Loaded_ =
    { events : List Event
    , hasMore : Bool
    , loadingMore : Bool
    }


type Msg
    = GotNow Posix
    | GotFirstPage (Result Api.Error (List Event))
    | LoadMore
    | GotOlderPage (Result Api.Error (List Event))


init : Session -> String -> ( Model, Cmd Msg )
init session slug =
    ( { session = session
      , slug = slug
      , now = Nothing
      , state = Loading
      }
    , Cmd.batch
        [ Task.perform GotNow Time.now
        , fetchPage session slug Nothing GotFirstPage
        ]
    )


fetchPage : Session -> String -> Maybe String -> (Result Api.Error (List Event) -> Msg) -> Cmd Msg
fetchPage session slug beforeId toMsg =
    Api.get session
        (Url.Builder.absolute [ "papi", "workspaces", slug, "events" ]
            (Url.Builder.int "limit" Feed.requestLimit
                :: (case beforeId of
                        Just id ->
                            [ Url.Builder.string "before_id" id ]

                        Nothing ->
                            []
                   )
            )
        )
        Feed.responseDecoder
        toMsg


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotNow now ->
            ( { model | now = Just now }, Cmd.none )

        GotFirstPage (Ok fetched) ->
            let
                page =
                    Feed.splitPage fetched
            in
            ( { model
                | state =
                    Loaded { events = page.events, hasMore = page.hasMore, loadingMore = False }
              }
            , Cmd.none
            )

        GotFirstPage (Err err) ->
            ( { model | state = Failed err }, Cmd.none )

        LoadMore ->
            case model.state of
                Loaded loaded ->
                    if loaded.loadingMore then
                        ( model, Cmd.none )

                    else
                        ( { model | state = Loaded { loaded | loadingMore = True } }
                        , fetchPage model.session
                            model.slug
                            (Feed.nextCursor loaded.events)
                            GotOlderPage
                        )

                _ ->
                    ( model, Cmd.none )

        GotOlderPage (Ok fetched) ->
            case model.state of
                Loaded loaded ->
                    let
                        page =
                            Feed.splitPage fetched
                    in
                    ( { model
                        | state =
                            Loaded
                                { events = loaded.events ++ page.events
                                , hasMore = page.hasMore
                                , loadingMore = False
                                }
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        GotOlderPage (Err _) ->
            -- Keep what we have; the button stays for a retry.
            case model.state of
                Loaded loaded ->
                    ( { model | state = Loaded { loaded | loadingMore = False } }, Cmd.none )

                _ ->
                    ( model, Cmd.none )



-- ===== View =====


view : Model -> Html Msg
view model =
    div [ class "content" ]
        (h1 [ class "page-title" ] [ text "Activity" ]
            :: p [ class "page-subtitle" ]
                [ text "Everything that's happened in "
                , span [ class "mono" ] [ text model.slug ]
                , text " — most recent first."
                ]
            :: (case model.state of
                    Loading ->
                        []

                    Failed err ->
                        [ div [ class "empty" ] [ text (Api.errorMessage err) ] ]

                    Loaded loaded ->
                        viewFeed model loaded
               )
        )


viewFeed : Model -> Loaded_ -> List (Html Msg)
viewFeed model loaded =
    if List.isEmpty loaded.events then
        [ div [ class "empty" ]
            [ text "Nothing yet. Actions show up here as people (and agents) work." ]
        ]

    else
        ol [ class "event-list" ] (List.map (viewEvent model) loaded.events)
            :: (if loaded.hasMore then
                    [ div [ class "load-more-wrap" ]
                        [ button
                            [ type_ "button", class "load-more-btn", onClick LoadMore ]
                            [ text "Load older" ]
                        ]
                    ]

                else
                    []
               )


viewEvent : Model -> Event -> Html Msg
viewEvent model event =
    li [ class "event-row" ]
        (List.filterMap identity
            [ Just
                (span [ class "event-actor" ]
                    (List.filterMap identity
                        [ actorIcon event.actorType
                        , Just
                            (span [ class "event-actor-name" ]
                                [ text (Maybe.withDefault "?" event.actorName) ]
                            )
                        , if event.actorType == "agent" then
                            Just (span [ class "event-via" ] [ text "via Claude" ])

                          else
                            Nothing
                        ]
                    )
                )
            , Just (span [ class "event-verb" ] [ text (Feed.verb event.action) ])
            , targetLink model.slug event
            , Feed.detail event
                |> Maybe.map
                    (\d -> span [ class "event-detail" ] [ text ("— " ++ d) ])
            , Just (span [ class "card-meta-dot" ] [ text "·" ])
            , Just
                (span
                    [ class "event-time", title (TimeFmt.absoluteTime event.occurredAt) ]
                    [ text
                        (case model.now of
                            Just now ->
                                TimeFmt.relativeTime now event.occurredAt

                            Nothing ->
                                ""
                        )
                    ]
                )
            ]
        )


{-| Link to the target when we know how; plain label otherwise —
ActivityLive.target\_link/1.
-}
targetLink : String -> Event -> Maybe (Html Msg)
targetLink workspaceSlug event =
    let
        label =
            Maybe.withDefault "" event.targetLabel

        docLink slug =
            Html.a
                [ href ("/w/" ++ workspaceSlug ++ "/d/" ++ slug), class "event-target" ]
                [ text
                    (case event.targetLabel of
                        Just l ->
                            l

                        Nothing ->
                            slug
                    )
                ]
    in
    case ( event.targetKind, event.targetSlug ) of
        ( Just "doc", Just slug ) ->
            Just (docLink slug)

        ( Just "comment", Just slug ) ->
            Just (docLink slug)

        _ ->
            case event.targetLabel of
                Just _ ->
                    Just (span [ class "event-target" ] [ text label ])

                Nothing ->
                    Nothing


{-| AvelineWeb.Icons.actor/1 — Lucide "user" / "bot", 2px stroke.
-}
actorIcon : String -> Maybe (Html Msg)
actorIcon actorType =
    let
        icon paths =
            Svg.svg
                [ SvgAttr.class "actor-icon"
                , SvgAttr.viewBox "0 0 24 24"
                , SvgAttr.fill "none"
                , SvgAttr.stroke "currentColor"
                , SvgAttr.strokeWidth "2"
                , SvgAttr.strokeLinecap "round"
                , SvgAttr.strokeLinejoin "round"
                ]
                (Svg.title [] [ text actorType ] :: paths)
    in
    case actorType of
        "human" ->
            Just
                (icon
                    [ Svg.path [ SvgAttr.d "M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" ] []
                    , Svg.circle [ SvgAttr.cx "12", SvgAttr.cy "7", SvgAttr.r "4" ] []
                    ]
                )

        "agent" ->
            Just
                (icon
                    [ Svg.path [ SvgAttr.d "M12 8V4H8" ] []
                    , Svg.rect
                        [ SvgAttr.width "16"
                        , SvgAttr.height "12"
                        , SvgAttr.x "4"
                        , SvgAttr.y "8"
                        , SvgAttr.rx "2"
                        ]
                        []
                    , Svg.path [ SvgAttr.d "M2 14h2" ] []
                    , Svg.path [ SvgAttr.d "M20 14h2" ] []
                    , Svg.path [ SvgAttr.d "M15 13v2" ] []
                    , Svg.path [ SvgAttr.d "M9 13v2" ] []
                    ]
                )

        _ ->
            Nothing
