module Page.Home exposing (Model, Msg, init, update, view)

{-| Workspace home — ported from `lib/aveline_web/live/home_live.ex`.
Renders only the page's main content region (`.content.home-content`);
the sidebar/topbar chrome is added by the coordinator in Main.elm.

Data comes from two /papi calls:

  - GET /papi/workspaces/:slug/home (fe-workspace endpoint: viewer,
    orientation, pinned docs, open threads, recently viewed, changes)
  - GET /papi/workspaces/:slug/tags (existing endpoint: the glossary)

-}

import Api
import Html exposing (Html, a, button, div, h1, section, span, text)
import Html.Attributes exposing (attribute, class, href, title, type_)
import Html.Events exposing (onClick)
import Iso8601
import Json.Decode as Decode exposing (Decoder)
import Route
import Session exposing (Session)
import Svg
import Svg.Attributes as SA
import Task
import Time exposing (Posix)
import Ui.Workspace.Time exposing (absoluteTime, relativeTime)



-- MODEL


type alias Model =
    { session : Session
    , slug : String
    , now : Maybe Posix
    , home : Status HomeData
    , tags : List TagRow
    , glossaryOpen : Maybe String
    }


type Status a
    = Loading
    | Loaded a
    | Failed Api.Error


type alias HomeData =
    { viewer : Viewer
    , orientation : Maybe DocCard
    , pinnedDocs : List DocCard
    , needsYou : List Thread
    , recentlyViewed : List Viewed
    , recentChanges : List Change
    }


type alias Viewer =
    { username : String
    , displayName : Maybe String
    }


type alias DocCard =
    { slug : String
    , title : String
    , summary : Maybe String
    , tags : List String
    }


type alias Thread =
    { body : String
    , blockId : Maybe String
    , actorType : String
    , actorUsername : Maybe String
    , insertedAt : Posix
    , docSlug : String
    , docTitle : String
    }


type alias Viewed =
    { slug : String
    , title : String
    , viewedAt : Posix
    }


type alias Change =
    { slug : String
    , title : String
    , versionNumber : Int
    , intent : Maybe String
    , updatedAt : Posix
    }


type alias TagRow =
    { slug : String
    , description : String
    , color : Maybe String
    }


init : Session -> String -> ( Model, Cmd Msg )
init session slug =
    ( { session = session
      , slug = slug
      , now = Nothing
      , home = Loading
      , tags = []
      , glossaryOpen = Nothing
      }
    , Cmd.batch
        [ Task.perform GotNow Time.now
        , Api.get session ("/papi/workspaces/" ++ slug ++ "/home") homeDecoder GotHome
        , Api.get session ("/papi/workspaces/" ++ slug ++ "/tags") tagsDecoder GotTags
        ]
    )



-- UPDATE


type Msg
    = GotNow Posix
    | GotHome (Result Api.Error HomeData)
    | GotTags (Result Api.Error (List TagRow))
    | GlossaryToggle String


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotNow now ->
            ( { model | now = Just now }, Cmd.none )

        GotHome (Ok data) ->
            ( { model | home = Loaded data }, Cmd.none )

        GotHome (Err err) ->
            ( { model | home = Failed err }, Cmd.none )

        GotTags (Ok rows) ->
            ( { model | tags = rows }, Cmd.none )

        GotTags (Err _) ->
            ( { model | tags = [] }, Cmd.none )

        GlossaryToggle slug ->
            ( { model
                | glossaryOpen =
                    if model.glossaryOpen == Just slug then
                        Nothing

                    else
                        Just slug
              }
            , Cmd.none
            )



-- VIEW


view : Model -> Html Msg
view model =
    case model.home of
        Loading ->
            div [ class "content home-content" ] []

        Failed err ->
            div [ class "content home-content" ]
                [ div [ class "empty" ] [ text (Api.errorMessage err) ] ]

        Loaded data ->
            viewLoaded model data


viewLoaded : Model -> HomeData -> Html Msg
viewLoaded model data =
    div [ class "content home-content" ]
        (List.filterMap identity
            [ Just
                (h1 [ class "page-title home-title" ]
                    [ text ("Welcome back, " ++ displayName data.viewer) ]
                )
            , viewPinned model.slug data
            , viewNeedsYou model data
            , viewDuo model data
            , viewGlossary model
            , viewEmpty data
            ]
        )


displayName : Viewer -> String
displayName viewer =
    case viewer.displayName of
        Just name ->
            name

        Nothing ->
            viewer.username


docPath : String -> String -> String
docPath slug docSlug =
    Route.href (Route.DocShow slug docSlug)



