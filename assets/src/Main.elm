module Main exposing (main)

{-| SPA shell: routing + page dispatch + the shared workspace chrome
(sidebar; see Ui.Chrome). STABLE shared surface — page agents fill
their Page.\* module; only the coordinator edits this file.
-}

import Api
import Api.Docs
import Api.Workspaces
import Browser exposing (Document)
import Browser.Navigation as Nav
import Html exposing (Html)
import Json.Decode as Decode
import Page.Activity
import Page.DataSources
import Page.DocShow
import Page.Docs
import Page.Home
import Page.Invite
import Page.Login
import Page.Settings
import Page.Signup
import Page.Team
import Page.Welcome
import Page.WorkspaceNew
import Route exposing (Route)
import Session exposing (Session)
import Ui.Chrome as Chrome
import Url exposing (Url)


main : Program Decode.Value Model Msg
main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = \_ -> Sub.none
        , onUrlRequest = LinkClicked
        , onUrlChange = UrlChanged
        }


type alias Model =
    { key : Nav.Key
    , session : Session
    , page : Page
    , route : Maybe Route
    , chrome : Maybe ChromeModel
    }


{-| Sidebar data for the current workspace. Fetched when entering a
workspace, kept across same-workspace navigations, dropped on bare
(auth) routes. Fetch failures leave the lists empty — the chrome still
renders with the slug as the workspace name.
-}
type alias ChromeModel =
    { slug : String
    , workspaces : List Api.Workspaces.Workspace
    , sections : Maybe Chrome.Sections
    }


type Page
    = NotFound
    | Signup Page.Signup.Model
    | Login Page.Login.Model
    | Invite Page.Invite.Model
    | WorkspaceNew Page.WorkspaceNew.Model
    | Home Page.Home.Model
    | Welcome Page.Welcome.Model
    | Docs Page.Docs.Model
    | DocShow Page.DocShow.Model
    | Activity Page.Activity.Model
    | DataSources Page.DataSources.Model
    | Team Page.Team.Model
    | Settings Page.Settings.Model


type Msg
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url
    | SignupMsg Page.Signup.Msg
    | LoginMsg Page.Login.Msg
    | InviteMsg Page.Invite.Msg
    | WorkspaceNewMsg Page.WorkspaceNew.Msg
    | HomeMsg Page.Home.Msg
    | WelcomeMsg Page.Welcome.Msg
    | DocsMsg Page.Docs.Msg
    | DocShowMsg Page.DocShow.Msg
    | ActivityMsg Page.Activity.Msg
    | DataSourcesMsg Page.DataSources.Msg
    | TeamMsg Page.Team.Msg
    | SettingsMsg Page.Settings.Msg
    | GotChromeWorkspaces (Result Api.Error (List Api.Workspaces.Workspace))
    | GotChromeViews String (Result Api.Error (List Api.Docs.ViewDef))


init : Decode.Value -> Url -> Nav.Key -> ( Model, Cmd Msg )
init flags url key =
    let
        session =
            Decode.decodeValue Session.decoder flags
                |> Result.withDefault { csrf = "", user = Nothing }
    in
    routeTo url
        { key = key
        , session = session
        , page = NotFound
        , route = Nothing
        , chrome = Nothing
        }


