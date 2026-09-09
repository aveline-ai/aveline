module Page.Welcome exposing (Model, Msg, init, update, view)

{-| The welcome page — ported from `lib/aveline_web/live/welcome_live.ex`
plus the `AvelineWeb.Setup.welcome/1` component it renders
(`lib/aveline_web/components/setup.ex`, design mock B: the vestibule).

Data comes from GET /papi/workspaces/:slug/welcome (fe-workspace
endpoint): the server-built setup prompt, doc/view counts, member
names, the orientation doc, and the backdrop docs.

The "Copy setup prompt" button keeps the LiveView's markup (ids +
`data-target`) but clipboard access needs a port wired in Main.elm —
deferred to the coordinator (see report).

-}

import Api
import Html exposing (Html, a, b, button, code, details, div, em, h1, p, pre, section, span, summary, text)
import Html.Attributes exposing (attribute, class, href, id, rel, target, title, type_)
import Html.Events exposing (onClick)
import Iso8601
import Json.Decode as Decode exposing (Decoder)
import Route
import Session exposing (Session)
import Svg
import Svg.Attributes as SA
import Task
import Time exposing (Posix)
import Ui.Workspace.Format as Format
import Ui.Workspace.Time exposing (relativeTime)



-- MODEL


type alias Model =
    { session : Session
    , slug : String
    , now : Maybe Posix
    , workspaceName : Maybe String
    , data : Status WelcomeData
    , promptCopied : Bool
    }


type Status a
    = Loading
    | Loaded a
    | Failed Api.Error


type alias WelcomeData =
    { prompt : String
    , apiBaseOverride : Maybe String
    , docCount : Int
    , viewCount : Int
    , memberNames : List String
    , orientation : Maybe Orientation
    , backdropDocs : List BackdropDoc
    }


type alias Orientation =
    { slug : String
    , title : String
    }


type alias BackdropDoc =
    { title : String
    , tags : List String
    , actorUsername : Maybe String
    , updatedAt : Posix
    }


init : Session -> String -> ( Model, Cmd Msg )
init session slug =
    ( { session = session
      , slug = slug
      , now = Nothing
      , workspaceName = Nothing
      , data = Loading
      , promptCopied = False
      }
    , Cmd.batch
        [ Task.perform GotNow Time.now
        , Api.get session ("/papi/workspaces/" ++ slug ++ "/welcome") welcomeDecoder GotWelcome
        , Api.get session ("/papi/workspaces/" ++ slug) workspaceNameDecoder GotWorkspaceName
        ]
    )



-- UPDATE


type Msg
    = GotNow Posix
    | GotWelcome (Result Api.Error WelcomeData)
    | GotWorkspaceName (Result Api.Error String)
    | CopyPromptClicked


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotNow now ->
            ( { model | now = Just now }, Cmd.none )

        GotWelcome (Ok data) ->
            ( { model | data = Loaded data }, Cmd.none )

        GotWelcome (Err err) ->
            ( { model | data = Failed err }, Cmd.none )

        GotWorkspaceName (Ok name) ->
            ( { model | workspaceName = Just name }, Cmd.none )

        GotWorkspaceName (Err _) ->
            ( model, Cmd.none )

        CopyPromptClicked ->
            -- The clipboard write itself happens in fe-auth.js's
            -- [data-copy-target] delegation; Elm only owns the label.
            ( { model | promptCopied = True }, Cmd.none )



-- VIEW


view : Model -> Html Msg
view model =
    case model.data of
        Loading ->
            div [ class "welcome-stage welcome-stage-fresh", id "welcome" ] []

        Failed err ->
            div [ class "welcome-stage welcome-stage-fresh", id "welcome" ]
                [ div [ class "welcome-center" ]
                    [ section [ class "welcome-panel welcome-vestibule" ]
                        [ p [ class "welcome-lede" ] [ text (Api.errorMessage err) ] ]
                    ]
                ]

        Loaded data ->
            viewStage model data


viewStage : Model -> WelcomeData -> Html Msg
viewStage model data =
    let
        inhabited =
            not (List.isEmpty data.memberNames)

        stageClass =
            if inhabited then
                "welcome-stage "

            else
                "welcome-stage welcome-stage-fresh"
    in
    div [ class stageClass, id "welcome" ]
        (List.filterMap identity
            [ if inhabited then
                Just (viewBackdrop model data)

              else
                Nothing
            , Just (div [ class "wb-veil", attribute "aria-hidden" "true" ] [])
            , Just (viewCenter model data inhabited)
            ]
        )



