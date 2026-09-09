module Page.Settings exposing (Model, Msg, init, update, view)

{-| User settings — ported from `lib/aveline_web/live/settings_live.ex`:
display-name profile form plus API key self-service. Settings are
per-user; the workspace slug in the URL only keeps the sidebar context
(and scopes the profile endpoint).

Data:

  - GET /papi/me (current user incl. display name)
  - PUT /papi/workspaces/:slug/profile (fe-workspace endpoint)
  - GET /papi/keys, POST /papi/keys, DELETE /papi/keys/:id

`data-confirm` is replaced by a two-step arm/confirm on the revoke
button; the copy buttons keep the LiveView markup but need a clipboard
port (deferred to the coordinator).

-}

import Api
import Html exposing (Html, button, code, div, form, h1, input, label, li, p, span, strong, text, ul)
import Html.Attributes exposing (attribute, autocomplete, class, for, id, placeholder, title, type_, value)
import Html.Events exposing (onClick, onInput, onSubmit)
import Iso8601
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Session exposing (Session)
import Task
import Time exposing (Posix)
import Ui.Workspace.Time exposing (absoluteTime, relativeTime)



-- MODEL


type alias Model =
    { session : Session
    , slug : String
    , now : Maybe Posix
    , username : Maybe String
    , displayName : String
    , saved : Bool
    , error : Maybe String
    , keys : List Key
    , keysLoaded : Bool
    , newKey : Maybe NewKey
    , keyError : Maybe String
    , keyNameInput : String
    , pendingRevoke : Maybe String
    }


type alias Key =
    { id : String
    , name : String
    , masked : String
    , createdAt : Posix
    , lastUsedAt : Maybe Posix
    }


type alias NewKey =
    { id : String
    , name : String
    , plaintext : String
    }


init : Session -> String -> ( Model, Cmd Msg )
init session slug =
    ( { session = session
      , slug = slug
      , now = Nothing
      , username = Maybe.map .username session.user
      , displayName = ""
      , saved = False
      , error = Nothing
      , keys = []
      , keysLoaded = False
      , newKey = Nothing
      , keyError = Nothing
      , keyNameInput = ""
      , pendingRevoke = Nothing
      }
    , Cmd.batch
        [ Task.perform GotNow Time.now
        , Api.get session "/papi/me" meDecoder GotMe
        , fetchKeys session
        ]
    )


fetchKeys : Session -> Cmd Msg
fetchKeys session =
    Api.get session "/papi/keys" keysDecoder GotKeys



-- UPDATE


type Msg
    = GotNow Posix
    | GotMe (Result Api.Error Me)
    | GotKeys (Result Api.Error (List Key))
    | DisplayNameChanged String
    | SaveProfile
    | GotSaved (Result Api.Error (Maybe String))
    | KeyNameChanged String
    | CreateKey
    | GotCreatedKey (Result Api.Error NewKey)
    | RevokeKey String
    | GotRevoked String (Result Api.Error ())


type alias Me =
    { username : String
    , displayName : Maybe String
    }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotNow now ->
            ( { model | now = Just now }, Cmd.none )

        GotMe (Ok me) ->
            ( { model
                | username = Just me.username
                , displayName = Maybe.withDefault "" me.displayName
              }
            , Cmd.none
            )

        GotMe (Err _) ->
            ( model, Cmd.none )

        GotKeys (Ok keys) ->
            ( { model | keys = keys, keysLoaded = True }, Cmd.none )

        GotKeys (Err _) ->
            ( { model | keysLoaded = True }, Cmd.none )

        DisplayNameChanged raw ->
            -- Mirrors the LV "update" event: typing clears saved/error.
            ( { model | displayName = raw, saved = False, error = Nothing }, Cmd.none )

        SaveProfile ->
            ( model
            , Api.put model.session
                ("/papi/workspaces/" ++ model.slug ++ "/profile")
                (Encode.object [ ( "display_name", Encode.string model.displayName ) ])
                savedDecoder
                GotSaved
            )

        GotSaved (Ok nextName) ->
            ( { model
                | displayName = Maybe.withDefault "" nextName
                , saved = True
                , error = Nothing
              }
            , Cmd.none
            )

        GotSaved (Err err) ->
            ( { model | error = Just (Api.errorMessage err) }, Cmd.none )

        KeyNameChanged raw ->
            ( { model | keyNameInput = raw }, Cmd.none )

        CreateKey ->
            if String.trim model.keyNameInput == "" then
                ( { model | keyError = Just "Give the key a name, like \"laptop\" or \"work\"." }
                , Cmd.none
                )

            else
                ( model
                , Api.post model.session
                    "/papi/keys"
                    (Encode.object [ ( "name", Encode.string (String.trim model.keyNameInput) ) ])
                    newKeyDecoder
                    GotCreatedKey
                )

        GotCreatedKey (Ok newKey) ->
            ( { model | newKey = Just newKey, keyError = Nothing, keyNameInput = "" }
            , fetchKeys model.session
            )

        GotCreatedKey (Err _) ->
            ( { model | keyError = Just "Could not create the key. Try again." }, Cmd.none )

        RevokeKey keyId ->
            -- Two-step confirmation standing in for data-confirm.
            if model.pendingRevoke == Just keyId then
                ( { model | pendingRevoke = Nothing }
                , Api.delete model.session
                    ("/papi/keys/" ++ keyId)
                    (Decode.succeed ())
                    (GotRevoked keyId)
                )

            else
                ( { model | pendingRevoke = Just keyId }, Cmd.none )

        GotRevoked keyId (Ok ()) ->
            -- Also clear the one-time reveal if it was for the revoked key.
            ( { model
                | keyError = Nothing
                , newKey =
                    case model.newKey of
                        Just nk ->
                            if nk.id == keyId then
                                Nothing

                            else
                                model.newKey

                        Nothing ->
                            Nothing
              }
            , fetchKeys model.session
            )

        GotRevoked _ (Err err) ->
            ( { model
                | keyError =
                    case err of
                        Api.ApiError e ->
                            if e.code == "last_key" then
                                Just "That's your only key. Create a new one first, then revoke this one."

                            else
                                Just "Could not revoke that key."

                        _ ->
                            Just "Could not revoke that key."
              }
            , Cmd.none
            )



