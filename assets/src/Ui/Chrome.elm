module Ui.Chrome exposing
    ( BucketGroup
    , Config
    , NavActive(..)
    , Sections
    , ViewItem
    , documentTitle
    , navActiveFor
    , sectionsFromViews
    , switcherClass
    , topbarTitle
    , view
    )

{-| The shared workspace shell (fe-chrome): Linear-style sidebar with
workspace switcher, nav items, saved-view sections and the collapse
toggle — a faithful port of `layouts/app.html.heex` (same HTML
structure and CSS classes, styled by `assets/css/app.css`).

Notes on parity with the LiveView:

  - The LV dropped its `.topbar` header in commit 1deb586 ("layout:
    drop both top nav bars"); the `topbar_title` assigns it still sets
    are vestigial and never rendered. We mirror that: `topbarTitle`
    exposes the per-route mapping for callers/tests, but `view` renders
    no topbar — the shell is sidebar + `.main-wrap` only.
  - Collapse state lives on `<html class="sidebar-collapsed">`, outside
    the Elm root, exactly like the LV's `SidebarCollapse` hook. The JS
    side is `assets/js/chrome.js` (event delegation on
    `[data-sidebar-toggle]` + localStorage persistence). Without that
    import the toggle button is inert and the sidebar stays expanded —
    the chrome degrades gracefully.
  - The workspace switcher is the opposite case: it is a native
    `<details>`, but Elm owns its `open` state (see
    `workspaceSwitcher`) so that navigating — or clicking outside, or
    Esc — closes it. `Config` therefore carries `switcherOpen` plus an
    `onSwitcherToggle` message; Main holds the flag.

-}

import Api.Docs
import Api.Workspaces exposing (Workspace)
import Html exposing (Html)
import Html.Attributes as Attr
import Html.Events as Events
import Json.Decode as Decode
import Json.Encode as Encode
import Route exposing (Route)
import Session
import Svg
import Svg.Attributes as SA



-- ===== Pure chrome logic =====


{-| Which sidebar item is highlighted — mirrors the LVs' `nav_active`
assigns (`:home`, `:all`, `{:view, name}`, `:data_sources`,
`:activity`, `:team`, `:connect`, `:settings`; DocShow sets none).
-}
type NavActive
    = NavHome
    | NavAll
    | NavView String
    | NavDataSources
    | NavActivity
    | NavTeam
    | NavConnect
    | NavSettings
    | NavNone


navActiveFor : Route -> NavActive
navActiveFor route =
    case route of
        Route.Home _ ->
            NavHome

        Route.Docs _ ->
            NavAll

        Route.DocsView _ name ->
            NavView name

        Route.DataSources _ ->
            NavDataSources

        Route.Activity _ ->
            NavActivity

        Route.Team _ ->
            NavTeam

        Route.Welcome _ ->
            NavConnect

        Route.Settings _ ->
            NavSettings

        Route.DocShow _ _ ->
            NavNone

        Route.DocShowVersion _ _ _ ->
            NavNone

        Route.Signup ->
            NavNone

        Route.Login ->
            NavNone

        Route.Invite _ ->
            NavNone

        Route.WorkspaceNew ->
            NavNone


{-| Per-route document title, mirroring each LiveView's `page_title`.
The second argument is the workspace name once the switcher data has
loaded; before that (or for DocShow, whose LV title uses the doc title
the shell doesn't know) we degrade to the route-only prefix.
-}
documentTitle : Route -> Maybe String -> String
documentTitle route wsName =
    let
        withWs parts =
            String.join " · " ("Aveline" :: parts ++ maybeToList wsName)

        maybeToList m =
            case m of
                Just x ->
                    [ x ]

                Nothing ->
                    []
    in
    case route of
        Route.Signup ->
            "Aveline · Sign up"

        Route.Login ->
            "Aveline · Log in"

        Route.Invite _ ->
            "Aveline · Invite"

        Route.WorkspaceNew ->
            "Aveline · New workspace"

        Route.Home _ ->
            withWs []

        Route.Docs _ ->
            withWs []

        Route.DocsView _ _ ->
            withWs []

        Route.DocShow _ _ ->
            withWs []

        Route.DocShowVersion _ _ _ ->
            withWs []

        Route.Welcome _ ->
            case wsName of
                Just name ->
                    "Aveline · Welcome to " ++ name

                Nothing ->
                    "Aveline · Welcome"

        Route.Activity _ ->
            withWs [ "Activity" ]

        Route.DataSources _ ->
            withWs [ "Data sources" ]

        Route.Team _ ->
            withWs [ "Team" ]

        Route.Settings _ ->
            "Aveline · Settings"


{-| Per-route topbar title, mirroring the LVs' `topbar_title` assigns
("Home", "Docs", view name for a saved view, …). Vestigial parity: the
LV keeps assigning these but no longer renders a topbar (commit
1deb586), so `view` doesn't either. `Nothing` for bare/auth routes and
for DocShow (whose title is the doc's, unknown to the shell).
-}
topbarTitle : Route -> Maybe String
topbarTitle route =
    case route of
        Route.Home _ ->
            Just "Home"

        Route.Docs _ ->
            Just "Docs"

        Route.DocsView _ name ->
            Just name

        Route.Activity _ ->
            Just "Activity"

        Route.DataSources _ ->
            Just "Data sources"

        Route.Team _ ->
            Just "Team"

        Route.Settings _ ->
            Just "Settings"

        Route.Welcome _ ->
            Just "Welcome"

        Route.DocShow _ _ ->
            Nothing

        Route.DocShowVersion _ _ _ ->
            Nothing

        Route.Signup ->
            Nothing

        Route.Login ->
            Nothing

        Route.Invite _ ->
            Nothing

        Route.WorkspaceNew ->
            Nothing


type alias ViewItem =
    { name : String
    , description : Maybe String
    }


type alias BucketGroup =
    { name : String
    , views : List ViewItem
    }


type alias Sections =
    { team : List ViewItem
    , yours : List ViewItem
    , buckets : List BucketGroup
    }


{-| Group the workspace's views into sidebar sections, mirroring
`Aveline.Views.sidebar_sections/2`: pinned views only; team-bucket
views first, then the viewer's personal bucket ("Yours"), then each
project bucket (sorted by bucket name, views name-sorted within).
-}
sectionsFromViews : List Api.Docs.ViewDef -> Sections
sectionsFromViews views =
    let
        pinned =
            List.filter .pinned views

        bucketKind v =
            Maybe.map .kind v.bucket

        toItem v =
            { name = v.name, description = v.description }

        byName =
            List.sortBy .name

        project =
            List.filter
                (\v ->
                    case v.bucket of
                        Just b ->
                            b.kind /= "team" && b.kind /= "personal"

                        Nothing ->
                            False
                )
                pinned

        bucketNames =
            project
                |> List.filterMap (\v -> Maybe.map .name v.bucket)
                |> unique
                |> List.sort

        bucketGroup name =
            { name = name
            , views =
                project
                    |> List.filter (\v -> Maybe.map .name v.bucket == Just name)
                    |> byName
                    |> List.map toItem
            }
    in
    { team =
        pinned
            |> List.filter (\v -> bucketKind v == Just "team")
            |> byName
            |> List.map toItem
    , yours =
        pinned
            |> List.filter (\v -> bucketKind v == Just "personal")
            |> byName
            |> List.map toItem
    , buckets = List.map bucketGroup bucketNames
    }


unique : List String -> List String
unique =
    List.foldr
        (\x acc ->
            if List.member x acc then
                acc

            else
                x :: acc
        )
        []



-- ===== View =====


type alias Config msg =
    { slug : String
    , workspaceName : String
    , workspaces : List Workspace
    , sections : Maybe Sections
    , navActive : NavActive
    , user : Maybe Session.User
    , switcherOpen : Bool
    , onSwitcherToggle : Bool -> msg
    }


{-| The workspace shell around a page's content — the `assigns[:workspace]`
branch of `layouts/app.html.heex`.
-}
view : Config msg -> Html msg -> Html msg
view config content =
    Html.div [ Attr.class "shell-sidebar", Attr.id "shell-sidebar" ]
        [ sidebar config
        , edgeToggle
        , Html.div [ Attr.class "main-wrap" ] [ content ]
        ]


sidebar : Config msg -> Html msg
sidebar config =
    Html.aside [ Attr.class "sidebar" ]
        (workspaceSwitcher config
            :: Html.div [ Attr.class "sidebar-section" ]
                (List.concat
                    [ [ sidebarItem (Route.Home config.slug) (config.navActive == NavHome) iconHome "Home"
                      , sidebarItem (Route.Docs config.slug) (config.navActive == NavAll) iconDocs "Docs"
                      ]
                    , viewSections config
                    , [ sidebarItem (Route.DataSources config.slug) (config.navActive == NavDataSources) iconDataSources "Data sources"
                      , sidebarItem (Route.Activity config.slug) (config.navActive == NavActivity) iconActivity "Activity"
                      , sidebarItem (Route.Team config.slug) (config.navActive == NavTeam) iconTeam "Team"
                      ]
                    ]
                )
            :: Html.div [ Attr.class "sidebar-spacer" ] []
            :: Html.div [ Attr.class "sidebar-section sidebar-section-bottom" ]
                [ Html.a
                    [ Attr.href (Route.href (Route.Welcome config.slug))
                    , Attr.classList
                        [ ( "sidebar-item", True )
                        , ( "active", config.navActive == NavConnect )
                        ]
                    , Attr.title "Connect your agent to this workspace"
                    ]
                    [ iconConnect
                    , Html.span [ Attr.class "label" ] [ Html.text "Connect agent" ]
                    ]
                , sidebarItem (Route.Settings config.slug) (config.navActive == NavSettings) iconSettings "Settings"
                ]
            :: sidebarFooter config.user
        )


{-| The workspace dropdown. It is a native `<details>`, but its open
state is owned by Elm: we mirror the model onto the `open` property and
learn about native opens/closes (summary clicks, keyboard activation)
from the element's `toggle` event. That is what lets navigation close
the menu — a plain `<details>` keeps its own state, so clicking a
workspace re-rendered the page with the menu still hanging open.
-}
workspaceSwitcher : Config msg -> Html msg
workspaceSwitcher config =
    Html.node "details"
        [ Attr.class switcherClass
        , Attr.property "open" (Encode.bool config.switcherOpen)
        , Events.on "toggle"
            (Decode.map config.onSwitcherToggle
                (Decode.at [ "target", "open" ] Decode.bool)
            )
        ]
        [ Html.node "summary"
            []
            [ Html.div [ Attr.class "sidebar-header" ]
                [ Html.span [ Attr.class "nav-brand-mark", Attr.title "Aveline" ] [ Html.text "A" ]
                , Html.div [ Attr.class "sidebar-workspace", Attr.title config.workspaceName ]
                    [ Html.text config.workspaceName ]
                , iconChevron
                ]
            ]
        , Html.div [ Attr.class "switcher-menu" ]
            (Html.div [ Attr.class "switcher-label" ] [ Html.text "Workspaces" ]
                :: List.map (switcherItem config.slug) config.workspaces
                ++ [ Html.div [ Attr.class "switcher-divider" ] []
                   , Html.a
                        [ Attr.href (Route.href Route.WorkspaceNew)
                        , Attr.class "switcher-item"
                        ]
                        [ iconPlus
                        , Html.span [] [ Html.text "New workspace" ]
                        ]
                   ]
            )
        ]


{-| The class the switcher's root carries; Main uses it to tell
clicks inside the open menu from clicks outside it.
-}
switcherClass : String
switcherClass =
    "workspace-switcher"


switcherItem : String -> Workspace -> Html msg
switcherItem currentSlug w =
    let
        current =
            w.slug == currentSlug
    in
    Html.a
        [ Attr.href (Route.href (Route.Home w.slug))
        , Attr.classList [ ( "switcher-item", True ), ( "current", current ) ]
        ]
        (Html.span [] [ Html.text w.name ]
            :: (if current then
                    [ Html.span [ Attr.class "check" ] [ Html.text "✓" ] ]

                else
                    []
               )
        )


viewSections : Config msg -> List (Html msg)
viewSections config =
    case config.sections of
        Nothing ->
            []

        Just sections ->
            List.concat
                [ if sections.team == [] then
                    []

                  else
                    [ Html.div [ Attr.class "sidebar-views" ]
                        (List.map (viewItemLink config) sections.team)
                    ]
                , if sections.yours == [] then
                    []

                  else
                    [ Html.div [ Attr.class "sidebar-views sidebar-views-scoped" ]
                        (Html.div [ Attr.class "sidebar-label" ] [ Html.text "Yours" ]
                            :: List.map (viewItemLink config) sections.yours
                        )
                    ]
                , List.map
                    (\group ->
                        Html.div [ Attr.class "sidebar-views sidebar-views-scoped" ]
                            (Html.div [ Attr.class "sidebar-label" ] [ Html.text group.name ]
                                :: List.map (viewItemLink config) group.views
                            )
                    )
                    sections.buckets
                ]


viewItemLink : Config msg -> ViewItem -> Html msg
viewItemLink config item =
    Html.a
        (List.concat
            [ [ Attr.href (Route.href (Route.DocsView config.slug item.name))
              , Attr.classList
                    [ ( "sidebar-item", True )
                    , ( "active", config.navActive == NavView item.name )
                    ]
              ]
            , case item.description of
                Just d ->
                    [ Attr.title d ]

                Nothing ->
                    []
            ]
        )
        [ Html.span [ Attr.class "label" ] [ Html.text item.name ] ]


sidebarItem : Route -> Bool -> Html msg -> String -> Html msg
sidebarItem route active icon label =
    Html.a
        [ Attr.href (Route.href route)
        , Attr.classList [ ( "sidebar-item", True ), ( "active", active ) ]
        ]
        [ icon
        , Html.span [ Attr.class "label" ] [ Html.text label ]
        ]


sidebarFooter : Maybe Session.User -> List (Html msg)
sidebarFooter maybeUser =
    case maybeUser of
        Nothing ->
            []

        Just user ->
            [ Html.div [ Attr.class "sidebar-footer" ]
                [ Html.div [ Attr.class "sidebar-user" ]
                    [ Html.span [ Attr.class "name" ] [ Html.text user.username ]
                    , Html.a
                        [ Attr.href "/logout"
                        , Attr.class "sidebar-logout"
                        , Attr.title "Log out"
                        , Attr.attribute "aria-label" "Log out"
                        ]
                        [ Html.span [ Attr.class "sidebar-logout-text" ] [ Html.text "log out" ]
                        , iconLogout
                        ]
                    ]
                ]
            ]


{-| The collapse toggle on the sidebar edge. Behavior (class toggle on
`<html>`, localStorage persistence) lives in assets/js/chrome.js via
the `data-sidebar-toggle` attribute; inert without it.
-}
edgeToggle : Html msg
edgeToggle =
    Html.button
        [ Attr.type_ "button"
        , Attr.attribute "data-sidebar-toggle" ""
        , Attr.class "sidebar-edge-toggle"
        , Attr.title "Toggle sidebar"
        , Attr.attribute "aria-label" "Toggle sidebar"
        ]
        [ Svg.svg
            [ SA.class "sidebar-edge-toggle-collapse"
            , SA.viewBox "0 0 24 24"
            , SA.fill "none"
            , SA.stroke "currentColor"
            , SA.strokeWidth "2"
            , SA.strokeLinecap "round"
            , SA.strokeLinejoin "round"
            ]
            [ Svg.polyline [ SA.points "15 18 9 12 15 6" ] [] ]
        , Svg.svg
            [ SA.class "sidebar-edge-toggle-expand"
            , SA.viewBox "0 0 24 24"
            , SA.fill "none"
            , SA.stroke "currentColor"
            , SA.strokeWidth "2"
            , SA.strokeLinecap "round"
            , SA.strokeLinejoin "round"
            ]
            [ Svg.polyline [ SA.points "9 18 15 12 9 6" ] [] ]
        ]



-- ===== Icons (verbatim from layouts/app.html.heex) =====


iconChevron : Html msg
iconChevron =
    Svg.svg
        [ SA.class "sidebar-header-chev"
        , SA.viewBox "0 0 16 16"
        , SA.fill "none"
        , SA.stroke "currentColor"
        , SA.strokeWidth "1.5"
        , SA.strokeLinecap "round"
        , SA.strokeLinejoin "round"
        ]
        [ Svg.path [ SA.d "M4 6l4 4 4-4" ] [] ]


iconPlus : Html msg
iconPlus =
    Svg.svg
        [ SA.class "actor-icon"
        , SA.viewBox "0 0 16 16"
        , SA.fill "none"
        , SA.stroke "currentColor"
        , SA.strokeWidth "1.6"
        , SA.strokeLinecap "round"
        ]
        [ Svg.path [ SA.d "M8 3.5v9M3.5 8h9" ] [] ]


iconHome : Html msg
iconHome =
    Svg.svg
        [ SA.class "icon"
        , SA.viewBox "0 0 16 16"
        , SA.fill "none"
        , SA.stroke "currentColor"
        , SA.strokeWidth "1.5"
        , SA.strokeLinejoin "round"
        ]
        [ Svg.path [ SA.d "M2.5 7.5L8 2.5l5.5 5v5.5a1 1 0 0 1-1 1h-9a1 1 0 0 1-1-1z" ] []
        , Svg.path [ SA.d "M6.5 14V9.5h3V14" ] []
        ]


iconDocs : Html msg
iconDocs =
    Svg.svg
        [ SA.class "icon"
        , SA.viewBox "0 0 16 16"
        , SA.fill "none"
        , SA.stroke "currentColor"
        , SA.strokeWidth "1.5"
        ]
        [ Svg.rect [ SA.x "2.5", SA.y "2.5", SA.width "11", SA.height "11", SA.rx "1.5" ] []
        , Svg.path [ SA.d "M5 6h6M5 8h6M5 10h4", SA.strokeLinecap "round" ] []
        ]


iconDataSources : Html msg
iconDataSources =
    Svg.svg
        [ SA.class "icon"
        , SA.viewBox "0 0 24 24"
        , SA.fill "none"
        , SA.stroke "currentColor"
        , SA.strokeWidth "1.7"
        , SA.strokeLinecap "round"
        , SA.strokeLinejoin "round"
        ]
        [ Svg.ellipse [ SA.cx "12", SA.cy "5", SA.rx "9", SA.ry "3" ] []
        , Svg.path [ SA.d "M3 5v14a9 3 0 0 0 18 0V5" ] []
        , Svg.path [ SA.d "M3 12a9 3 0 0 0 18 0" ] []
        ]


iconActivity : Html msg
iconActivity =
    Svg.svg
        [ SA.class "icon"
        , SA.viewBox "0 0 24 24"
        , SA.fill "none"
        , SA.stroke "currentColor"
        , SA.strokeWidth "1.7"
        , SA.strokeLinecap "round"
        , SA.strokeLinejoin "round"
        ]
        [ Svg.polyline [ SA.points "22 12 18 12 15 21 9 3 6 12 2 12" ] [] ]


iconTeam : Html msg
iconTeam =
    Svg.svg
        [ SA.class "icon"
        , SA.viewBox "0 0 16 16"
        , SA.fill "none"
        , SA.stroke "currentColor"
        , SA.strokeWidth "1.5"
        ]
        [ Svg.circle [ SA.cx "6", SA.cy "6", SA.r "2.2" ] []
        , Svg.circle [ SA.cx "11", SA.cy "6.5", SA.r "1.7" ] []
        , Svg.path
            [ SA.d "M2.5 13c0-2 1.7-3.2 3.5-3.2s3.5 1.2 3.5 3.2M9.7 13c0-1.4 1.2-2.4 2.7-2.4s2.6 1 2.6 2.4"
            , SA.strokeLinecap "round"
            ]
            []
        ]


iconConnect : Html msg
iconConnect =
    Svg.svg
        [ SA.class "icon"
        , SA.viewBox "0 0 24 24"
        , SA.fill "none"
        , SA.stroke "currentColor"
        , SA.strokeWidth "1.7"
        , SA.strokeLinecap "round"
        , SA.strokeLinejoin "round"
        ]
        [ Svg.path [ SA.d "M13 2L3 14h7l-1 8 10-12h-7l1-8z" ] [] ]


iconSettings : Html msg
iconSettings =
    Svg.svg
        [ SA.class "icon"
        , SA.viewBox "0 0 24 24"
        , SA.fill "none"
        , SA.stroke "currentColor"
        , SA.strokeWidth "1.6"
        , SA.strokeLinecap "round"
        , SA.strokeLinejoin "round"
        ]
        [ Svg.path [ SA.d "M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09a1.65 1.65 0 0 0-1-1.51 1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09a1.65 1.65 0 0 0 1.51-1 1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33h.04a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82v.04a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" ] []
        , Svg.circle [ SA.cx "12", SA.cy "12", SA.r "3" ] []
        ]


iconLogout : Html msg
iconLogout =
    Svg.svg
        [ SA.class "sidebar-logout-icon"
        , SA.viewBox "0 0 24 24"
        , SA.fill "none"
        , SA.stroke "currentColor"
        , SA.strokeWidth "1.8"
        , SA.strokeLinecap "round"
        , SA.strokeLinejoin "round"
        ]
        [ Svg.path [ SA.d "M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" ] []
        , Svg.polyline [ SA.points "16 17 21 12 16 7" ] []
        , Svg.line [ SA.x1 "21", SA.y1 "12", SA.x2 "9", SA.y2 "12" ] []
        ]