-- Backdrop: the workspace's real docs drifting behind the glass panel.


backdropSlots : List ( String, String, String )
backdropSlots =
    [ ( "wb-p1", "wb-tier-1", "" )
    , ( "wb-p4", "wb-tier-1", "wb-drift-b" )
    , ( "wb-p3", "wb-tier-1", "wb-drift-c" )
    , ( "wb-p6", "wb-tier-1", "wb-drift-c" )
    , ( "wb-p2", "wb-tier-2", "wb-drift-b" )
    , ( "wb-p5", "wb-tier-2", "" )
    , ( "wb-p7", "wb-tier-3", "wb-drift-b" )
    , ( "wb-p8", "wb-tier-3", "wb-drift-c" )
    , ( "wb-p9", "wb-tier-3", "" )
    , ( "wb-p10", "wb-tier-3", "wb-drift-b" )
    ]


viewBackdrop : Model -> WelcomeData -> Html Msg
viewBackdrop model data =
    div [ class "wb-backdrop", attribute "aria-hidden" "true" ]
        (List.map2 (viewBackdropCard model)
            (List.take 10 data.backdropDocs)
            backdropSlots
        )


viewBackdropCard : Model -> BackdropDoc -> ( String, String, String ) -> Html Msg
viewBackdropCard model doc ( pos, tier, drift ) =
    div [ class ("wb-card " ++ pos ++ " " ++ tier ++ " " ++ drift) ]
        (List.filterMap identity
            [ Just
                (div [ class "wb-title" ]
                    [ docIcon False
                    , text doc.title
                    ]
                )
            , Just (skeletonLine doc.title 0)
            , Just (skeletonLine doc.title 1)
            , Just (skeletonLine doc.title 2)
            , if List.isEmpty doc.tags then
                Nothing

              else
                Just
                    (div [ class "wb-chips" ]
                        (List.map
                            (\tag -> span [ class "wb-chip" ] [ text tag ])
                            (List.take 2 doc.tags)
                        )
                    )
            , Maybe.map
                (\username ->
                    div [ class "wb-meta" ]
                        [ span [ class ("wb-face " ++ hueClass username) ]
                            [ text (String.left 1 username) ]
                        , text (" " ++ username ++ " edited " ++ relative model doc.updatedAt)
                        ]
                )
                doc.actorUsername
            ]
        )


skeletonLine : String -> Int -> Html msg
skeletonLine docTitle line =
    div
        [ class "wb-line"
        , attribute "style" ("width: " ++ String.fromInt (skeletonWidth docTitle line) ++ "%")
        ]
        []


{-| Deterministic skeleton line widths (55-94%), stable per title/line.
The server uses `:erlang.phash2`; here a plain string hash — same idea,
different specific widths.
-}
skeletonWidth : String -> Int -> Int
skeletonWidth docTitle line =
    55 + modBy 40 (Format.hash (docTitle ++ ":" ++ String.fromInt line))


{-| A muted hue class per person, stable by name (wb-hue-0..4).
-}
hueClass : String -> String
hueClass name =
    "wb-hue-" ++ String.fromInt (modBy 5 (Format.hash name))



-- Center panel


viewCenter : Model -> WelcomeData -> Bool -> Html Msg
viewCenter model data inhabited =
    let
        others =
            data.memberNames
    in
    div [ class "welcome-center" ]
        [ section [ class "welcome-panel welcome-vestibule" ]
            (List.filterMap identity
                [ Just
                    (div [ class "welcome-eyebrow" ]
                        [ span [ class "welcome-spark" ] [ text "●" ]
                        , text (" " ++ model.slug ++ " · aveline")
                        ]
                    )
                , Just (viewHeading model others)
                , Just (viewLede inhabited)
                , if inhabited then
                    Just (viewProof data others)

                  else
                    Nothing
                , Just (viewSetup model data)
                , Maybe.map (viewStart model) data.orientation
                ]
            )
        ]


viewHeading : Model -> List String -> Html Msg
viewHeading model others =
    h1 [ class "welcome-h1" ]
        (text "Welcome to "
            :: em [] [ text (Maybe.withDefault model.slug model.workspaceName) ]
            :: text "."
            :: (if List.isEmpty others then
                    [ Html.br [] []
                    , text "Your team's shared brain starts here."
                    ]

                else
                    []
               )
        )


