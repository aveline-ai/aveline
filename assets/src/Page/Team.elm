module Page.Team exposing (Model, Msg, init, update, view)

{-| Team page — ported from `lib/aveline_web/live/team_live.ex`:
members roster with per-member usage stats (folded in from the old
Usage page), workspace totals, and the invite link.

Data:

  - GET /papi/workspaces/:slug/members (existing endpoint)
  - GET /papi/workspaces/:slug/team (fe-workspace endpoint: totals,
    per-member stats, current invite — read-only, never mints)
  - GET /papi/workspaces/:slug (workspace name for the invite copy)
  - POST /papi/workspaces/:slug/invite (generate)
  - POST /papi/workspaces/:slug/invite/rotate (fe-workspace endpoint)
  - DELETE /papi/workspaces/:slug/invite (revoke)
  - DELETE /papi/workspaces/:slug/members/:id (remove)

`data-confirm` dialogs are replaced by a two-step arm/confirm on the
same button (no browser confirm without a port); the LiveView's flash
messages render inline at the top of the content region.

-}

import Api
import Dict exposing (Dict)
import Html exposing (Html, button, code, div, h1, li, p, span, strong, text, ul)
import Html.Attributes exposing (attribute, class, id, title, type_)
import Html.Events exposing (onClick)
import Iso8601
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Session exposing (Session)
import Task
import Time exposing (Posix)
import Ui.Workspace.Format exposing (avatarHue, formatNumber, initial)
import Ui.Workspace.Time exposing (absoluteTime, relativeTime)



-- MODEL


type alias Model =
    { session : Session
    , slug : String
    , now : Maybe Posix
    , workspaceName : Maybe String
    , members : Status (List Member)
    , team : Status TeamData
    , pendingConfirm : Maybe Confirm
    , notice : Maybe Notice
    }


type Status a
    = Loading
    | Loaded a
    | Failed Api.Error


type Confirm
    = ConfirmRotate
    | ConfirmRevoke
    | ConfirmRemove String


type alias Notice =
    { error : Bool
    , message : String
    }


type alias Member =
    { id : String
    , username : String
    , displayName : Maybe String
    , joinedAt : Posix
    }


type alias TeamData =
    { invite : Maybe Invite
    , totals : Totals
    , statsByUser : Dict String MemberStats
    }


type alias Invite =
    { code : String
    , url : String
    }


type alias Totals =
    { activeDocs : Int
    , reads : Int
    , totalEdits : Int
    , kudos : Int
    , comments : Int
    }


type alias MemberStats =
    { docsOwned : Int
    , editsMade : Int
    , readsEarned : Int
    , kudosEarned : Int
    }


init : Session -> String -> ( Model, Cmd Msg )
init session slug =
    ( { session = session
      , slug = slug
      , now = Nothing
      , workspaceName = Nothing
      , members = Loading
      , team = Loading
      , pendingConfirm = Nothing
      , notice = Nothing
      }
    , Cmd.batch
        [ Task.perform GotNow Time.now
        , fetchMembers session slug
        , fetchTeam session slug
        , Api.get session ("/papi/workspaces/" ++ slug) workspaceNameDecoder GotWorkspaceName
        ]
    )


fetchMembers : Session -> String -> Cmd Msg
fetchMembers session slug =
    Api.get session ("/papi/workspaces/" ++ slug ++ "/members") membersDecoder GotMembers


fetchTeam : Session -> String -> Cmd Msg
fetchTeam session slug =
    Api.get session ("/papi/workspaces/" ++ slug ++ "/team") teamDecoder GotTeam



-- UPDATE