routeTo : Url -> Model -> ( Model, Cmd Msg )
routeTo url oldModel =
    let
        route =
            Route.fromUrl url

        ( chrome, chromeCmd ) =
            syncChrome route oldModel

        model =
            { oldModel | route = route, chrome = chrome }

        wrap toPage toMsg ( pageModel, cmd ) =
            ( { model | page = toPage pageModel }
            , Cmd.batch [ Cmd.map toMsg cmd, chromeCmd ]
            )
    in
    case route of
        Nothing ->
            ( { model | page = NotFound }, chromeCmd )

        Just Route.Signup ->
            wrap Signup SignupMsg (Page.Signup.init model.session)

        Just Route.Login ->
            wrap Login LoginMsg (Page.Login.init model.session (queryParam "next" url))

        Just (Route.Invite code) ->
            wrap Invite InviteMsg (Page.Invite.init model.session code)

        Just Route.WorkspaceNew ->
            wrap WorkspaceNew WorkspaceNewMsg (Page.WorkspaceNew.init model.session)

        Just (Route.Home slug) ->
            wrap Home HomeMsg (Page.Home.init model.session slug)

        Just (Route.Welcome slug) ->
            wrap Welcome WelcomeMsg (Page.Welcome.init model.session slug)

        Just (Route.Docs slug) ->
            wrap Docs DocsMsg (Page.Docs.init model.session slug Nothing)

        Just (Route.DocsView slug name) ->
            wrap Docs DocsMsg (Page.Docs.init model.session slug (Just name))

        Just (Route.DocShow slug docSlug) ->
            wrap DocShow DocShowMsg (Page.DocShow.init model.session slug docSlug Nothing)

        Just (Route.DocShowVersion slug docSlug version) ->
            wrap DocShow DocShowMsg (Page.DocShow.init model.session slug docSlug (Just version))

        Just (Route.Activity slug) ->
            wrap Activity ActivityMsg (Page.Activity.init model.session slug)

        Just (Route.DataSources slug) ->
            wrap DataSources DataSourcesMsg (Page.DataSources.init model.session slug)

        Just (Route.Team slug) ->
            wrap Team TeamMsg (Page.Team.init model.session slug)

        Just (Route.Settings slug) ->
            wrap Settings SettingsMsg (Page.Settings.init model.session slug)


{-| Read one query parameter from the raw query string (Route parses
paths only; ?next= on /login is the lone query-param dependency).
-}
queryParam : String -> Url -> Maybe String
queryParam name url =
    url.query
        |> Maybe.andThen
            (\q ->
                String.split "&" q
                    |> List.filterMap
                        (\pair ->
                            case String.split "=" pair of
                                key :: rest ->
                                    if key == name then
                                        Url.percentDecode (String.join "=" rest)

                                    else
                                        Nothing

                                [] ->
                                    Nothing
                        )
                    |> List.head
            )


{-| Keep sidebar data in step with the route: entering a workspace
fetches the switcher's workspace list + the viewer's views for that
workspace; navigating within the same workspace reuses what we have;
bare (auth) routes drop the chrome.
-}
syncChrome : Maybe Route -> Model -> ( Maybe ChromeModel, Cmd Msg )
syncChrome route model =
    case route |> Maybe.andThen Route.workspaceSlug of
        Nothing ->
            ( Nothing, Cmd.none )

        Just slug ->
            case model.chrome of
                Just chrome ->
                    if chrome.slug == slug then
                        ( Just chrome, Cmd.none )

                    else
                        enterWorkspace model.session slug

                Nothing ->
                    enterWorkspace model.session slug


