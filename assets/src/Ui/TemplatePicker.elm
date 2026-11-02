module Ui.TemplatePicker exposing
    ( Model
    , Msg
    , Template
    , defaultTemplate
    , init
    , selected
    , update
    , view
    )

{-| The workspace-template picker shared by the signup form and the
new-workspace form: three selectable cards fed by GET /papi/templates
(open endpoint, no login needed).

It never blocks the host form. While the list loads, or if it fails,
`selected` still answers with the recommended template's name
(`defaultTemplate`), so the host can submit regardless. Once the list
arrives the server's recommended entry is preselected.

`update` is pure: the only command this component ever issues is the
fetch in `init`.

-}

import Api
import Html exposing (Html, button, div, span, text)
import Html.Attributes exposing (attribute, class, classList, type_)
import Html.Events exposing (onClick)
import Json.Decode as Decode exposing (Decoder)
import Session exposing (Session)


type alias Template =
    { name : String
    , title : String
    , summary : String
    , recommended : Bool
    , tagCount : Int
    , viewCount : Int
    , docCount : Int
    }


type alias Model =
    { templates : Status
    , selected : String
    }


type Status
    = Loading
    | Loaded (List Template)
    | Failed


{-| The template a workspace gets when the list never arrives: the one
the server marks recommended today.
-}
defaultTemplate : String
defaultTemplate =
    "autonomous-dev"


type Msg
    = GotTemplates (Result Api.Error (List Template))
    | Selected String


init : Session -> ( Model, Cmd Msg )
init session =
    ( { templates = Loading, selected = defaultTemplate }
    , Api.get session "/papi/templates" templatesDecoder GotTemplates
    )


templatesDecoder : Decoder (List Template)
templatesDecoder =
    Decode.field "templates"
        (Decode.list
            (Decode.map7 Template
                (Decode.field "name" Decode.string)
                (Decode.field "title" Decode.string)
                (Decode.field "summary" Decode.string)
                (Decode.field "recommended" Decode.bool)
                (Decode.field "tag_count" Decode.int)
                (Decode.field "view_count" Decode.int)
                (Decode.field "doc_count" Decode.int)
            )
        )


update : Msg -> Model -> Model
update msg model =
    case msg of
        GotTemplates (Ok templates) ->
            { model
                | templates = Loaded templates
                , selected =
                    templates
                        |> List.filter .recommended
                        |> List.head
                        |> Maybe.map .name
                        |> Maybe.withDefault
                            (List.head templates
                                |> Maybe.map .name
                                |> Maybe.withDefault model.selected
                            )
            }

        GotTemplates (Err _) ->
            { model | templates = Failed }

        Selected name ->
            { model | selected = name }


{-| The name to post as `template`.
-}
selected : Model -> String
selected model =
    model.selected


view : Model -> Html Msg
view model =
    div [ class "tpl-picker" ]
        (div [ class "auth-label" ] [ text "Start from" ]
            :: (case model.templates of
                    Loading ->
                        [ div [ class "tpl-note" ] [ text "Loading templates…" ] ]

                    Failed ->
                        [ div [ class "tpl-note" ]
                            [ text "Couldn't load the template list. You'll start from the recommended setup, Autonomous dev." ]
                        ]

                    Loaded templates ->
                        [ div [ class "tpl-cards", attribute "role" "radiogroup", attribute "aria-label" "Workspace template" ]
                            (List.map (viewCard model.selected) templates)
                        ]
               )
        )


viewCard : String -> Template -> Html Msg
viewCard current template =
    let
        isSelected =
            template.name == current
    in
    button
        [ type_ "button"
        , classList [ ( "tpl-card", True ), ( "tpl-card-selected", isSelected ) ]
        , attribute "role" "radio"
        , attribute "aria-checked"
            (if isSelected then
                "true"

             else
                "false"
            )
        , onClick (Selected template.name)
        ]
        [ div [ class "tpl-card-head" ]
            (span [ class "tpl-card-title" ] [ text template.title ]
                :: (if template.recommended then
                        [ span [ class "tpl-badge" ] [ text "Recommended" ] ]

                    else
                        []
                   )
            )
        , div [ class "tpl-card-summary" ] [ text template.summary ]
        , div [ class "tpl-card-counts" ] [ text (countsLine template) ]
        ]


{-| "18 tags · 3 boards · 1 doc" — zero counts dropped; the blank
template (nothing but the orientation doc) says so in words.
-}
countsLine : Template -> String
countsLine template =
    let
        parts =
            List.filterMap identity
                [ plural template.tagCount "tag" "tags"
                , plural template.viewCount "board" "boards"
                , plural template.docCount "doc" "docs"
                ]
    in
    if template.name == "blank" || List.isEmpty parts then
        "Just the orientation doc"

    else
        String.join " · " parts


plural : Int -> String -> String -> Maybe String
plural n one many =
    if n <= 0 then
        Nothing

    else if n == 1 then
        Just ("1 " ++ one)

    else
        Just (String.fromInt n ++ " " ++ many)
