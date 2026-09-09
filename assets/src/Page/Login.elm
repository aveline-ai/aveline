module Page.Login exposing (Model, Msg, init, update, view)

{-| Ported from lib/aveline\_web/live/login\_live.ex by the fe-auth
page agent. Keep the exposed signature exactly as-is; Main.elm
depends on it.

Token paste form. Submit hits POST /papi/session (the JSON mirror of
SessionController.create); on success we do a full page load to `/` so
the fresh session cookie applies everywhere — the server then bounces
signed-in users into their workspace, exactly like the old POST /login
redirect. Invalid tokens show inline (the LiveView surfaced them as a
flash after the redirect).

-}

import Api
import Auth.Ui
import Browser.Navigation as Nav
import Html exposing (Html, a, button, div, form, input, label, text)
import Html.Attributes exposing (attribute, autocomplete, autofocus, class, for, href, id, name, placeholder, required, spellcheck, type_)
import Html.Events exposing (onInput, onSubmit)
import Json.Decode as Decode
import Json.Encode as Encode
import Route
import Session exposing (Session)
import Ui.AuthBg


type alias Model =
    { session : Session
    , next : String
    , redirecting : Bool
    , token : String
    , error : Maybe String
    , submitting : Bool
    }


type Msg
    = TokenChanged String
    | Submitted
    | GotLogin (Result Api.Error ())


init : Session -> Maybe String -> ( Model, Cmd Msg )
init session next =
    let
        model =
            { session = session
            , next = safeNext next
            , redirecting = False
            , token = ""
            , error = Nothing
            , submitting = False
            }
    in
    case session.user of
        Just _ ->
            -- Already signed in — bounce home, mirroring the LiveView's
            -- push_navigate to "/".
            ( { model | redirecting = True }, Nav.load model.next )

        Nothing ->
            ( model, Cmd.none )


{-| Mirror SessionController.safe\_next/1: only same-origin relative
paths, so a crafted link can't bounce the user off-site after login.
-}
safeNext : Maybe String -> String
safeNext next =
    case next of
        Just path ->
            if String.startsWith "/" path && not (String.startsWith "//" path) then
                path

            else
                "/"

        Nothing ->
            "/"


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        TokenChanged raw ->
            ( { model | token = raw, error = Nothing }, Cmd.none )

        Submitted ->
            if model.submitting || String.trim model.token == "" then
                ( model, Cmd.none )

            else
                ( { model | submitting = True }
                , Api.post model.session
                    "/papi/session"
                    (Encode.object [ ( "token", Encode.string (String.trim model.token) ) ])
                    (Decode.succeed ())
                    GotLogin
                )

        GotLogin (Ok ()) ->
            -- Full page load so the fresh session cookie applies
            -- everywhere; the server routes signed-in users onward.
            ( model, Nav.load model.next )

        GotLogin (Err err) ->
            ( { model | submitting = False, error = Just (Api.errorMessage err) }
            , Cmd.none
            )


view : Model -> Html Msg
view model =
    if model.redirecting then
        text ""

    else
        div [ class "auth-shell" ]
            (Ui.AuthBg.split
                ++ [ div [ class "auth-card auth-card-spare" ]
                        [ Auth.Ui.brand
                        , form [ class "auth-form", onSubmit Submitted ]
                            [ label [ class "auth-label", for "token" ] [ text "API key" ]
                            , input
                                [ type_ "text"
                                , name "token"
                                , id "token"
                                , placeholder "avl_…"
                                , class "auth-input auth-input-hero mono"
                                , autocomplete False
                                , attribute "autocapitalize" "none"
                                , attribute "autocorrect" "off"
                                , spellcheck False
                                , attribute "data-1p-ignore" ""
                                , attribute "data-lpignore" "true"
                                , attribute "data-bwignore" ""
                                , autofocus True
                                , required True
                                , onInput TokenChanged
                                ]
                                []
                            , button [ type_ "submit", class "auth-submit" ] [ text "Log in" ]
                            , Auth.Ui.errorLine model.error
                            ]
                        , div [ class "auth-footer" ]
                            [ text "New here? "
                            , a [ href (Route.href Route.Signup), class "auth-link" ] [ text "Sign up" ]
                            ]
                        ]
                   ]
            )