type Msg
    = GotNow Posix
    | GotWorkspaceName (Result Api.Error String)
    | GotMembers (Result Api.Error (List Member))
    | GotTeam (Result Api.Error TeamData)
    | CreateInvite
    | GotInvite (Result Api.Error Invite)
    | RotateInvite
    | GotRotated (Result Api.Error Invite)
    | RevokeInvite
    | GotRevoked (Result Api.Error ())
    | RemoveMember String
    | GotRemoved (Result Api.Error ())
    | CancelConfirm


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotNow now ->
            ( { model | now = Just now }, Cmd.none )

        GotWorkspaceName (Ok name) ->
            ( { model | workspaceName = Just name }, Cmd.none )

        GotWorkspaceName (Err _) ->
            ( model, Cmd.none )

        GotMembers (Ok members) ->
            ( { model | members = Loaded members }, Cmd.none )

        GotMembers (Err err) ->
            ( { model | members = Failed err }, Cmd.none )

        GotTeam (Ok team) ->
            ( { model | team = Loaded team }, Cmd.none )

        GotTeam (Err err) ->
            ( { model | team = Failed err }, Cmd.none )

        CreateInvite ->
            ( model
            , Api.post model.session
                ("/papi/workspaces/" ++ model.slug ++ "/invite")
                (Encode.object [])
                inviteDecoder
                GotInvite
            )

        GotInvite (Ok invite) ->
            ( { model | team = setInvite (Just invite) model.team, notice = Nothing }
            , Cmd.none
            )

        GotInvite (Err _) ->
            ( { model | notice = Just { error = True, message = "Could not create invite link." } }
            , Cmd.none
            )

        RotateInvite ->
            confirmable ConfirmRotate
                model
                (Api.post model.session
                    ("/papi/workspaces/" ++ model.slug ++ "/invite/rotate")
                    (Encode.object [])
                    rotatedDecoder
                    GotRotated
                )

        GotRotated (Ok invite) ->
            ( { model
                | team = setInvite (Just invite) model.team
                , notice = Just { error = False, message = "Rotated. Old link no longer works." }
              }
            , Cmd.none
            )

        GotRotated (Err _) ->
            ( { model | notice = Just { error = True, message = "Could not rotate." } }
            , Cmd.none
            )

        RevokeInvite ->
            confirmable ConfirmRevoke
                model
                (Api.delete model.session
                    ("/papi/workspaces/" ++ model.slug ++ "/invite")
                    (Decode.succeed ())
                    GotRevoked
                )

        GotRevoked (Ok ()) ->
            ( { model
                | team = setInvite Nothing model.team
                , notice = Just { error = False, message = "Invite link revoked." }
              }
            , Cmd.none
            )

        GotRevoked (Err _) ->
            ( model, Cmd.none )

        RemoveMember userId ->
            confirmable (ConfirmRemove userId)
                model
                (Api.delete model.session
                    ("/papi/workspaces/" ++ model.slug ++ "/members/" ++ userId)
                    (Decode.succeed ())
                    GotRemoved
                )

        GotRemoved (Ok ()) ->
            -- Same as TeamLive's assign_roster: refetch rows and stats
            -- together so they never drift apart.
            ( { model | notice = Nothing }
            , Cmd.batch
                [ fetchMembers model.session model.slug
                , fetchTeam model.session model.slug
                ]
            )

        GotRemoved (Err _) ->
            ( { model | notice = Just { error = True, message = "Could not remove member." } }
            , Cmd.none
            )

        CancelConfirm ->
            ( { model | pendingConfirm = Nothing }, Cmd.none )


{-| Two-step confirmation: first click arms the button, second fires.
-}
confirmable : Confirm -> Model -> Cmd Msg -> ( Model, Cmd Msg )
confirmable action model cmd =
    if model.pendingConfirm == Just action then
        ( { model | pendingConfirm = Nothing }, cmd )

    else
        ( { model | pendingConfirm = Just action }, Cmd.none )


setInvite : Maybe Invite -> Status TeamData -> Status TeamData
setInvite invite team =
    case team of
        Loaded data ->
            Loaded { data | invite = invite }

        other ->
            other



-- VIEW


view : Model -> Html Msg
view model =
    div [ class "content" ]
        (List.filterMap identity
            [ Just (h1 [ class "page-title" ] [ text "Team" ])
            , Just
                (p [ class "page-subtitle" ]
                    [ text "Everyone who can read + comment in "
                    , span [ class "mono" ] [ text model.slug ]
                    , text "."
                    ]
                )
            , Maybe.map viewNotice model.notice
            , viewTotals model
            , Just (viewMembers model)
            , Just (viewInviteSection model)
            ]
        )


viewNotice : Notice -> Html Msg
viewNotice notice =
    if notice.error then
        div [ class "auth-error", attribute "style" "margin-bottom:12px" ] [ text notice.message ]

    else
        div [ class "banner", attribute "style" "margin-bottom:12px" ] [ text notice.message ]


viewTotals : Model -> Maybe (Html Msg)
viewTotals model =
    case model.team of
        Loaded data ->
            Just
                (p [ class "team-totals" ]
                    [ text "Together: "
                    , stat data.totals.activeDocs "doc"
                    , text " · "
                    , stat data.totals.reads "view"
                    , text " · "
                    , stat data.totals.totalEdits "edit"
                    , text " · "
                    , stat data.totals.kudos "kudos"
                    , text " · "
                    , stat data.totals.comments "comment"
                    ]
                )

        _ ->
            Nothing