-- Pinned docs + orientation card


viewPinned : String -> HomeData -> Maybe (Html Msg)
viewPinned slug data =
    if List.isEmpty data.pinnedDocs && data.orientation == Nothing then
        Nothing

    else
        Just
            (section [ class "shelf" ]
                [ div [ class "shelf-head" ]
                    [ span [ class "shelf-icon", attribute "aria-hidden" "true" ] [ pinIcon ]
                    , span [ class "shelf-label" ] [ text "Pinned docs" ]
                    ]
                , div [ class "story-grid" ]
                    ((case data.orientation of
                        Just o ->
                            [ a
                                [ href (docPath slug o.slug), class "orientation-card" ]
                                [ span [ class "orientation-body" ]
                                    (span [ class "orientation-title" ] [ text o.title ]
                                        :: (case o.summary of
                                                Just s ->
                                                    [ span [ class "orientation-summary" ] [ text s ] ]

                                                Nothing ->
                                                    []
                                           )
                                    )
                                , span [ class "orientation-cta" ] [ text "Get oriented →" ]
                                ]
                            ]

                        Nothing ->
                            []
                     )
                        ++ List.map (viewStoryCard slug) data.pinnedDocs
                    )
                ]
            )


viewStoryCard : String -> DocCard -> Html Msg
viewStoryCard slug d =
    a [ href (docPath slug d.slug), class "story-card" ]
        (List.filterMap identity
            [ Just
                (div [ class "story-card-top" ]
                    [ span [ class "story-card-title" ] [ text d.title ] ]
                )
            , Maybe.map
                (\s -> div [ class "story-card-summary" ] [ text s ])
                d.summary
            , if List.isEmpty d.tags then
                Nothing

              else
                Just
                    (div [ class "story-card-tags" ]
                        (List.map
                            (\t -> span [ class "story-card-tag" ] [ text t ])
                            (List.take 3 d.tags)
                        )
                    )
            ]
        )



-- Open comments on your docs


viewNeedsYou : Model -> HomeData -> Maybe (Html Msg)
viewNeedsYou model data =
    if List.isEmpty data.needsYou then
        Nothing

    else
        Just
            (section [ class "shelf" ]
                [ div [ class "shelf-head" ]
                    [ span [ class "shelf-icon shelf-icon-attn", attribute "aria-hidden" "true" ] [ commentIcon ]
                    , span [ class "shelf-label" ] [ text "Open comments on your docs" ]
                    , span [ class "shelf-count shelf-count-attn" ]
                        [ text (String.fromInt (List.length data.needsYou) ++ " open") ]
                    ]
                , div [ class "attn-list" ]
                    (List.map (viewThread model) data.needsYou)
                ]
            )


viewThread : Model -> Thread -> Html Msg
viewThread model c =
    let
        anchor =
            case c.blockId of
                Just blockId ->
                    "#" ++ blockId

                Nothing ->
                    ""
    in
    a [ href (docPath model.slug c.docSlug ++ anchor), class "attn-row" ]
        [ span [ class "attn-body" ] [ text ("“" ++ snippet c.body ++ "”") ]
        , span [ class "attn-meta" ]
            (List.filterMap identity
                [ Maybe.map (\u -> text (u ++ " ")) c.actorUsername
                , if c.actorType == "agent" then
                    Just (span [ class "attn-via" ] [ text "via Claude" ])

                  else
                    Nothing
                , Just (text " on ")
                , Just (span [ class "attn-doc" ] [ text c.docTitle ])
                , Just (text (" · " ++ relative model c.insertedAt))
                ]
            )
        ]


snippet : String -> String
snippet body =
    let
        trimmed =
            String.trim body
    in
    if String.length trimmed > 110 then
        String.left 110 trimmed ++ "…"

    else
        trimmed



-- Recently viewed / recently changed


viewDuo : Model -> HomeData -> Maybe (Html Msg)
viewDuo model data =
    if List.isEmpty data.recentlyViewed && List.isEmpty data.recentChanges then
        Nothing

    else
        Just
            (div [ class "home-duo" ]
                (List.filterMap identity
                    [ viewRecentlyViewed model data
                    , viewRecentChanges model data
                    ]
                )
            )