viewLede : Bool -> Html Msg
viewLede inhabited =
    if inhabited then
        p [ class "welcome-lede" ]
            [ text "This workspace already knows things: decisions, runbooks, tickets. Connect your agent and it inherits all of it, plus everything written next. You review, comment, and steer. About two minutes." ]

    else
        p [ class "welcome-lede" ]
            [ text "Every decision, runbook, and ticket your agents file here compounds. In a month, a new teammate's agent can learn the whole system in one read. It starts with yours. About two minutes." ]


viewProof : WelcomeData -> List String -> Html Msg
viewProof data others =
    div [ class "welcome-proof" ]
        (List.filterMap identity
            [ if List.isEmpty others then
                Nothing

              else
                Just
                    (span [ class "welcome-facepile" ]
                        (List.map
                            (\name ->
                                span [ class ("wb-face welcome-face " ++ hueClass name) ]
                                    [ text (String.left 1 name) ]
                            )
                            (List.take 5 others)
                        )
                    )
            , Just (span [] [ b [] [ text (namesSentence others) ] ])
            , Just (span [ class "welcome-sep" ] [ text "·" ])
            , Just (span [] [ b [] [ text (String.fromInt data.docCount) ], text " docs" ])
            , Just (span [ class "welcome-sep" ] [ text "·" ])
            , Just (span [] [ b [] [ text (String.fromInt data.viewCount) ], text " saved views" ])
            ]
        )


{-| "alice is here", "alice and bob are here", "you're the first one here"
-}
namesSentence : List String -> String
namesSentence names =
    case names of
        [] ->
            "you're the first one here"

        [ a ] ->
            a ++ " is here"

        [ a, b ] ->
            a ++ " and " ++ b ++ " are here"

        many ->
            case List.reverse many of
                last :: rest ->
                    String.join ", " (List.reverse rest) ++ ", and " ++ last ++ " are here"

                [] ->
                    ""


viewSetup : Model -> WelcomeData -> Html Msg
viewSetup model data =
    div [ class "welcome-setup" ]
        [ p [ class "welcome-setup-lead" ]
            [ text "One prompt sets everything up. Paste it into your coding agent: Claude Code, Cursor, and Codex all work." ]
        , button
            [ type_ "button"
            , id "welcome-copy"
            , class "welcome-cta"
            , attribute "data-copy-target" "#welcome-snippet"
            , title "Copy the setup prompt"
            , onClick CopyPromptClicked
            ]
            [ copyIcon
            , span [ class "token-field-copy-label" ]
                [ text
                    (if model.promptCopied then
                        "Copied ✓"

                     else
                        "Copy setup prompt"
                    )
                ]
            ]
        , div [ class "welcome-or", attribute "aria-hidden" "true" ]
            [ span [] [], text "or do it yourself", span [] [] ]
        , div [ class "welcome-steps-box" ]
            [ step True
                "Install the CLI"
                [ a
                    [ href "https://github.com/aveline-ai/cli/releases/latest"
                    , target "_blank"
                    , rel "noopener"
                    , class "welcome-step-line welcome-step-line-link"
                    ]
                    [ text "github.com/aveline-ai/cli/releases/latest ↗" ]
                , div [ class "welcome-step-note" ]
                    [ text "Your agent talks to Aveline through the "
                    , span [ class "mono" ] [ text "aveline" ]
                    , text " CLI. Grab the latest binary for this machine and put it on your PATH."
                    ]
                ]
            , step False
                "Log in"
                [ div [ class "welcome-step-line" ]
                    [ text
                        ("aveline login"
                            ++ (case data.apiBaseOverride of
                                    Just base ->
                                        " --api-url " ++ base

                                    Nothing ->
                                        ""
                               )
                        )
                    ]
                , div [ class "welcome-step-note" ]
                    [ text "Authenticates the CLI as you with your API key. Lost track of yours? Mint a fresh one anytime in "
                    , a [ href (Route.href (Route.Settings model.slug)), class "welcome-step-link" ]
                        [ text "Settings" ]
                    , text "."
                    ]
                ]
            , step False
                "Set your workspace"
                [ div [ class "welcome-step-line" ]
                    [ text ("aveline use-workspace " ++ model.slug) ]
                , div [ class "welcome-step-note" ]
                    [ text "Points every command at "
                    , span [ class "mono" ] [ text model.slug ]
                    , text " by default, so nothing you or your agent runs needs a workspace flag."
                    ]
                ]
            , step False
                "Teach your project"
                [ div [ class "welcome-step-line" ]
                    [ text "CLAUDE.md: start sessions with aveline get-orientation" ]
                , div [ class "welcome-step-note" ]
                    [ text "Add that line to your agent instructions file. Your agent connects the moment it first reads the orientation doc." ]
                ]
            ]
        , pre [ class "welcome-snippet-source", attribute "aria-hidden" "true" ]
            [ code [ id "welcome-snippet" ] [ text data.prompt ] ]
        ]