-- VIEW


view : Model -> Html Msg
view model =
    div [ class "content" ]
        [ h1 [ class "page-title" ] [ text "Settings" ]
        , p [ class "page-subtitle" ]
            [ text "Signed in as "
            , span [ class "mono" ] [ text (Maybe.withDefault "" model.username) ]
            , text "."
            ]
        , div [ class "section-label" ] [ text "Profile" ]
        , viewProfileForm model
        , div [ class "section-label", attribute "style" "margin-top:32px" ]
            [ text "API keys "
            , span [ class "count" ] [ text (String.fromInt (List.length model.keys)) ]
            ]
        , case model.newKey of
            Just newKey ->
                viewNewKey newKey

            Nothing ->
                text ""
        , ul [ class "card-list" ]
            (List.map (viewKeyRow model) model.keys)
        , viewCreateKeyForm model
        , case model.keyError of
            Just err ->
                div [ class "auth-error", attribute "style" "margin-top:8px" ] [ text err ]

            Nothing ->
                text ""
        , div [ class "auth-hint", attribute "style" "margin-top:8px" ]
            [ text "Keys are shown once at creation and stored hashed. Sign in on another browser with "
            , span [ class "mono" ] [ text "/login/<key>" ]
            , text ", or point the CLI at one via "
            , span [ class "mono" ] [ text "aveline login" ]
            , text "."
            ]
        ]


viewProfileForm : Model -> Html Msg
viewProfileForm model =
    form
        [ onSubmit SaveProfile
        , class "auth-form"
        , attribute "style" "max-width:480px"
        ]
        (List.filterMap identity
            [ Just (label [ class "auth-label", for "display-name" ] [ text "Display name" ])
            , Just
                (input
                    [ type_ "text"
                    , Html.Attributes.name "display_name"
                    , id "display-name"
                    , value model.displayName
                    , onInput DisplayNameChanged
                    , autocomplete False
                    , placeholder "e.g. Alice from accounting"
                    , class
                        ("auth-input "
                            ++ (case model.error of
                                    Just _ ->
                                        "auth-input-error"

                                    Nothing ->
                                        ""
                               )
                        )
                    ]
                    []
                )
            , Just
                (div [ class "auth-hint" ]
                    [ text "Shown next to your username on items and threads. Leave blank to use just the username." ]
                )
            , Maybe.map
                (\err -> div [ class "auth-error" ] [ text err ])
                model.error
            , if model.saved then
                Just
                    (div [ class "auth-hint", attribute "style" "color:#4ADE80;margin-top:8px" ]
                        [ text "Saved." ]
                    )

              else
                Nothing
            , Just
                (button
                    [ type_ "submit", class "auth-submit", attribute "style" "max-width:140px" ]
                    [ text "Save" ]
                )
            ]
        )


