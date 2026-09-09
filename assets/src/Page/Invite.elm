module Page.Invite exposing (Model, Msg, init, update, view)

{-| Ported from lib/aveline\_web/live/invite\_live.ex by the fe-auth
page agent. Keep the exposed signature exactly as-is; Main.elm
depends on it.

Landing page for invite links — `/invite/:code`:

  - Invalid/revoked code: "Invite link expired" card.
  - Signed in: a "Join {workspace}" confirm (POST
    /papi/invites/:code/accept), then a full load into /w/:slug.
    Already-members bounce straight in.
  - Signed out: signup form (username + pre-generated API key behind a
    copy gate), toggleable to a paste-your-token sign-in. Both paths end
    in POST /papi/session + a full page load so the fresh cookie applies
    everywhere.

The LiveView's per-keystroke "Username taken." check is reproduced with
local format validation plus a 250ms-debounced GET
/papi/signup/username-status.

-}

import Api
import Auth.Ui
import Auth.Validate
import Browser.Navigation as Nav
import Html exposing (Html, button, div, form, h1, input, label, p, strong, text)
import Html.Attributes exposing (attribute, autocomplete, autofocus, class, for, id, name, placeholder, spellcheck, style, type_, value)
import Html.Events exposing (onClick, onInput, onSubmit)
import Json.Decode as Decode
import Json.Encode as Encode
import Process
import Session exposing (Session)
import Task
import Ui.AuthBg


type alias Model =
    { session : Session
    , code : String
    , state : State
    }


type State
    = Loading
    | Invalid
    | SignedIn { workspace : Workspace, error : Maybe String }
    | SignupForm FormState


type alias Workspace =
    { slug : String
    , name : String
    }


type alias FormState =
    { workspace : Workspace
    , hasToken : Bool
    , username : String
    , loginToken : String
    , previewToken : Maybe String
    , copied : Bool
    , error : Maybe String
    , checkSeq : Int
    , submitting : Bool
    }


type Msg
    = GotInvite (Result Api.Error { workspace : Workspace, alreadyMember : Bool })
    | GotPreviewToken (Result Api.Error String)
    | Accept
    | GotAccept (Result Api.Error Workspace)
    | ToggleHasToken
    | UsernameChanged String
    | DebouncedCheck Int
    | GotUsernameStatus String (Result Api.Error Bool)
    | LoginTokenChanged String
    | SubmitLogin
    | GotLoginSession (Result Api.Error ())
    | CopyClicked
    | TokenCopied
    | SubmitSignup
    | GotSignup (Result Api.Error { slug : String, token : String })
    | GotSignupSession String (Result Api.Error ())


init : Session -> String -> ( Model, Cmd Msg )
init session code =
    ( { session = session, code = code, state = Loading }
    , Api.get session ("/papi/invites/" ++ code) inviteDecoder GotInvite
    )


inviteDecoder : Decode.Decoder { workspace : Workspace, alreadyMember : Bool }
inviteDecoder =
    Decode.map2 (\ws member -> { workspace = ws, alreadyMember = member })
        (Decode.field "workspace" workspaceDecoder)
        (Decode.field "already_member" Decode.bool)


workspaceDecoder : Decode.Decoder Workspace
workspaceDecoder =
    Decode.map2 Workspace
        (Decode.field "slug" Decode.string)
        (Decode.field "name" Decode.string)


