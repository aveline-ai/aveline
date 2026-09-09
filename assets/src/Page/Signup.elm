module Page.Signup exposing (Model, Msg, init, update, view)

{-| Ported from lib/aveline\_web/live/signup\_live.ex by the fe-auth
page agent. Keep the exposed signature exactly as-is; Main.elm
depends on it.

Token-only signup: pick a username + name your first workspace; the API
key is pre-generated (GET /papi/signup/preview-token) and shown in the
form behind a copy gate. Submit hits POST /papi/signup (which mirrors
the LiveView's validation order and messages), then logs in via
POST /papi/session and does a full page load to /w/:slug/welcome so the
fresh session cookie applies everywhere.

Already-signed-in visitors bounce into their first workspace (or
/new-workspace), mirroring the LiveView mount. A stale cookie (401 from
/papi/workspaces) drops back to the form instead of looping.

-}

import Api
import Auth.Ui
import Browser.Navigation as Nav
import Html exposing (Html, a, button, div, form, input, label, text)
import Html.Attributes exposing (attribute, autocomplete, autofocus, class, disabled, for, href, id, name, placeholder, spellcheck, style, type_, value)
import Html.Events exposing (onInput, onSubmit)
import Json.Decode as Decode
import Json.Encode as Encode
import Route
import Session exposing (Session)
import Ui.AuthBg


type alias Model =
    { session : Session
    , redirecting : Bool
    , username : String
    , workspaceName : String
    , previewToken : Maybe String
    , copied : Bool
    , error : Maybe String
    , submitting : Bool
    }


type Msg
    = GotWorkspaces (Result Api.Error (List String))
    | GotPreviewToken (Result Api.Error String)
    | UsernameChanged String
    | WorkspaceNameChanged String
    | CopyClicked
    | TokenCopied
    | Submitted
    | GotSignup (Result Api.Error { slug : String, token : String })
    | GotLogin String (Result Api.Error ())


init : Session -> ( Model, Cmd Msg )
init session =
    let
        model =
            { session = session
            , redirecting = False
            , username = ""
            , workspaceName = ""
            , previewToken = Nothing
            , copied = False
            , error = Nothing
            , submitting = False
            }
    in
    case session.user of
        Just _ ->
            -- Already signed in — bounce into a workspace (or the
            -- new-workspace flow). Resolved through /papi/workspaces so
            -- a stale cookie falls back to the signup form.
            ( { model | redirecting = True }
            , Api.get session "/papi/workspaces" workspacesDecoder GotWorkspaces
            )

        Nothing ->
            ( model, fetchPreviewToken session )


fetchPreviewToken : Session -> Cmd Msg
fetchPreviewToken session =
    Api.get session
        "/papi/signup/preview-token"
        (Decode.field "token" Decode.string)
        GotPreviewToken


workspacesDecoder : Decode.Decoder (List String)
workspacesDecoder =
    Decode.field "workspaces" (Decode.list (Decode.field "slug" Decode.string))


signupDecoder : Decode.Decoder { slug : String, token : String }
signupDecoder =
    Decode.map2 (\slug token -> { slug = slug, token = token })
        (Decode.at [ "workspace", "slug" ] Decode.string)
        (Decode.field "token" Decode.string)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotWorkspaces (Ok slugs) ->
            ( model
            , Nav.load <|
                case slugs of
                    slug :: _ ->
                        Route.href (Route.Home slug)

                    [] ->
                        Route.href Route.WorkspaceNew
            )

        GotWorkspaces (Err _) ->
            -- Stale cookie (deleted account) or transient failure —
            -- drop back to the signup form instead of looping.
            ( { model | redirecting = False }
            , fetchPreviewToken model.session
            )

        GotPreviewToken (Ok token) ->
            ( { model | previewToken = Just token }, Cmd.none )

        GotPreviewToken (Err err) ->
            ( { model | error = Just (Api.errorMessage err) }, Cmd.none )

        UsernameChanged raw ->
            -- Pure input capture — no validation messages until submit.
            -- Any prior error clears once the user starts editing again.
            ( { model
                | username = raw |> String.trim |> String.toLower
                , error = Nothing
              }
            , Cmd.none
            )

        WorkspaceNameChanged raw ->
            ( { model | workspaceName = raw, error = Nothing }, Cmd.none )

        CopyClicked ->
            ( { model | copied = True }, Cmd.none )

        TokenCopied ->
            ( { model | copied = True }, Cmd.none )

        Submitted ->
            if model.submitting then
                ( model, Cmd.none )

            else
                -- All checks (username → workspace → copy, then the
                -- account insert) run server-side in POST /papi/signup,
                -- preserving the LiveView's exact ordering and messages.
                ( { model | submitting = True }
                , Api.post model.session
                    "/papi/signup"
                    (Encode.object
                        [ ( "username", Encode.string model.username )
                        , ( "workspace_name", Encode.string model.workspaceName )
                        , ( "token", Encode.string (Maybe.withDefault "" model.previewToken) )
                        , ( "copied", Encode.bool model.copied )
                        ]
                    )
                    signupDecoder
                    GotSignup
                )

        GotSignup (Ok result) ->
            -- One door for everyone: auto-login and land on welcome
            -- (the key was already shown, with its copy gate, above).
            ( model
            , Api.post model.session
                "/papi/session"
                (Encode.object [ ( "token", Encode.string result.token ) ])
                (Decode.succeed ())
                (GotLogin ("/w/" ++ result.slug ++ "/welcome"))
            )

        GotSignup (Err err) ->
            ( { model | submitting = False, error = Just (Api.errorMessage err) }
            , Cmd.none
            )

        GotLogin next (Ok ()) ->
            -- Full page load so the fresh session cookie applies
            -- everywhere.
            ( model, Nav.load next )

        GotLogin _ (Err err) ->
            ( { model | submitting = False, error = Just (Api.errorMessage err) }
            , Cmd.none
            )


view : Model -> Html Msg
view model =
    if model.redirecting then
        text ""

    else
        viewForm model


viewForm : Model -> Html Msg
viewForm model =
    let
        canSubmit =
            String.trim model.username
                /= ""
                && String.trim model.workspaceName
                /= ""
    in
    div [ class "auth-shell" ]
        (Ui.AuthBg.split
            ++ [ div [ class "auth-card auth-card-spare" ]
                    [ Auth.Ui.brand
                    , form [ class "auth-form", id "signup-form", onSubmit Submitted ]
                        [ label [ class "auth-label", for "username" ] [ text "Username" ]
                        , input
                            [ type_ "text"
                            , name "username"
                            , id "username"
                            , value model.username
                            , autocomplete False
                            , attribute "autocapitalize" "none"
                            , attribute "autocorrect" "off"
                            , spellcheck False
                            , placeholder "arie"
                            , class "auth-input auth-input-hero"
                            , autofocus True
                            , onInput UsernameChanged
                            ]
                            []
                        , label [ class "auth-label", for "ws-name", style "margin-top" "16px" ]
                            [ text "Workspace name" ]
                        , input
                            [ type_ "text"
                            , name "workspace_name"
                            , id "ws-name"
                            , value model.workspaceName
                            , autocomplete False
                            , placeholder "Aveline AI"
                            , class "auth-input auth-input-hero"
                            , onInput WorkspaceNameChanged
                            ]
                            []
                        , label [ class "auth-label", style "margin-top" "18px" ] [ text "Your API key" ]
                        , Auth.Ui.tokenField
                            { token = Maybe.withDefault "" model.previewToken
                            , copied = model.copied
                            , onCopy = CopyClicked
                            , onNativeCopy = TokenCopied
                            }
                        , Auth.Ui.copyHint
                        , button [ type_ "submit", class "auth-submit", disabled (not canSubmit) ]
                            [ text "Sign up" ]
                        , Auth.Ui.errorLine model.error
                        ]
                    , div [ class "auth-footer" ]
                        [ text "Already have a token? "
                        , a [ href (Route.href Route.Login), class "auth-link" ] [ text "Log in" ]
                        ]
                    ]
               ]
        )
