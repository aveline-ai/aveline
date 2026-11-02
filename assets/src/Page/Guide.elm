module Page.Guide exposing (Model, Msg, init, update, view)

{-| "How Aveline works" — Aveline's own, versioned guide, read inside a
workspace. Elm-only (no LiveView counterpart). Keep the exposed
signature exactly as-is; Main.elm depends on it.

Data comes from GET /papi/guide (open endpoint): version, changelog
and the guide's blocks, rendered with the same renderer the doc page
uses (`Doc.BlockView`), minus the gutter and comments. The link to
this workspace's orientation doc rides on GET /papi/workspaces/:slug/home,
which already echoes the orientation card; if that call fails the link
is simply absent.

-}

import Api
import Doc.BlockView as BlockView
import Doc.Blocks as Blocks exposing (Block)
import Html exposing (Html, a, article, details, div, h1, header, li, p, span, summary, text, ul)
import Html.Attributes exposing (class, href)
import Json.Decode as Decode exposing (Decoder)
import Route
import Session exposing (Session)



-- MODEL


type alias Model =
    { session : Session
    , slug : String
    , guide : Status Guide
    , orientationSlug : Maybe String
    }


type Status a
    = Loading
    | Loaded a
    | Failed Api.Error


type alias Guide =
    { version : Int
    , changelog : List ChangelogEntry
    , blocks : List Block
    }


type alias ChangelogEntry =
    { version : Int
    , line : String
    }


init : Session -> String -> ( Model, Cmd Msg )
init session slug =
    ( { session = session
      , slug = slug
      , guide = Loading
      , orientationSlug = Nothing
      }
    , Cmd.batch
        [ Api.get session "/papi/guide" guideDecoder GotGuide
        , Api.get session ("/papi/workspaces/" ++ slug ++ "/home") orientationSlugDecoder GotOrientation
        ]
    )



-- UPDATE


type Msg
    = GotGuide (Result Api.Error Guide)
    | GotOrientation (Result Api.Error (Maybe String))


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotGuide (Ok guide) ->
            ( { model | guide = Loaded guide }, Cmd.none )

        GotGuide (Err err) ->
            ( { model | guide = Failed err }, Cmd.none )

        GotOrientation (Ok slug) ->
            ( { model | orientationSlug = slug }, Cmd.none )

        GotOrientation (Err _) ->
            -- The link is a nicety; the guide reads fine without it.
            ( model, Cmd.none )



-- VIEW


view : Model -> Html Msg
view model =
    div [ class "doc-layout" ]
        [ case model.guide of
            Loading ->
                text ""

            Failed err ->
                div [ class "empty" ] [ text (Api.errorMessage err) ]

            Loaded guide ->
                viewGuide model guide
        ]


viewGuide : Model -> Guide -> Html Msg
viewGuide model guide =
    div [ class "doc-article guide-article" ]
        [ header [ class "article-header" ]
            [ h1 [ class "article-title" ] [ text "How Aveline works" ]
            , p [ class "guide-lede" ]
                (List.concat
                    [ [ text ("Aveline's own guide, version " ++ String.fromInt guide.version ++ ". ")
                      , text "Your team's orientation doc is the authority on how this workspace works."
                      ]
                    , case model.orientationSlug of
                        Just slug ->
                            [ text " "
                            , a [ href (Route.href (Route.DocShow model.slug slug)), class "guide-link" ]
                                [ text "Read the orientation doc →" ]
                            ]

                        Nothing ->
                            []
                    ]
                )
            , viewChangelog guide.changelog
            ]
        , article [ class "prose" ]
            [ div [ class "blocks" ]
                (List.map (BlockView.view (blockConfig model)) guide.blocks)
            ]
        ]


viewChangelog : List ChangelogEntry -> Html Msg
viewChangelog entries =
    if List.isEmpty entries then
        text ""

    else
        details [ class "guide-changelog" ]
            [ summary [] [ text "What changed" ]
            , ul []
                (List.map
                    (\entry ->
                        li []
                            [ span [ class "guide-changelog-version" ]
                                [ text ("v" ++ String.fromInt entry.version) ]
                            , text (" " ++ entry.line)
                            ]
                    )
                    entries
                )
            ]


{-| Read-only: no gutter, plain tag chips, charts shown as their echoed
rows.
-}
blockConfig : Model -> BlockView.Config Msg
blockConfig model =
    { slug = model.slug
    , gutter = always (text "")
    , tagChip = \tag -> span [ class "chip chip-tag" ] [ text tag ]
    , chart = BlockView.chartStatic
    }



-- DECODERS


guideDecoder : Decoder Guide
guideDecoder =
    Decode.field "guide"
        (Decode.map3 Guide
            (Decode.field "version" Decode.int)
            (Decode.field "changelog" (Decode.list changelogDecoder))
            (Decode.field "blocks" (Decode.list Blocks.blockDecoder))
        )


changelogDecoder : Decoder ChangelogEntry
changelogDecoder =
    Decode.map2 ChangelogEntry
        (Decode.field "version" Decode.int)
        (Decode.field "line" Decode.string)


orientationSlugDecoder : Decoder (Maybe String)
orientationSlugDecoder =
    Decode.field "orientation" (Decode.nullable (Decode.field "slug" Decode.string))