step : Bool -> String -> List (Html Msg) -> Html Msg
step open titleText body =
    details
        ([ class "welcome-step", attribute "name" "welcome-steps" ]
            ++ (if open then
                    [ attribute "open" "" ]

                else
                    []
               )
        )
        [ summary [ class "welcome-step-title" ] [ text titleText ]
        , div [ class "welcome-step-body" ] body
        ]


viewStart : Model -> Orientation -> Html Msg
viewStart model orientation =
    div [ class "welcome-start" ]
        [ text "Start with "
        , span [ attribute "aria-hidden" "true" ] [ text "→" ]
        , a
            [ href (Route.href (Route.DocShow model.slug orientation.slug))
            , class "welcome-start-doc"
            ]
            [ docIcon True
            , text orientation.title
            ]
        ]


relative : Model -> Posix -> String
relative model t =
    case model.now of
        Just now ->
            relativeTime now t

        Nothing ->
            ""



-- ICONS (exact svgs from setup.ex)


docIcon : Bool -> Html msg
docIcon withFold =
    Svg.svg
        [ SA.viewBox "0 0 16 16"
        , SA.fill "none"
        , SA.stroke "currentColor"
        , SA.strokeWidth "1.3"
        , SA.strokeLinejoin "round"
        ]
        (Svg.path [ SA.d "M4 2h5.5L13 5.5V13a1 1 0 01-1 1H4a1 1 0 01-1-1V3a1 1 0 011-1z" ] []
            :: (if withFold then
                    [ Svg.path [ SA.d "M9.5 2v3.5H13" ] [] ]

                else
                    []
               )
        )


copyIcon : Html msg
copyIcon =
    Svg.svg
        [ SA.viewBox "0 0 16 16"
        , SA.fill "none"
        , SA.stroke "currentColor"
        , SA.strokeWidth "1.4"
        , SA.strokeLinecap "round"
        ]
        [ Svg.rect [ SA.x "5.5", SA.y "5.5", SA.width "8", SA.height "8", SA.rx "1.5" ] []
        , Svg.path [ SA.d "M10.5 3.5v-.75A1.25 1.25 0 009.25 1.5h-6A1.25 1.25 0 002 2.75v6A1.25 1.25 0 003.25 10H4" ] []
        ]



-- DECODERS


welcomeDecoder : Decoder WelcomeData
welcomeDecoder =
    Decode.map7 WelcomeData
        (Decode.field "prompt" Decode.string)
        (Decode.field "api_base_override" (Decode.nullable Decode.string))
        (Decode.field "doc_count" Decode.int)
        (Decode.field "view_count" Decode.int)
        (Decode.field "member_names" (Decode.list Decode.string))
        (Decode.field "orientation" (Decode.nullable orientationDecoder))
        (Decode.field "backdrop_docs" (Decode.list backdropDocDecoder))


orientationDecoder : Decoder Orientation
orientationDecoder =
    Decode.map2 Orientation
        (Decode.field "slug" Decode.string)
        (Decode.field "title" Decode.string)


backdropDocDecoder : Decoder BackdropDoc
backdropDocDecoder =
    Decode.map4 BackdropDoc
        (Decode.field "title" Decode.string)
        (Decode.field "tags" (Decode.list Decode.string))
        (Decode.field "actor_username" (Decode.nullable Decode.string))
        (Decode.field "updated_at" Iso8601.decoder)


workspaceNameDecoder : Decoder String
workspaceNameDecoder =
    Decode.at [ "workspace", "name" ] Decode.string