viewMembers : Model -> Html Msg
viewMembers model =
    case model.members of
        Loading ->
            div [ class "section-label" ] [ text "Members" ]

        Failed err ->
            div [ class "empty" ] [ text (Api.errorMessage err) ]

        Loaded members ->
            div []
                [ div [ class "section-label" ]
                    [ text "Members "
                    , span [ class "count" ] [ text (String.fromInt (List.length members)) ]
                    ]
                , ul [ class "card-list" ]
                    (List.map (viewMemberRow model) members)
                ]


viewMemberRow : Model -> Member -> Html Msg
viewMemberRow model m =
    let
        isSelf =
            currentUserId model == Just m.id

        hue =
            String.fromInt (avatarHue m.username)
    in
    li [ class "card team-row" ]
        [ div [ class "team-row-left" ]
            [ div
                [ class "team-avatar"
                , attribute "style"
                    ("background: hsl(" ++ hue ++ ", 55%, 28%); color: hsl(" ++ hue ++ ", 70%, 80%)")
                ]
                [ text (initial m.username) ]
            , div []
                [ div [ class "team-row-name" ]
                    (text m.username
                        :: (if isSelf then
                                [ span
                                    [ class "chip"
                                    , attribute "style" "margin-left:6px;font-size:10px;height:18px;padding:0 6px"
                                    ]
                                    [ text "you" ]
                                ]

                            else
                                []
                           )
                    )
                , div [ class "team-row-sub" ]
                    ((case m.displayName of
                        Just name ->
                            if name /= "" then
                                [ text (name ++ " · ") ]

                            else
                                []

                        Nothing ->
                            []
                     )
                        ++ [ text "joined "
                           , span [ title (absoluteTime m.joinedAt) ]
                                [ text (relative model m.joinedAt) ]
                           ]
                    )
                ]
            ]
        , div [ class "team-row-right" ]
            [ viewMemberStats model m
            , div [ class "team-row-actions" ]
                (if isSelf then
                    []

                 else
                    [ removeButton model m ]
                )
            ]
        ]


removeButton : Model -> Member -> Html Msg
removeButton model m =
    let
        armed =
            model.pendingConfirm == Just (ConfirmRemove m.id)
    in
    button
        [ onClick (RemoveMember m.id)
        , class "thread-action-btn"
        , title ("Remove " ++ m.username ++ " from this workspace?")
        ]
        [ text
            (if armed then
                "confirm?"

             else
                "remove"
            )
        ]


viewMemberStats : Model -> Member -> Html Msg
viewMemberStats model m =
    case model.team of
        Loaded data ->
            case Dict.get m.id data.statsByUser of
                Just s ->
                    div [ class "team-row-stats" ]
                        [ div [ class "team-stat-group" ]
                            [ div [ class "team-stat-group-label" ] [ text "Built" ]
                            , div [ class "team-stat-group-values" ]
                                [ stat s.docsOwned "doc"
                                , text " · "
                                , stat s.editsMade "edit"
                                ]
                            ]
                        , div [ class "team-stat-group" ]
                            [ div [ class "team-stat-group-label" ] [ text "Impact" ]
                            , div [ class "team-stat-group-values" ]
                                [ stat s.readsEarned "view"
                                , text " · "
                                , stat s.kudosEarned "kudos"
                                ]
                            ]
                        ]

                Nothing ->
                    text ""

        _ ->
            text ""


{-| `<span class="team-stat"><strong>{n}</strong> {word}</span>` —
"kudos" is its own plural; everything else takes a plain s.
-}
stat : Int -> String -> Html Msg
stat value label =
    span [ class "team-stat" ]
        [ strong [] [ text (formatNumber value) ]
        , text (" " ++ pluralizeLabel label value)
        ]


pluralizeLabel : String -> Int -> String
pluralizeLabel label value =
    if value == 1 then
        label

    else if label == "kudos" then
        "kudos"

    else
        label ++ "s"



-- Invite link


viewInviteSection : Model -> Html Msg
viewInviteSection model =
    div []
        [ div [ class "section-label", attribute "style" "margin-top:32px" ] [ text "Invite link" ]
        , case model.team of
            Loaded data ->
                case data.invite of
                    Just invite ->
                        viewInvite model invite

                    Nothing ->
                        viewNoInvite

            _ ->
                text ""
        ]


