module Page.WorkspaceNew exposing (Model, Msg, init, update, view)

{-| Ported from lib/aveline\_web/live/workspace\_new\_live.ex by the
fe-auth page agent. Keep the exposed signature exactly as-is; Main.elm
depends on it.

Create-a-workspace form. Pick a name; the slug preview is derived
client-side with the same rules as Aveline.Slug.derive. Creation goes
through the existing POST /papi/workspaces (which adds the creator as
first member), then a full load into the new workspace. Signed-out
visitors bounce to /login, mirroring the LiveView mount.

-}

import Api
import Auth.Ui
import Auth.Validate
import Browser.Navigation as Nav
import Html exposing (Html, button, code, div, form, input, label, span, text)
import Html.Attributes exposing (autocomplete, autofocus, class, disabled, for, id, name, placeholder, style, type_, value)
import Html.Events exposing (onInput, onSubmit)
import Json.Decode as Decode
import Json.Encode as Encode
import Route
import Session exposing (Session)


type alias Model =
    { session : Session
    , redirecting : Bool
    , name : String
    , error : Maybe String
    , submitting : Bool
    }


type Msg
    = NameChanged String
    | Submitted
    | GotCreate (Result Api.Error String)


init : Session -> ( Model, Cmd Msg )
init session =
    let
        model =
            { session = session
            , redirecting = False
            , name = ""
            , error = Nothing
            , submitting = False
            }
    in
    case session.user of
        Nothing ->
            -- "Sign in first." — bounce to the login form.
            ( { model | redirecting = True }, Nav.load (Route.href Route.Login) )

        Just _ ->
            ( model, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NameChanged raw ->
            ( { model | name = raw, error = Nothing }, Cmd.none )

        Submitted ->
            let
                trimmed =
                    String.trim model.name
            in
            if model.submitting then
                ( model, Cmd.none )

            else if trimmed == "" then
                ( { model | error = Just "Pick a name." }, Cmd.none )

            else if String.length trimmed > 80 then
                ( { model | error = Just "Too long (max 80 characters)." }, Cmd.none )

            else
                case Auth.Validate.deriveSlug trimmed of
                    Nothing ->
                        ( { model | error = Just "Name needs at least one letter or digit." }
                        , Cmd.none
                        )

                    Just slug ->
                        ( { model | submitting = True }
                        , Api.post model.session
                            "/papi/workspaces"
                            (Encode.object
                                [ ( "name", Encode.string trimmed )
                                , ( "slug", Encode.string slug )
                                ]
                            )
                            (Decode.at [ "workspace", "slug" ] Decode.string)
                            GotCreate
                        )

        GotCreate (Ok slug) ->
            -- "Workspace created." — full load into the new workspace.
            ( model, Nav.load ("/w/" ++ slug) )

        GotCreate (Err err) ->
            ( { model
                | submitting = False
                , error = Just (createError err)
              }
            , Cmd.none
            )


{-| Same message mapping as the LiveView's submit error handling.
-}
createError : Api.Error -> String
createError err =
    case err of
        Api.ApiError e ->
            if e.code == "slug_taken" then
                "That name is already in use. Pick a different one."

            else
                "Couldn't create — check the name."

        _ ->
            "Couldn't create the workspace."


view : Model -> Html Msg
view model =
    if model.redirecting then
        text ""

    else
        viewForm model


viewForm : Model -> Html Msg
viewForm model =
    let
        trimmed =
            String.trim model.name

        slugPreview =
            if trimmed /= "" then
                Auth.Validate.deriveSlug trimmed

            else
                Nothing

        inputClass =
            "auth-input auth-input-hero "
                ++ (case model.error of
                        Just _ ->
                            "auth-input-error"

                        Nothing ->
                            ""
                   )
    in
    div [ class "auth-shell" ]
        [ div [ class "auth-card auth-card-spare" ]
            [ Auth.Ui.brand
            , form [ class "auth-form", onSubmit Submitted ]
                [ label [ class "auth-label", for "ws-name" ] [ text "Workspace name" ]
                , input
                    [ type_ "text"
                    , name "name"
                    , id "ws-name"
                    , value model.name
                    , autocomplete False
                    , placeholder "Aveline AI"
                    , class inputClass
                    , autofocus True
                    , onInput NameChanged
                    ]
                    []
                , div [ class "auth-hint", style "min-height" "18px" ]
                    (case model.error of
                        Just err ->
                            [ span [ class "auth-error", style "margin" "0" ] [ text err ] ]

                        Nothing ->
                            [ text "aveline.ai/w/"
                            , code [] [ text (Maybe.withDefault "" slugPreview) ]
                            ]
                    )
                , button [ type_ "submit", class "auth-submit", disabled (trimmed == "") ]
                    [ text "Create" ]
                ]
            ]
        ]