enterWorkspace : Session -> String -> ( Maybe ChromeModel, Cmd Msg )
enterWorkspace session slug =
    ( Just { slug = slug, workspaces = [], sections = Nothing }
    , Cmd.batch
        [ Api.Workspaces.fetch session GotChromeWorkspaces
        , Api.Docs.fetchViews session slug (GotChromeViews slug)
        ]
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        step toPage toMsg pageUpdate pageMsg pageModel =
            let
                ( newPageModel, cmd ) =
                    pageUpdate pageMsg pageModel
            in
            ( { model | page = toPage newPageModel }, Cmd.map toMsg cmd )
    in
    case ( msg, model.page ) of
        ( LinkClicked (Browser.Internal url), _ ) ->
            case Route.fromUrl url of
                Just _ ->
                    ( model, Nav.pushUrl model.key (Url.toString url) )

                Nothing ->
                    -- Same-origin but not an SPA route (e.g. /logout):
                    -- hand it to the server like the LV's plain <a>.
                    ( model, Nav.load (Url.toString url) )

        ( LinkClicked (Browser.External href), _ ) ->
            ( model, Nav.load href )

        ( UrlChanged url, _ ) ->
            routeTo url model

        ( SignupMsg m, Signup pm ) ->
            step Signup SignupMsg Page.Signup.update m pm

        ( LoginMsg m, Login pm ) ->
            step Login LoginMsg Page.Login.update m pm

        ( InviteMsg m, Invite pm ) ->
            step Invite InviteMsg Page.Invite.update m pm

        ( WorkspaceNewMsg m, WorkspaceNew pm ) ->
            step WorkspaceNew WorkspaceNewMsg Page.WorkspaceNew.update m pm

        ( HomeMsg m, Home pm ) ->
            step Home HomeMsg Page.Home.update m pm

        ( WelcomeMsg m, Welcome pm ) ->
            step Welcome WelcomeMsg Page.Welcome.update m pm

        ( DocsMsg m, Docs pm ) ->
            step Docs DocsMsg Page.Docs.update m pm

        ( DocShowMsg m, DocShow pm ) ->
            step DocShow DocShowMsg Page.DocShow.update m pm

        ( ActivityMsg m, Activity pm ) ->
            step Activity ActivityMsg Page.Activity.update m pm

        ( DataSourcesMsg m, DataSources pm ) ->
            step DataSources DataSourcesMsg Page.DataSources.update m pm

        ( TeamMsg m, Team pm ) ->
            step Team TeamMsg Page.Team.update m pm

        ( SettingsMsg m, Settings pm ) ->
            step Settings SettingsMsg Page.Settings.update m pm

        ( GotChromeWorkspaces result, _ ) ->
            case ( result, model.chrome ) of
                ( Ok workspaces, Just chrome ) ->
                    ( { model | chrome = Just { chrome | workspaces = workspaces } }
                    , Cmd.none
                    )

                _ ->
                    -- Load failure (or chrome already dropped): keep the
                    -- shell rendering with what it has.
                    ( model, Cmd.none )

        ( GotChromeViews slug result, _ ) ->
            case ( result, model.chrome ) of
                ( Ok views, Just chrome ) ->
                    if chrome.slug == slug then
                        ( { model
                            | chrome =
                                Just { chrome | sections = Just (Chrome.sectionsFromViews views) }
                          }
                        , Cmd.none
                        )

                    else
                        -- Stale response from a workspace we've left.
                        ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )


view : Model -> Document Msg
view model =
    { title =
        case model.route of
            Just route ->
                Chrome.documentTitle route (workspaceName model)

            Nothing ->
                "Aveline"
    , body =
        [ case model.chrome of
            Just chrome ->
                Chrome.view (chromeConfig model chrome) (viewPage model)

            Nothing ->
                viewPage model
        ]
    }


{-| The current workspace's display name, once GET /papi/workspaces has
answered.
-}
workspaceName : Model -> Maybe String
workspaceName model =
    model.chrome
        |> Maybe.andThen
            (\chrome ->
                chrome.workspaces
                    |> List.filter (\w -> w.slug == chrome.slug)
                    |> List.head
                    |> Maybe.map .name
            )


chromeConfig : Model -> ChromeModel -> Chrome.Config
chromeConfig model chrome =
    { slug = chrome.slug
    , workspaceName = Maybe.withDefault chrome.slug (workspaceName model)
    , workspaces = chrome.workspaces
    , sections = chrome.sections
    , navActive =
        model.route
            |> Maybe.map Chrome.navActiveFor
            |> Maybe.withDefault Chrome.NavNone
    , user = model.session.user
    }


viewPage : Model -> Html Msg
viewPage model =
    case model.page of
        NotFound ->
            Html.text "Not found"

        Signup pm ->
            Html.map SignupMsg (Page.Signup.view pm)

        Login pm ->
            Html.map LoginMsg (Page.Login.view pm)

        Invite pm ->
            Html.map InviteMsg (Page.Invite.view pm)

        WorkspaceNew pm ->
            Html.map WorkspaceNewMsg (Page.WorkspaceNew.view pm)

        Home pm ->
            Html.map HomeMsg (Page.Home.view pm)

        Welcome pm ->
            Html.map WelcomeMsg (Page.Welcome.view pm)

        Docs pm ->
            Html.map DocsMsg (Page.Docs.view pm)

        DocShow pm ->
            Html.map DocShowMsg (Page.DocShow.view pm)

        Activity pm ->
            Html.map ActivityMsg (Page.Activity.view pm)

        DataSources pm ->
            Html.map DataSourcesMsg (Page.DataSources.view pm)

        Team pm ->
            Html.map TeamMsg (Page.Team.view pm)

        Settings pm ->
            Html.map SettingsMsg (Page.Settings.view pm)