signupDecoder : Decode.Decoder { slug : String, token : String }
signupDecoder =
    Decode.map2 (\slug token -> { slug = slug, token = token })
        (Decode.at [ "workspace", "slug" ] Decode.string)
        (Decode.field "token" Decode.string)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotInvite (Ok invite) ->
            if invite.alreadyMember then
                -- "You're already a member." — straight into the
                -- workspace, like the LiveView's push_navigate.
                ( model, Nav.load ("/w/" ++ invite.workspace.slug) )

            else
                case model.session.user of
                    Just _ ->
                        ( { model | state = SignedIn { workspace = invite.workspace, error = Nothing } }
                        , Cmd.none
                        )

                    Nothing ->
                        ( { model
                            | state =
                                SignupForm
                                    { workspace = invite.workspace
                                    , hasToken = False
                                    , username = ""
                                    , loginToken = ""
                                    , previewToken = Nothing
                                    , copied = False
                                    , error = Nothing
                                    , checkSeq = 0
                                    , submitting = False
                                    }
                          }
                        , Api.get model.session
                            "/papi/signup/preview-token"
                            (Decode.field "token" Decode.string)
                            GotPreviewToken
                        )

        GotInvite (Err _) ->
            ( { model | state = Invalid }, Cmd.none )

        GotPreviewToken result ->
            updateForm model
                (\fs ->
                    case result of
                        Ok token ->
                            ( { fs | previewToken = Just token }, Cmd.none )

                        Err err ->
                            ( { fs | error = Just (Api.errorMessage err) }, Cmd.none )
                )

        Accept ->
            case model.state of
                SignedIn signedIn ->
                    ( model
                    , Api.post model.session
                        ("/papi/invites/" ++ model.code ++ "/accept")
                        (Encode.object [])
                        (Decode.field "workspace" workspaceDecoder)
                        GotAccept
                    )

                _ ->
                    ( model, Cmd.none )

        GotAccept (Ok workspace) ->
            ( model, Nav.load ("/w/" ++ workspace.slug) )

        GotAccept (Err err) ->
            case model.state of
                SignedIn signedIn ->
                    ( { model | state = SignedIn { signedIn | error = Just (Api.errorMessage err) } }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        ToggleHasToken ->
            updateForm model
                (\fs -> ( { fs | hasToken = not fs.hasToken, error = Nothing }, Cmd.none ))

        UsernameChanged raw ->
            updateForm model
                (\fs ->
                    let
                        username =
                            Auth.Validate.normalizeUsername raw

                        localError =
                            Auth.Validate.checkUsername Auth.Validate.InviteContext username

                        seq =
                            fs.checkSeq + 1
                    in
                    ( { fs | username = username, error = localError, checkSeq = seq }
                    , -- Format is fine locally — debounce the DB-backed
                      -- "Username taken." check (phx-debounce="250").
                      if localError == Nothing && username /= "" then
                        Process.sleep 250 |> Task.perform (\_ -> DebouncedCheck seq)

                      else
                        Cmd.none
                    )
                )

        DebouncedCheck seq ->
            case model.state of
                SignupForm fs ->
                    if seq == fs.checkSeq && fs.username /= "" then
                        ( model
                        , Api.get model.session
                            ("/papi/signup/username-status?username=" ++ fs.username)
                            (Decode.field "taken" Decode.bool)
                            (GotUsernameStatus fs.username)
                        )

                    else
                        ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        GotUsernameStatus username result ->
            updateForm model
                (\fs ->
                    if username == fs.username && fs.error == Nothing && result == Ok True then
                        ( { fs | error = Just "Username taken." }, Cmd.none )

                    else
                        ( fs, Cmd.none )
                )

        LoginTokenChanged raw ->
            updateForm model (\fs -> ( { fs | loginToken = raw }, Cmd.none ))

        SubmitLogin ->
            updateForm model
                (\fs ->
                    if fs.submitting then
                        ( fs, Cmd.none )

                    else
                        ( { fs | submitting = True }
                        , Api.post model.session
                            "/papi/session"
                            (Encode.object [ ( "token", Encode.string (String.trim fs.loginToken) ) ])
                            (Decode.succeed ())
                            GotLoginSession
                        )
                )

        GotLoginSession (Ok ()) ->
            -- Mirrors POST /login?next=/invite/:code — the full reload
            -- re-runs the invite lookup with the fresh cookie and lands
            -- on the "Join {workspace}" confirm.
            ( model, Nav.load ("/invite/" ++ model.code) )

        GotLoginSession (Err err) ->
            updateForm model
                (\fs ->
                    ( { fs | submitting = False, error = Just (Api.errorMessage err) }, Cmd.none )
                )

        CopyClicked ->
            updateForm model (\fs -> ( { fs | copied = True }, Cmd.none ))

        TokenCopied ->
            updateForm model (\fs -> ( { fs | copied = True }, Cmd.none ))

        SubmitSignup ->
            updateForm model
                (\fs ->
                    if fs.submitting then
                        ( fs, Cmd.none )

                    else
                        -- Username → copy checks (and messages) run
                        -- server-side in POST /papi/signup, preserving
                        -- the LiveView's exact ordering.
                        ( { fs | submitting = True }
                        , Api.post model.session
                            "/papi/signup"
                            (Encode.object
                                [ ( "username", Encode.string fs.username )
                                , ( "invite_code", Encode.string model.code )
                                , ( "token", Encode.string (Maybe.withDefault "" fs.previewToken) )
                                , ( "copied", Encode.bool fs.copied )
                                ]
                            )
                            signupDecoder
                            GotSignup
                        )
                )

        GotSignup (Ok result) ->
            -- Account exists and the token is in the DB — log in with
            -- it, then a full load into the workspace welcome.
            ( model
            , Api.post model.session
                "/papi/session"
                (Encode.object [ ( "token", Encode.string result.token ) ])
                (Decode.succeed ())
                (GotSignupSession ("/w/" ++ result.slug ++ "/welcome"))
            )

        GotSignup (Err err) ->
            updateForm model
                (\fs ->
                    ( { fs | submitting = False, error = Just (Api.errorMessage err) }, Cmd.none )
                )

        GotSignupSession next (Ok ()) ->
            ( model, Nav.load next )

        GotSignupSession _ (Err err) ->
            updateForm model
                (\fs ->
                    ( { fs | submitting = False, error = Just (Api.errorMessage err) }, Cmd.none )
                )


updateForm : Model -> (FormState -> ( FormState, Cmd Msg )) -> ( Model, Cmd Msg )
updateForm model step =
    case model.state of
        SignupForm fs ->
            let
                ( newFs, cmd ) =
                    step fs
            in
            ( { model | state = SignupForm newFs }, cmd )

        _ ->
            ( model, Cmd.none )



-- VIEW


view : Model -> Html Msg
view model =
    case model.state of
        Loading ->
            text ""

        Invalid ->
            viewInvalid

        SignedIn signedIn ->
            viewSignedIn model.session signedIn

        SignupForm fs ->
            viewSignup fs


shell : List (Html Msg) -> Html Msg
shell cardChildren =
    div [ class "auth-shell" ]
        (Ui.AuthBg.split
            ++ [ div [ class "auth-card auth-card-spare" ] (Auth.Ui.brand :: cardChildren) ]
        )


viewInvalid : Html Msg
viewInvalid =
    shell
        [ h1 [ class "auth-title", style "text-align" "center" ] [ text "Invite link expired" ]
        , p [ class "auth-subtitle", style "text-align" "center" ]
            [ text "This invite link is no longer valid. Ask whoever sent it to share a fresh one." ]
        ]


viewSignedIn : Session -> { workspace : Workspace, error : Maybe String } -> Html Msg
viewSignedIn session signedIn =
    let
        username =
            session.user |> Maybe.map .username |> Maybe.withDefault ""
    in
    shell
        [ p [ class "auth-subtitle", style "text-align" "center", style "margin-bottom" "24px" ]
            [ text "You've been invited to "
            , strong [] [ text signedIn.workspace.name ]
            , text ". You're signed in as "
            , strong [] [ text username ]
            , text "."
            ]
        , button [ onClick Accept, class "auth-submit" ]
            [ text ("Join " ++ signedIn.workspace.name) ]
        , Auth.Ui.errorLine signedIn.error
        ]


viewSignup : FormState -> Html Msg
viewSignup fs =
    shell
        [ p [ class "auth-subtitle", style "text-align" "center", style "margin-bottom" "24px" ]
            [ text "You've been invited to "
            , strong [] [ text fs.workspace.name ]
            , text ". "
            , text
                (if fs.hasToken then
                    "Sign in with your API key to accept."

                 else
                    "Pick a username and you're in."
                )
            ]
        , if fs.hasToken then
            viewTokenForm fs

          else
            viewSignupForm fs
        , div [ class "auth-footer" ]
            (if fs.hasToken then
                [ text "New to Aveline? "
                , button [ type_ "button", onClick ToggleHasToken, class "auth-link" ]
                    [ text "Create an account" ]
                ]

             else
                [ text "Already have a token? "
                , button [ type_ "button", onClick ToggleHasToken, class "auth-link" ]
                    [ text "Sign in instead" ]
                ]
            )
        ]


viewTokenForm : FormState -> Html Msg
viewTokenForm fs =
    form [ class "auth-form", id "invite-login-form", onSubmit SubmitLogin ]
        [ label [ class "auth-label", for "token" ] [ text "Your API key" ]
        , input
            [ type_ "password"
            , name "token"
            , id "token"
            , autocomplete False
            , attribute "autocapitalize" "none"
            , attribute "autocorrect" "off"
            , spellcheck False
            , placeholder "avl_…"
            , class "auth-input auth-input-hero"
            , autofocus True
            , onInput LoginTokenChanged
            ]
            []
        , div [ class "auth-hint" ] [ text "Paste the token you saved when you signed up." ]
        , button [ type_ "submit", class "auth-submit" ]
            [ text ("Sign in and join " ++ fs.workspace.name) ]
        , Auth.Ui.errorLine fs.error
        ]


viewSignupForm : FormState -> Html Msg
viewSignupForm fs =
    let
        canSubmit =
            String.trim fs.username /= ""
    in
    form [ class "auth-form", id "invite-signup-form", onSubmit SubmitSignup ]
        [ label [ class "auth-label", for "username" ] [ text "Username" ]
        , input
            [ type_ "text"
            , name "username"
            , id "username"
            , value fs.username
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
        , label [ class "auth-label", style "margin-top" "18px" ] [ text "Your API key" ]
        , Auth.Ui.tokenField
            { token = Maybe.withDefault "" fs.previewToken
            , copied = fs.copied
            , onCopy = CopyClicked
            , onNativeCopy = TokenCopied
            }
        , Auth.Ui.copyHint
        , button [ type_ "submit", class "auth-submit", Html.Attributes.disabled (not canSubmit) ]
            [ text ("Join " ++ fs.workspace.name) ]
        , Auth.Ui.errorLine fs.error
        ]