viewNewKey : NewKey -> Html Msg
viewNewKey newKey =
    div [ class "invite-block", attribute "style" "margin-bottom:14px" ]
        [ p [ class "auth-hint", attribute "style" "margin-bottom:10px" ]
            [ text "Your new key "
            , strong [] [ text newKey.name ]
            , text ". Copy it now: this is the only time it's shown. Only a hash is stored."
            ]
        , div [ class "invite-url-row" ]
            [ code [ id "new-key-value", class "invite-url" ] [ text newKey.plaintext ]
            , button
                [ type_ "button"
                , id "copy-new-key-btn"
                , class "auth-secondary"
                , attribute "data-target" "#new-key-value"
                , attribute "style" "height:36px;padding:0 14px"
                ]
                [ text "Copy" ]
            ]
        ]


viewKeyRow : Model -> Key -> Html Msg
viewKeyRow model t =
    li [ class "card team-row" ]
        [ div [ class "team-row-left" ]
            [ div []
                [ div [ class "team-row-name" ]
                    [ text t.name
                    , span
                        [ class "mono"
                        , attribute "style" "margin-left:8px;font-size:12px;color:var(--text-muted)"
                        ]
                        [ text t.masked ]
                    ]
                , div [ class "team-row-sub" ]
                    ([ text "created "
                     , span [ title (absoluteTime t.createdAt) ] [ text (relative model t.createdAt) ]
                     , text " · last used "
                     ]
                        ++ (case t.lastUsedAt of
                                Just lastUsed ->
                                    [ span [ title (absoluteTime lastUsed) ]
                                        [ text (relative model lastUsed) ]
                                    ]

                                Nothing ->
                                    [ span [] [ text "never" ] ]
                           )
                    )
                ]
            ]
        , div [ class "team-row-right" ]
            [ div [ class "team-row-actions" ]
                [ if List.length model.keys > 1 then
                    button
                        [ onClick (RevokeKey t.id)
                        , class "thread-action-btn"
                        , title (keyConfirm t (List.length model.keys))
                        ]
                        [ text
                            (if model.pendingRevoke == Just t.id then
                                "confirm?"

                             else
                                "revoke"
                            )
                        ]

                  else
                    span
                        [ class "auth-hint"
                        , attribute "style" "font-size:11px"
                        , title "Your only key. Create a new one first, then revoke this one."
                        ]
                        [ text "only key" ]
                ]
            ]
        ]


keyConfirm : Key -> Int -> String
keyConfirm t count =
    let
        base =
            "Revoke \"" ++ t.name ++ "\" (" ++ t.masked ++ ")? Anything still using it stops working immediately."
    in
    if count > 1 then
        base ++ " If this browser signed in with it, your session cookie keeps working."

    else
        base


viewCreateKeyForm : Model -> Html Msg
viewCreateKeyForm model =
    form
        [ onSubmit CreateKey
        , attribute "style" "display:flex;gap:8px;margin-top:12px;max-width:480px"
        ]
        [ input
            [ type_ "text"
            , Html.Attributes.name "key_name"
            , value model.keyNameInput
            , onInput KeyNameChanged
            , autocomplete False
            , placeholder "Name the new key, e.g. \"laptop\""
            , class "auth-input"
            , attribute "style" "flex:1"
            ]
            []
        , button
            [ type_ "submit"
            , class "auth-secondary"
            , attribute "style" "height:44px;padding:0 16px;white-space:nowrap"
            ]
            [ text "New key" ]
        ]


relative : Model -> Posix -> String
relative model t =
    case model.now of
        Just now ->
            relativeTime now t

        Nothing ->
            ""



-- DECODERS


meDecoder : Decoder Me
meDecoder =
    Decode.field "user"
        (Decode.map2 Me
            (Decode.field "username" Decode.string)
            (Decode.field "display_name" (Decode.nullable Decode.string))
        )


keysDecoder : Decoder (List Key)
keysDecoder =
    Decode.field "keys"
        (Decode.list
            (Decode.map5 Key
                (Decode.field "id" Decode.string)
                (Decode.field "name" Decode.string)
                (Decode.field "masked" Decode.string)
                (Decode.field "created_at" Iso8601.decoder)
                (Decode.field "last_used_at" (Decode.nullable Iso8601.decoder))
            )
        )


{-| PUT /profile echoes the updated user; we only need the new name.
-}
savedDecoder : Decoder (Maybe String)
savedDecoder =
    Decode.at [ "user", "display_name" ] (Decode.nullable Decode.string)


{-| POST /papi/keys responds with the key map at the top level plus the
one-time `key` plaintext.
-}
newKeyDecoder : Decoder NewKey
newKeyDecoder =
    Decode.map3 NewKey
        (Decode.field "id" Decode.string)
        (Decode.field "name" Decode.string)
        (Decode.field "key" Decode.string)