viewRecentlyViewed : Model -> HomeData -> Maybe (Html Msg)
viewRecentlyViewed model data =
    if List.isEmpty data.recentlyViewed then
        Nothing

    else
        Just
            (section [ class "shelf" ]
                [ div [ class "shelf-head" ]
                    [ span [ class "shelf-icon", attribute "aria-hidden" "true" ] [ clockIcon ]
                    , span [ class "shelf-label" ] [ text "Recently viewed by you" ]
                    ]
                , div [ class "recent-list" ]
                    (List.map
                        (\v ->
                            a [ href (docPath model.slug v.slug), class "recent-row" ]
                                [ span [ class "recent-title" ] [ text v.title ]
                                , span [ class "recent-time", title (absoluteTime v.viewedAt) ]
                                    [ text ("opened " ++ relative model v.viewedAt) ]
                                ]
                        )
                        data.recentlyViewed
                    )
                ]
            )


viewRecentChanges : Model -> HomeData -> Maybe (Html Msg)
viewRecentChanges model data =
    if List.isEmpty data.recentChanges then
        Nothing

    else
        Just
            (section [ class "shelf" ]
                [ div [ class "shelf-head" ]
                    [ span [ class "shelf-icon", attribute "aria-hidden" "true" ] [ activityIcon ]
                    , span [ class "shelf-label" ] [ text "Recently changed" ]
                    ]
                , div [ class "recent-list" ]
                    (List.map (viewChange model) data.recentChanges)
                , a [ href (Route.href (Route.Activity model.slug)), class "shelf-more" ]
                    [ text "View all activity →" ]
                ]
            )


viewChange : Model -> Change -> Html Msg
viewChange model d =
    a [ href (docPath model.slug d.slug), class "recent-row" ]
        (List.filterMap identity
            [ Just (span [ class "recent-title" ] [ text d.title ])
            , Just
                (span [ class "recent-version" ]
                    [ text ("v" ++ String.fromInt d.versionNumber) ]
                )
            , Maybe.map
                (\i -> span [ class "recent-intent" ] [ text ("“" ++ i ++ "”") ])
                d.intent
            , Just (span [ class "recent-time" ] [ text (relative model d.updatedAt) ])
            ]
        )



-- Tag glossary


viewGlossary : Model -> Maybe (Html Msg)
viewGlossary model =
    if List.isEmpty model.tags then
        Nothing

    else
        Just
            (section [ class "shelf" ]
                [ div [ class "shelf-head" ]
                    [ span [ class "shelf-icon", attribute "aria-hidden" "true" ] [ tagIcon ]
                    , span [ class "shelf-label" ] [ text "Tags" ]
                    ]
                , div [ class "tag-glossary" ]
                    [ div [ class "tag-cloud" ]
                        (List.map (viewChip model.glossaryOpen) model.tags)
                    , div [ class "tag-info" ]
                        [ case openGlossaryRow model.tags model.glossaryOpen of
                            Just row ->
                                span [ class "tag-info-desc" ] [ text row.description ]

                            Nothing ->
                                span [ class "tag-info-hint" ]
                                    [ text "Click a tag to read what it means." ]
                        ]
                    ]
                ]
            )


viewChip : Maybe String -> TagRow -> Html Msg
viewChip open row =
    let
        openClass =
            if open == Just row.slug then
                " chip-open"

            else
                ""

        styleAttrs =
            case row.color of
                Just c ->
                    -- CSS custom properties need a raw style attribute.
                    [ attribute "style"
                        ("--tag: " ++ c ++ "; --tag-dim: " ++ c ++ "14; --tag-border: " ++ c ++ "40")
                    ]

                Nothing ->
                    []
    in
    button
        ([ type_ "button"
         , onClick (GlossaryToggle row.slug)
         , class ("chip chip-tag" ++ openClass)
         ]
            ++ styleAttrs
        )
        [ span [ class "chip-text" ] [ text row.slug ] ]


openGlossaryRow : List TagRow -> Maybe String -> Maybe TagRow
openGlossaryRow rows open =
    open
        |> Maybe.andThen
            (\slug -> List.head (List.filter (\r -> r.slug == slug) rows))



-- Empty state


viewEmpty : HomeData -> Maybe (Html Msg)
viewEmpty data =
    if List.isEmpty data.pinnedDocs && List.isEmpty data.needsYou && List.isEmpty data.recentChanges then
        Just
            (div [ class "empty" ]
                [ text "Nothing here yet. Create a doc (or have your agent do it) and this page fills itself in." ]
            )

    else
        Nothing


relative : Model -> Posix -> String
relative model t =
    case model.now of
        Just now ->
            relativeTime now t

        Nothing ->
            ""



-- ICONS (exact svgs from home_live.ex)