viewInvite : Model -> Invite -> Html Msg
viewInvite model invite =
    div [ class "invite-block" ]
        [ p [ class "auth-hint", attribute "style" "margin-bottom:10px" ]
            [ text "Anyone with this link can join "
            , strong [] [ text (Maybe.withDefault model.slug model.workspaceName) ]
            , text ". New users get a signup screen; existing users join with one click."
            ]
        , div [ class "invite-url-row" ]
            [ code [ id "invite-url-value", class "invite-url" ] [ text invite.url ]
            , button
                [ type_ "button"
                , id "copy-invite-btn"
                , class "auth-secondary"
                , attribute "data-target" "#invite-url-value"
                , attribute "style" "height:36px;padding:0 14px"
                ]
                [ text "Copy" ]
            ]
        , div [ attribute "style" "display:flex;gap:8px;margin-top:12px" ]
            [ button
                [ onClick RotateInvite
                , class "auth-secondary"
                , attribute "style" "height:32px;padding:0 12px;font-size:12px"
                , title "Rotate the invite link? The current link will stop working."
                ]
                [ text
                    (if model.pendingConfirm == Just ConfirmRotate then
                        "Confirm rotate"

                     else
                        "Rotate"
                    )
                ]
            , button
                [ onClick RevokeInvite
                , class "auth-secondary"
                , attribute "style" "height:32px;padding:0 12px;font-size:12px;color:var(--danger);border-color:rgba(229,72,77,0.3)"
                , title "Revoke the invite link entirely?"
                ]
                [ text
                    (if model.pendingConfirm == Just ConfirmRevoke then
                        "Confirm revoke"

                     else
                        "Revoke"
                    )
                ]
            ]
        ]


viewNoInvite : Html Msg
viewNoInvite =
    div [ class "banner" ]
        [ text "No active invite link."
        , button
            [ onClick CreateInvite
            , class "auth-link"
            , attribute "style" "background:none;border:none;cursor:pointer;padding:0;margin-left:6px"
            ]
            [ text "Generate one" ]
        ]


currentUserId : Model -> Maybe String
currentUserId model =
    Maybe.map .id model.session.user


relative : Model -> Posix -> String
relative model t =
    case model.now of
        Just now ->
            relativeTime now t

        Nothing ->
            ""



-- DECODERS


membersDecoder : Decoder (List Member)
membersDecoder =
    Decode.field "members"
        (Decode.list
            (Decode.map4 Member
                (Decode.field "id" Decode.string)
                (Decode.field "username" Decode.string)
                (Decode.field "display_name" (Decode.nullable Decode.string))
                (Decode.field "joined_at" Iso8601.decoder)
            )
        )


teamDecoder : Decoder TeamData
teamDecoder =
    Decode.map3 TeamData
        (Decode.field "invite" (Decode.nullable inviteFieldsDecoder))
        (Decode.field "totals" totalsDecoder)
        (Decode.field "contributors" statsByUserDecoder)


inviteFieldsDecoder : Decoder Invite
inviteFieldsDecoder =
    Decode.map2 Invite
        (Decode.field "code" Decode.string)
        (Decode.field "url" Decode.string)


{-| POST /invite responds with top-level `code` + `url`.
-}
inviteDecoder : Decoder Invite
inviteDecoder =
    inviteFieldsDecoder


{-| POST /invite/rotate responds with `invite: {code, url}`.
-}
rotatedDecoder : Decoder Invite
rotatedDecoder =
    Decode.field "invite" inviteFieldsDecoder


totalsDecoder : Decoder Totals
totalsDecoder =
    Decode.map5 Totals
        (Decode.field "active_docs" Decode.int)
        (Decode.field "reads" Decode.int)
        (Decode.field "total_edits" Decode.int)
        (Decode.field "kudos" Decode.int)
        (Decode.field "comments" Decode.int)


statsByUserDecoder : Decoder (Dict String MemberStats)
statsByUserDecoder =
    Decode.list
        (Decode.map5 (\uid a b c d -> ( uid, MemberStats a b c d ))
            (Decode.field "user_id" Decode.string)
            (Decode.field "docs_owned" Decode.int)
            (Decode.field "edits_made" Decode.int)
            (Decode.field "reads_earned" Decode.int)
            (Decode.field "kudos_earned" Decode.int)
        )
        |> Decode.map Dict.fromList


workspaceNameDecoder : Decoder String
workspaceNameDecoder =
    Decode.at [ "workspace", "name" ] Decode.string
