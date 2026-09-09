module UiChromeTest exposing (suite)

{-| Pure chrome logic (fe-chrome): nav-active mapping, document/topbar
title mapping, sidebar view sections, and Route.workspaceSlug.
-}

import Api.Docs exposing (ViewDef)
import Expect
import Route
import Test exposing (Test, describe, test)
import Ui.Chrome as Chrome


viewDef : String -> Bool -> Maybe { name : String, kind : String } -> ViewDef
viewDef name pinned bucket =
    { name = name
    , description = Nothing
    , config =
        { tags = []
        , groupBy = Nothing
        , subGroupBy = Nothing
        , sort = Nothing
        , edited = Nothing
        }
    , pinned = pinned
    , bucket = bucket
    }


suite : Test
suite =
    describe "Ui.Chrome"
        [ describe "navActiveFor"
            [ test "home" <|
                \_ -> Chrome.navActiveFor (Route.Home "acme") |> Expect.equal Chrome.NavHome
            , test "docs highlights Docs" <|
                \_ -> Chrome.navActiveFor (Route.Docs "acme") |> Expect.equal Chrome.NavAll
            , test "a saved view highlights that view's item" <|
                \_ ->
                    Chrome.navActiveFor (Route.DocsView "acme" "Roadmap")
                        |> Expect.equal (Chrome.NavView "Roadmap")
            , test "data sources" <|
                \_ ->
                    Chrome.navActiveFor (Route.DataSources "acme")
                        |> Expect.equal Chrome.NavDataSources
            , test "activity" <|
                \_ -> Chrome.navActiveFor (Route.Activity "acme") |> Expect.equal Chrome.NavActivity
            , test "team" <|
                \_ -> Chrome.navActiveFor (Route.Team "acme") |> Expect.equal Chrome.NavTeam
            , test "welcome highlights Connect agent" <|
                \_ -> Chrome.navActiveFor (Route.Welcome "acme") |> Expect.equal Chrome.NavConnect
            , test "settings" <|
                \_ -> Chrome.navActiveFor (Route.Settings "acme") |> Expect.equal Chrome.NavSettings
            , test "doc show highlights nothing (matches LV)" <|
                \_ -> Chrome.navActiveFor (Route.DocShow "acme" "spec") |> Expect.equal Chrome.NavNone
            , test "historical doc version highlights nothing" <|
                \_ ->
                    Chrome.navActiveFor (Route.DocShowVersion "acme" "spec" "3")
                        |> Expect.equal Chrome.NavNone
            , test "auth routes highlight nothing" <|
                \_ -> Chrome.navActiveFor Route.Login |> Expect.equal Chrome.NavNone
            ]
        , describe "topbarTitle"
            [ test "home" <|
                \_ -> Chrome.topbarTitle (Route.Home "acme") |> Expect.equal (Just "Home")
            , test "docs" <|
                \_ -> Chrome.topbarTitle (Route.Docs "acme") |> Expect.equal (Just "Docs")
            , test "saved view uses the view name" <|
                \_ ->
                    Chrome.topbarTitle (Route.DocsView "acme" "Roadmap")
                        |> Expect.equal (Just "Roadmap")
            , test "activity" <|
                \_ -> Chrome.topbarTitle (Route.Activity "acme") |> Expect.equal (Just "Activity")
            , test "data sources" <|
                \_ ->
                    Chrome.topbarTitle (Route.DataSources "acme")
                        |> Expect.equal (Just "Data sources")
            , test "team" <|
                \_ -> Chrome.topbarTitle (Route.Team "acme") |> Expect.equal (Just "Team")
            , test "settings" <|
                \_ -> Chrome.topbarTitle (Route.Settings "acme") |> Expect.equal (Just "Settings")
            , test "doc show has no shell-known title" <|
                \_ -> Chrome.topbarTitle (Route.DocShow "acme" "spec") |> Expect.equal Nothing
            , test "auth routes have none" <|
                \_ -> Chrome.topbarTitle Route.Signup |> Expect.equal Nothing
            ]
        , describe "documentTitle (mirrors LV page_title)"
            [ test "home with workspace name" <|
                \_ ->
                    Chrome.documentTitle (Route.Home "acme") (Just "Acme")
                        |> Expect.equal "Aveline · Acme"
            , test "home before workspace name loads" <|
                \_ ->
                    Chrome.documentTitle (Route.Home "acme") Nothing
                        |> Expect.equal "Aveline"
            , test "welcome" <|
                \_ ->
                    Chrome.documentTitle (Route.Welcome "acme") (Just "Acme")
                        |> Expect.equal "Aveline · Welcome to Acme"
            , test "team" <|
                \_ ->
                    Chrome.documentTitle (Route.Team "acme") (Just "Acme")
                        |> Expect.equal "Aveline · Team · Acme"
            , test "activity" <|
                \_ ->
                    Chrome.documentTitle (Route.Activity "acme") (Just "Acme")
                        |> Expect.equal "Aveline · Activity · Acme"
            , test "data sources" <|
                \_ ->
                    Chrome.documentTitle (Route.DataSources "acme") (Just "Acme")
                        |> Expect.equal "Aveline · Data sources · Acme"
            , test "settings ignores workspace name (LV does too)" <|
                \_ ->
                    Chrome.documentTitle (Route.Settings "acme") (Just "Acme")
                        |> Expect.equal "Aveline · Settings"
            , test "docs list" <|
                \_ ->
                    Chrome.documentTitle (Route.Docs "acme") (Just "Acme")
                        |> Expect.equal "Aveline · Acme"
            , test "login" <|
                \_ ->
                    Chrome.documentTitle Route.Login Nothing
                        |> Expect.equal "Aveline · Log in"
            , test "signup" <|
                \_ ->
                    Chrome.documentTitle Route.Signup Nothing
                        |> Expect.equal "Aveline · Sign up"
            , test "new workspace" <|
                \_ ->
                    Chrome.documentTitle Route.WorkspaceNew Nothing
                        |> Expect.equal "Aveline · New workspace"
            ]
        , describe "sectionsFromViews (mirrors Views.sidebar_sections)"
            [ test "only pinned views appear" <|
                \_ ->
                    Chrome.sectionsFromViews
                        [ viewDef "Pinned" True (Just { name = "Team", kind = "team" })
                        , viewDef "Unpinned" False (Just { name = "Team", kind = "team" })
                        ]
                        |> .team
                        |> List.map .name
                        |> Expect.equal [ "Pinned" ]
            , test "splits team / personal / project buckets" <|
                \_ ->
                    let
                        sections =
                            Chrome.sectionsFromViews
                                [ viewDef "Beta" True (Just { name = "Proj B", kind = "project" })
                                , viewDef "Mine" True (Just { name = "personal-arie", kind = "personal" })
                                , viewDef "Roadmap" True (Just { name = "Team", kind = "team" })
                                , viewDef "Alpha" True (Just { name = "Proj A", kind = "project" })
                                ]
                    in
                    ( List.map .name sections.team
                    , List.map .name sections.yours
                    , List.map (\b -> ( b.name, List.map .name b.views )) sections.buckets
                    )
                        |> Expect.equal
                            ( [ "Roadmap" ]
                            , [ "Mine" ]
                            , [ ( "Proj A", [ "Alpha" ] ), ( "Proj B", [ "Beta" ] ) ]
                            )
            , test "views within a project bucket sort by name" <|
                \_ ->
                    Chrome.sectionsFromViews
                        [ viewDef "Zed" True (Just { name = "Proj", kind = "project" })
                        , viewDef "Abe" True (Just { name = "Proj", kind = "project" })
                        ]
                        |> .buckets
                        |> List.map (\b -> List.map .name b.views)
                        |> Expect.equal [ [ "Abe", "Zed" ] ]
            , test "bucketless pinned views are dropped" <|
                \_ ->
                    Chrome.sectionsFromViews [ viewDef "Orphan" True Nothing ]
                        |> Expect.equal { team = [], yours = [], buckets = [] }
            ]
        , describe "Route.workspaceSlug"
            [ test "workspace routes carry their slug" <|
                \_ ->
                    [ Route.Home "acme"
                    , Route.Welcome "acme"
                    , Route.Docs "acme"
                    , Route.DocsView "acme" "Roadmap"
                    , Route.DocShow "acme" "spec"
                    , Route.DocShowVersion "acme" "spec" "2"
                    , Route.Activity "acme"
                    , Route.DataSources "acme"
                    , Route.Team "acme"
                    , Route.Settings "acme"
                    ]
                        |> List.map Route.workspaceSlug
                        |> Expect.equal (List.repeat 10 (Just "acme"))
            , test "auth routes are bare" <|
                \_ ->
                    [ Route.Signup, Route.Login, Route.Invite "abc", Route.WorkspaceNew ]
                        |> List.map Route.workspaceSlug
                        |> Expect.equal (List.repeat 4 Nothing)
            ]
        ]