pinIcon : Html msg
pinIcon =
    Svg.svg
        [ SA.viewBox "0 0 24 24"
        , SA.fill "none"
        , SA.stroke "currentColor"
        , SA.strokeWidth "2"
        , SA.strokeLinecap "round"
        , SA.strokeLinejoin "round"
        ]
        [ Svg.path [ SA.d "M12 17v5" ] []
        , Svg.path [ SA.d "M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 0 1 1 1z" ] []
        ]


commentIcon : Html msg
commentIcon =
    Svg.svg
        [ SA.viewBox "0 0 24 24"
        , SA.fill "none"
        , SA.stroke "currentColor"
        , SA.strokeWidth "2"
        , SA.strokeLinecap "round"
        , SA.strokeLinejoin "round"
        ]
        [ Svg.path [ SA.d "M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" ] [] ]


clockIcon : Html msg
clockIcon =
    Svg.svg
        [ SA.viewBox "0 0 24 24"
        , SA.fill "none"
        , SA.stroke "currentColor"
        , SA.strokeWidth "2"
        , SA.strokeLinecap "round"
        , SA.strokeLinejoin "round"
        ]
        [ Svg.circle [ SA.cx "12", SA.cy "12", SA.r "10" ] []
        , Svg.polyline [ SA.points "12 6 12 12 16 14" ] []
        ]


activityIcon : Html msg
activityIcon =
    Svg.svg
        [ SA.viewBox "0 0 24 24"
        , SA.fill "none"
        , SA.stroke "currentColor"
        , SA.strokeWidth "2"
        , SA.strokeLinecap "round"
        , SA.strokeLinejoin "round"
        ]
        [ Svg.polyline [ SA.points "22 12 18 12 15 21 9 3 6 12 2 12" ] [] ]


tagIcon : Html msg
tagIcon =
    Svg.svg
        [ SA.viewBox "0 0 16 16"
        , SA.fill "none"
        , SA.stroke "currentColor"
        , SA.strokeWidth "1.5"
        ]
        [ Svg.path [ SA.d "M2 7l5-5h6v6l-5 5z", SA.strokeLinejoin "round" ] []
        , Svg.circle [ SA.cx "9.5", SA.cy "6.5", SA.r "0.9", SA.fill "currentColor" ] []
        ]



-- DECODERS


homeDecoder : Decoder HomeData
homeDecoder =
    Decode.map6 HomeData
        (Decode.field "viewer" viewerDecoder)
        (Decode.field "orientation" (Decode.nullable docCardDecoder))
        (Decode.field "pinned_docs" (Decode.list docCardDecoder))
        (Decode.field "needs_you" (Decode.list threadDecoder))
        (Decode.field "recently_viewed" (Decode.list viewedDecoder))
        (Decode.field "recent_changes" (Decode.list changeDecoder))


viewerDecoder : Decoder Viewer
viewerDecoder =
    Decode.map2 Viewer
        (Decode.field "username" Decode.string)
        (Decode.field "display_name" (Decode.nullable Decode.string))


docCardDecoder : Decoder DocCard
docCardDecoder =
    Decode.map4 DocCard
        (Decode.field "slug" Decode.string)
        (Decode.field "title" Decode.string)
        (Decode.field "summary" (Decode.nullable Decode.string))
        (Decode.field "tags" (Decode.list Decode.string))


threadDecoder : Decoder Thread
threadDecoder =
    Decode.map7 Thread
        (Decode.field "body" Decode.string)
        (Decode.field "block_id" (Decode.nullable Decode.string))
        (Decode.field "actor_type" Decode.string)
        (Decode.field "actor_username" (Decode.nullable Decode.string))
        (Decode.field "inserted_at" Iso8601.decoder)
        (Decode.field "doc_slug" Decode.string)
        (Decode.field "doc_title" Decode.string)


viewedDecoder : Decoder Viewed
viewedDecoder =
    Decode.map3 Viewed
        (Decode.field "slug" Decode.string)
        (Decode.field "title" Decode.string)
        (Decode.field "viewed_at" Iso8601.decoder)


changeDecoder : Decoder Change
changeDecoder =
    Decode.map5 Change
        (Decode.field "slug" Decode.string)
        (Decode.field "title" Decode.string)
        (Decode.field "version_number" Decode.int)
        (Decode.field "intent" (Decode.nullable Decode.string))
        (Decode.field "updated_at" Iso8601.decoder)


tagsDecoder : Decoder (List TagRow)
tagsDecoder =
    Decode.field "tags"
        (Decode.list
            (Decode.map3 TagRow
                (Decode.field "slug" Decode.string)
                (Decode.field "description" Decode.string)
                (Decode.field "color" (Decode.nullable Decode.string))
            )
        )
