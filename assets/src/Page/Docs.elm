module Page.Docs exposing (Model, Msg, init, update, view)

{-| The docs index — port of lib/aveline\_web/live/workspace\_show\_live.ex.

List / filter / search / sort / group, saved views (the `/v/:view_name`
route lands here with `Just viewName`), facet counts, the view switcher.
Renders only the main content region (`div.content`); the coordinator
adds shared chrome (sidebar, topbar, flash) later.

State that lived in the LV's URL query params (tag/author/group/…)
lives in the page model here — the shared Route surface doesn't carry
query params yet (reported as a deferred need).

-}

import Api
import Api.Docs as ApiDocs exposing (DocSummary, Facets, Member, TagInfo, ViewDef)
import Dict exposing (Dict)
import Html exposing (Html, a, button, div, form, h1, input, li, p, span, text, ul)
import Html.Attributes exposing (attribute, autocomplete, class, hidden, href, id, name, placeholder, title, type_, value)
import Html.Events exposing (onClick, onInput, onSubmit)
import Page.Docs.Logic as Logic exposing (Knobs, Sort(..))
import Route
import Session exposing (Session)
import Set exposing (Set)
import Svg
import Svg.Attributes as SA
import Task
import Time
import Ui.DocCard


type alias Model =
    { session : Session
    , slug : String
    , viewName : Maybe String
    , now : Maybe Time.Posix
    , workspaceTags : List TagInfo
    , tagsLoaded : Bool
    , authors : List String
    , views : Maybe (List ViewDef)
    , currentView : Maybe ViewDef
    , viewNotFound : Bool
    , knobs : Knobs
    , searchInput : String
    , docs : List DocSummary
    , docsLoaded : Bool
    , hasMore : Bool
    , facetTags : Dict String Int
    , facetAuthors : Dict String Int
    , openMenu : Maybe String
    , collapsed : Set String
    , error : Maybe String
    }


type Msg
    = GotNow Time.Posix
    | GotTags (Result Api.Error (List TagInfo))
    | GotMembers (Result Api.Error (List Member))
    | GotViews (Result Api.Error (List ViewDef))
    | GotDocs (Result Api.Error ApiDocs.DocsPage)
    | GotMoreDocs (Result Api.Error ApiDocs.DocsPage)
    | GotFacets (Result Api.Error Facets)
    | ToggleMenu String
    | CloseMenus
    | ToggleTag String
    | ToggleAuthor String
    | SetEdited (Maybe String)
    | SetGroup (Maybe String)
    | SetSubgroup (Maybe String)
    | SetSort Sort
    | ClearFilters
    | ResetView
    | SearchChanged String
    | SearchSubmitted
    | LoadMore
    | ToggleSection String


init : Session -> String -> Maybe String -> ( Model, Cmd Msg )
init session slug viewName =
    let
        model =
            { session = session
            , slug = slug
            , viewName = viewName
            , now = Nothing
            , workspaceTags = []
            , tagsLoaded = False
            , authors = []
            , views = Nothing
            , currentView = Nothing
            , viewNotFound = False
            , knobs = Logic.defaultKnobs
            , searchInput = ""
            , docs = []
            , docsLoaded = False
            , hasMore = False
            , facetTags = Dict.empty
            , facetAuthors = Dict.empty
            , openMenu = Nothing
            , collapsed = Set.empty
            , error = Nothing
            }
    in
    ( model
    , Cmd.batch
        ([ Task.perform GotNow Time.now
         , ApiDocs.fetchTags session slug GotTags
         , ApiDocs.fetchMembers session slug GotMembers
         , ApiDocs.fetchViews session slug GotViews
         ]
            ++ (case viewName of
                    -- On a view URL the knobs seed from the saved
                    -- config, which needs /views (and /tags for scope
                    -- validation) first — see trySeedView.
                    Just _ ->
                        []

                    Nothing ->
                        [ fetchList model, fetchFacetCounts model ]
               )
        )
    )


tagSlugs : Model -> List String
tagSlugs model =
    List.map .slug model.workspaceTags


tagColors : Model -> Dict String String
tagColors model =
    model.workspaceTags
        |> List.filterMap (\t -> t.color |> Maybe.map (\c -> ( t.slug, c )))
        |> Dict.fromList


fetchList : Model -> Cmd Msg
fetchList model =
    ApiDocs.fetchDocs model.session
        model.slug
        model.knobs
        { sort = Logic.sortToParam model.knobs.sort, offset = 0 }
        GotDocs


fetchFacetCounts : Model -> Cmd Msg
fetchFacetCounts model =
    ApiDocs.fetchFacets model.session model.slug model.knobs GotFacets


{-| Every knob change refetches the list and the corpus-wide facet
counts — the Elm analogue of the LV's push\_patch → handle\_params.
-}
applyKnobs : Model -> Knobs -> ( Model, Cmd Msg )
applyKnobs model knobs =
    let
        newModel =
            { model | knobs = knobs }
    in
    ( newModel, Cmd.batch [ fetchList newModel, fetchFacetCounts newModel ] )


{-| On a `/v/:view_name` URL: once views AND tags are in, resolve the
view and seed the knobs from its config (pristine load). A view that
doesn't exist — or that the viewer can't use; /views only returns
usable ones — resolves like one that doesn't exist.
-}
trySeedView : Model -> ( Model, Cmd Msg )
trySeedView model =
    case ( model.viewName, model.views, model.tagsLoaded ) of
        ( Just name, Just views, True ) ->
            case List.filter (\v -> v.name == name) views |> List.head of
                Just v ->
                    let
                        newModel =
                            { model
                                | currentView = Just v
                                , knobs = Logic.seedKnobs (tagSlugs model) v.config
                            }
                    in
                    ( newModel, Cmd.batch [ fetchList newModel, fetchFacetCounts newModel ] )

                Nothing ->
                    ( { model | viewNotFound = True }, Cmd.none )

        _ ->
            ( model, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotNow now ->
            ( { model | now = Just now }, Cmd.none )

        GotTags (Ok tags) ->
            trySeedView { model | workspaceTags = tags, tagsLoaded = True }

        GotTags (Err err) ->
            ( { model | error = Just (Api.errorMessage err), tagsLoaded = True }, Cmd.none )

        GotMembers (Ok members) ->
            -- LV sorts author chips by username.
            ( { model | authors = members |> List.map .username |> List.sort }, Cmd.none )

        GotMembers (Err err) ->
            ( { model | error = Just (Api.errorMessage err) }, Cmd.none )

        GotViews (Ok views) ->
            trySeedView { model | views = Just views }

        GotViews (Err err) ->
            ( { model | error = Just (Api.errorMessage err) }, Cmd.none )

        GotDocs (Ok page) ->
            ( { model | docs = page.docs, hasMore = page.hasMore, docsLoaded = True }
            , Cmd.none
            )

        GotDocs (Err err) ->
            ( { model | error = Just (Api.errorMessage err), docsLoaded = True }, Cmd.none )

        GotMoreDocs (Ok page) ->
            ( { model | docs = model.docs ++ page.docs, hasMore = page.hasMore }, Cmd.none )

        GotMoreDocs (Err err) ->
            ( { model | error = Just (Api.errorMessage err) }, Cmd.none )

        GotFacets (Ok facets) ->
            ( { model | facetTags = facets.tags, facetAuthors = facets.authors }, Cmd.none )

        GotFacets (Err err) ->
            ( { model | error = Just (Api.errorMessage err) }, Cmd.none )

        ToggleMenu menuId ->
            ( { model
                | openMenu =
                    if model.openMenu == Just menuId then
                        Nothing

                    else
                        Just menuId
              }
            , Cmd.none
            )

        CloseMenus ->
            ( { model | openMenu = Nothing }, Cmd.none )

        ToggleTag tag ->
            let
                knobs =
                    model.knobs
            in
            applyKnobs model { knobs | tags = toggleIn tag knobs.tags }

        ToggleAuthor username ->
            let
                knobs =
                    model.knobs
            in
            applyKnobs model { knobs | authors = toggleIn username knobs.authors }

        SetEdited within ->
            let
                knobs =
                    model.knobs
            in
            applyKnobs { model | openMenu = Nothing } { knobs | edited = within }

        SetGroup group ->
            let
                knobs =
                    model.knobs
            in
            -- Clearing or changing the group invalidates any sub-group.
            -- Menu stays open so "Then by" is reachable, same as the LV.
            applyKnobs model { knobs | groupBy = group, subGroupBy = Nothing }

        SetSubgroup group ->
            let
                knobs =
                    model.knobs
            in
            applyKnobs model { knobs | subGroupBy = group }

        SetSort sort ->
            let
                knobs =
                    model.knobs
            in
            applyKnobs { model | openMenu = Nothing } { knobs | sort = sort }

        ClearFilters ->
            let
                knobs =
                    model.knobs
            in
            -- Sort survives Clear all, exactly like the LV's clear_filters.
            applyKnobs { model | searchInput = "" }
                { knobs
                    | tags = []
                    , authors = []
                    , groupBy = Nothing
                    , subGroupBy = Nothing
                    , edited = Nothing
                    , search = ""
                }

        ResetView ->
            -- Back to the saved view: re-seed the knobs from config.
            case model.currentView of
                Just v ->
                    applyKnobs { model | searchInput = "" }
                        (Logic.seedKnobs (tagSlugs model) v.config)

                Nothing ->
                    ( model, Cmd.none )

        SearchChanged input ->
            ( { model | searchInput = input }, Cmd.none )

        SearchSubmitted ->
            let
                knobs =
                    model.knobs
            in
            applyKnobs model { knobs | search = model.searchInput }

        LoadMore ->
            ( model
            , ApiDocs.fetchDocs model.session
                model.slug
                model.knobs
                { sort = Logic.sortToParam model.knobs.sort, offset = List.length model.docs }
                GotMoreDocs
            )

        ToggleSection key ->
            ( { model
                | collapsed =
                    if Set.member key model.collapsed then
                        Set.remove key model.collapsed

                    else
                        Set.insert key model.collapsed
              }
            , Cmd.none
            )


toggleIn : String -> List String -> List String
toggleIn x xs =
    if List.member x xs then
        List.filter ((/=) x) xs

    else
        xs ++ [ x ]



-- ===== View =====


view : Model -> Html Msg
view model =
    if model.viewNotFound then
        -- The LV redirects to /docs with a "View not found." flash; the
        -- page has no Nav.Key, so render the message in place instead.
        div [ class "content" ]
            [ div [ class "empty" ]
                [ text "View not found. "
                , a [ href (Route.href (Route.Docs model.slug)) ] [ text "All docs" ]
                ]
            ]

    else
        div [ class "content" ]
            (List.concat
                [ clickAwayOverlay model
                , [ div [ class "docs-head" ]
                        (viewTitle model ++ viewModifiedBadge model)
                  , p [ class "page-subtitle docs-subtitle" ] (viewSubtitle model)
                  , div [ class "docs-controls" ]
                        [ div [ class "filter-bar" ] [ viewSearchRow model ]
                        , div [ class "fbar" ] (viewFbar model)
                        ]
                  ]
                , viewList model
                ]
            )


{-| Stand-in for the LV's phx-click-away: a transparent fixed layer just
under the open menu (fdd menus are z-index 30). Escape-to-close is not
ported — page subscriptions aren't wired in Main.
-}
clickAwayOverlay : Model -> List (Html Msg)
clickAwayOverlay model =
    case model.openMenu of
        Nothing ->
            []

        Just _ ->
            [ div
                [ attribute "style" "position:fixed;inset:0;z-index:29"
                , onClick CloseMenus
                ]
                []
            ]


viewTitle : Model -> List (Html Msg)
viewTitle model =
    let
        views =
            Maybe.withDefault [] model.views
    in
    if views == [] then
        [ h1 [ class "page-title" ] [ text "Docs" ] ]

    else
        [ div [ class "title-fdd", id "fdd-view" ]
            [ h1 [ class "page-title" ]
                [ button
                    [ type_ "button", class "title-fdd-btn", onClick (ToggleMenu "fdd-view") ]
                    [ text (model.currentView |> Maybe.map .name |> Maybe.withDefault "Docs")
                    , chevronSvg "title-chev" "2.2"
                    ]
                ]
            , div
                [ class "fdd-menu title-fdd-menu"
                , id "fdd-view-menu"
                , hidden (model.openMenu /= Just "fdd-view")
                ]
                (viewSwitcherMenu model views)
            ]
        ]


viewSwitcherMenu : Model -> List ViewDef -> List (Html Msg)
viewSwitcherMenu model views =
    let
        sections =
            Logic.viewSections views

        sectionHeaders =
            sections.yours /= [] || sections.buckets /= []

        rows =
            List.map (vmenuViewRow model)
    in
    List.concat
        [ [ a
                [ href (Route.href (Route.Docs model.slug)), class "vmenu-item" ]
                [ span [ class (radioClass (model.currentView == Nothing)) ] []
                , span [ class "vmenu-body" ]
                    [ span [ class "vmenu-name" ] [ text "All docs" ]
                    , span [ class "vmenu-desc" ] [ text "Everything written in this workspace." ]
                    ]
                ]
          ]
        , if sectionHeaders && sections.team /= [] then
            [ div [ class "fdd-section" ] [ text "Team" ] ]

          else
            []
        , rows sections.team
        , if sections.yours /= [] then
            [ div [ class "fdd-section" ] [ text "Yours" ] ]

          else
            []
        , rows sections.yours
        , List.concatMap
            (\( bucket, bucketViews ) ->
                div [ class "fdd-section" ] [ text bucket.name ] :: rows bucketViews
            )
            sections.buckets
        ]


vmenuViewRow : Model -> ViewDef -> Html Msg
vmenuViewRow model v =
    let
        current =
            (model.currentView |> Maybe.map .name) == Just v.name
    in
    a
        [ href (Route.href (Route.DocsView model.slug v.name)), class "vmenu-item" ]
        [ span [ class (radioClass current) ] []
        , span [ class "vmenu-body" ]
            [ span [ class "vmenu-name" ]
                (List.concat
                    [ [ text v.name ]
                    , if (v.bucket |> Maybe.map .kind) == Just "personal" then
                        [ vmenuLockSvg ]

                      else
                        []
                    , if v.pinned then
                        [ vmenuPinSvg ]

                      else
                        []
                    ]
                )
            , span [ class "vmenu-desc" ] [ text (Maybe.withDefault "" v.description) ]
            ]
        ]


modified : Model -> Bool
modified model =
    case model.currentView of
        Just v ->
            Logic.isModified (tagSlugs model) v.config model.knobs

        Nothing ->
            False


viewModifiedBadge : Model -> List (Html Msg)
viewModifiedBadge model =
    if modified model then
        [ span [ class "view-modified" ]
            [ text "modified "
            , button [ type_ "button", class "view-reset", onClick ResetView ] [ text "reset" ]
            ]
        ]

    else
        []


viewSubtitle : Model -> List (Html Msg)
viewSubtitle model =
    case model.currentView of
        Just v ->
            [ text (Maybe.withDefault "" v.description) ]

        Nothing ->
            [ text "Everything written in "
            , span [ class "mono" ] [ text model.slug ]
            , text ". Filter, search, sort, group."
            ]


viewSearchRow : Model -> Html Msg
viewSearchRow model =
    div [ class "filter-row" ]
        [ span [ class "filter-row-icon", title "Search" ] [ searchSvg ]
        , form [ class "filter-row-form", onSubmit SearchSubmitted ]
            [ input
                [ type_ "text"
                , name "value"
                , value model.searchInput
                , placeholder "Search docs by title & content"
                , class "search-input"
                , autocomplete False
                , onInput SearchChanged
                ]
                []
            ]
        ]


viewFbar : Model -> List (Html Msg)
viewFbar model =
    List.concat
        [ if model.workspaceTags /= [] then
            [ viewTagFdd model ]

          else
            []
        , if model.authors /= [] then
            [ viewAuthorFdd model ]

          else
            []
        , [ viewGroupFdd model
          , viewEditedFdd model
          , viewSortFdd model
          ]
        , viewClearAll model
        ]


viewTagFdd : Model -> Html Msg
viewTagFdd model =
    let
        ( plain, scoped ) =
            Logic.groupedTags (tagSlugs model)

        item tag label =
            button
                [ type_ "button", class "fdd-item", onClick (ToggleTag tag) ]
                [ span [ class (checkClass (List.member tag model.knobs.tags)) ] []
                , span [ class "fdd-item-label" ] [ text label ]
                , span [ class "fdd-item-count" ]
                    [ text (String.fromInt (Dict.get tag model.facetTags |> Maybe.withDefault 0)) ]
                ]
    in
    fdd model
        { menuId = "fdd-tag", label = "Tag", count = List.length model.knobs.tags }
        (List.map (\tag -> item tag tag) plain
            ++ List.concatMap
                (\( scope, values ) ->
                    div [ class "fdd-section" ] [ text scope ]
                        :: List.map (\tag -> item tag (Logic.valueOf tag)) values
                )
                scoped
        )


viewAuthorFdd : Model -> Html Msg
viewAuthorFdd model =
    fdd model
        { menuId = "fdd-author", label = "Author", count = List.length model.knobs.authors }
        (List.map
            (\username ->
                button
                    [ type_ "button", class "fdd-item", onClick (ToggleAuthor username) ]
                    [ span [ class (checkClass (List.member username model.knobs.authors)) ] []
                    , span [ class "fdd-item-label" ] [ text username ]
                    , span [ class "fdd-item-count" ]
                        [ text (String.fromInt (Dict.get username model.facetAuthors |> Maybe.withDefault 0)) ]
                    ]
            )
            model.authors
        )


groupLabel : Maybe String -> Maybe String -> String
groupLabel maybeGroup maybeSub =
    case ( maybeGroup, maybeSub ) of
        ( Nothing, _ ) ->
            "Group"

        ( Just group, Nothing ) ->
            "Group · " ++ group

        ( Just group, Just sub ) ->
            "Group · " ++ group ++ " › " ++ sub


viewGroupFdd : Model -> Html Msg
viewGroupFdd model =
    let
        scopes =
            Logic.workspaceScopes (tagSlugs model)

        radioItem msg on label =
            button
                [ type_ "button", class "fdd-item", onClick msg ]
                [ span [ class (radioClass on) ] []
                , span [ class "fdd-item-label" ] [ text label ]
                ]
    in
    fdd model
        { menuId = "fdd-group"
        , label = groupLabel model.knobs.groupBy model.knobs.subGroupBy
        , count = 0
        }
        (List.concat
            [ [ div [ class "fdd-section" ] [ text "Group by" ]
              , radioItem (SetGroup Nothing) (model.knobs.groupBy == Nothing) "None"
              ]
            , List.map
                (\scope -> radioItem (SetGroup (Just scope)) (model.knobs.groupBy == Just scope) scope)
                scopes
            , case model.knobs.groupBy of
                Nothing ->
                    []

                Just group ->
                    List.concat
                        [ [ div [ class "fdd-section" ] [ text "Then by" ]
                          , radioItem (SetSubgroup Nothing) (model.knobs.subGroupBy == Nothing) "None"
                          ]
                        , scopes
                            |> List.filter ((/=) group)
                            |> List.map
                                (\scope ->
                                    radioItem (SetSubgroup (Just scope))
                                        (model.knobs.subGroupBy == Just scope)
                                        scope
                                )
                        ]
            ]
        )


viewEditedFdd : Model -> Html Msg
viewEditedFdd model =
    let
        current =
            model.knobs.edited

        label =
            case current of
                Just token ->
                    "Edited · " ++ token

                Nothing ->
                    "Edited"
    in
    fdd model
        { menuId = "fdd-edited", label = label, count = 0 }
        (List.map
            (\( optLabel, token ) ->
                button
                    [ type_ "button", class "fdd-item", onClick (SetEdited token) ]
                    [ span [ class (radioClass (current == token)) ] []
                    , span [ class "fdd-item-label" ] [ text optLabel ]
                    ]
            )
            [ ( "Any time", Nothing )
            , ( "Last 24 hours", Just "24h" )
            , ( "Last 7 days", Just "7d" )
            , ( "Last 30 days", Just "30d" )
            , ( "Last 90 days", Just "90d" )
            ]
        )


viewSortFdd : Model -> Html Msg
viewSortFdd model =
    fdd model
        { menuId = "fdd-sort", label = "Sort · " ++ Logic.sortLabel model.knobs.sort, count = 0 }
        (List.map
            (\( optLabel, sort ) ->
                button
                    [ type_ "button", class "fdd-item", onClick (SetSort sort) ]
                    [ span [ class (radioClass (model.knobs.sort == sort)) ] []
                    , span [ class "fdd-item-label" ] [ text optLabel ]
                    ]
            )
            [ ( "Recent", Recent ), ( "Kudos", Kudos ), ( "Views", Views ) ]
        )


viewClearAll : Model -> List (Html Msg)
viewClearAll model =
    let
        knobs =
            model.knobs

        anyFilter =
            knobs.tags /= [] || knobs.authors /= [] || knobs.groupBy /= Nothing || knobs.edited /= Nothing || knobs.search /= ""
    in
    if model.currentView == Nothing && anyFilter then
        [ button
            [ type_ "button", class "fbar-clear", onClick ClearFilters ]
            [ text "Clear all" ]
        ]

    else
        []


{-| The LV's `fdd` component: trigger button + hidden menu. Open state
lives in `model.openMenu`; multi-select menus stay open across
re-fetches because the choice of when to close is per-Msg.
-}
fdd : Model -> { menuId : String, label : String, count : Int } -> List (Html Msg) -> Html Msg
fdd model config items =
    div [ class "fdd", id config.menuId ]
        [ button
            [ type_ "button"
            , class
                ("fdd-btn "
                    ++ (if config.count > 0 then
                            "fdd-btn-active"

                        else
                            ""
                       )
                )
            , onClick (ToggleMenu config.menuId)
            ]
            (List.concat
                [ [ text config.label ]
                , if config.count > 0 then
                    [ span [ class "fdd-badge" ] [ text (String.fromInt config.count) ] ]

                  else
                    []
                , [ chevronSvg "fdd-chev" "2" ]
                ]
            )
        , div
            [ class "fdd-menu"
            , id (config.menuId ++ "-menu")
            , hidden (model.openMenu /= Just config.menuId)
            ]
            items
        ]


checkClass : Bool -> String
checkClass on =
    "fdd-check "
        ++ (if on then
                "on"

            else
                ""
           )


radioClass : Bool -> String
radioClass on =
    "fdd-check fdd-radio "
        ++ (if on then
                "on"

            else
                ""
           )



-- ===== List =====


viewList : Model -> List (Html Msg)
viewList model =
    if model.docsLoaded && model.docs == [] then
        [ div [ class "empty" ] [ text "No docs match the current filter." ] ]

    else
        (case model.knobs.groupBy of
            Just group ->
                [ div [ class "grouped-list" ]
                    (Logic.groupedSections (tagSlugs model) group model.knobs.subGroupBy .tags model.docs
                        |> List.indexedMap (viewGroupBlock model)
                    )
                ]

            Nothing ->
                [ cardList model model.docs ]
        )
            ++ viewLoadMore model


viewLoadMore : Model -> List (Html Msg)
viewLoadMore model =
    if model.hasMore then
        [ div [ class "load-more-wrap" ]
            [ button [ type_ "button", class "load-more-btn", onClick LoadMore ] [ text "Load more" ] ]
        ]

    else
        []


viewGroupBlock : Model -> Int -> Logic.Section DocSummary -> Html Msg
viewGroupBlock model si sec =
    let
        key =
            "grp-" ++ String.fromInt si

        isCollapsed =
            Set.member key model.collapsed
    in
    div
        [ class
            ("group-block"
                ++ (if isCollapsed then
                        " group-collapsed"

                    else
                        ""
                   )
            )
        , id key
        ]
        [ button
            [ type_ "button", class "group-head", onClick (ToggleSection key) ]
            [ chevronSvg "group-chev" "2.4"
            , span (class "group-dot" :: dotStyle model sec.key) []
            , span [ class "group-head-name" ] [ text sec.label ]
            , span [ class "group-head-count" ] [ text (String.fromInt sec.count) ]
            ]
        , div [ id (key ++ "-body"), class "group-body", hidden isCollapsed ]
            (case sec.subs of
                Just subs ->
                    List.map (viewSubgroup model) subs

                Nothing ->
                    [ cardList model sec.docs ]
            )
        ]


viewSubgroup : Model -> Logic.SubSection DocSummary -> Html Msg
viewSubgroup model sub =
    div [ class "subgroup" ]
        [ div [ class "subgroup-head" ]
            [ span (class "group-dot group-dot-sm" :: dotStyle model sub.key) []
            , span [ class "subgroup-head-name" ] [ text sub.label ]
            , span [ class "group-head-count" ] [ text (String.fromInt sub.count) ]
            ]
        , cardList model sub.docs
        ]


dotStyle : Model -> Maybe String -> List (Html.Attribute Msg)
dotStyle model key =
    case key |> Maybe.andThen (\k -> Dict.get k (tagColors model)) of
        Just c ->
            [ attribute "style" ("background: " ++ c) ]

        Nothing ->
            []


cardList : Model -> List DocSummary -> Html Msg
cardList model docs =
    let
        cardConfig =
            { wsSlug = model.slug, now = model.now, tagColors = tagColors model }
    in
    ul [ class "card-list" ]
        (List.map (\doc -> li [] [ Ui.DocCard.view cardConfig doc ]) docs)



-- ===== Icons =====


chevronSvg : String -> String -> Html msg
chevronSvg svgClass strokeWidth =
    Svg.svg
        [ SA.class svgClass
        , SA.viewBox "0 0 24 24"
        , SA.fill "none"
        , SA.stroke "currentColor"
        , SA.strokeWidth strokeWidth
        , SA.strokeLinecap "round"
        , SA.strokeLinejoin "round"
        ]
        [ Svg.polyline [ SA.points "6 9 12 15 18 9" ] [] ]


searchSvg : Html msg
searchSvg =
    Svg.svg
        [ SA.viewBox "0 0 16 16"
        , SA.fill "none"
        , SA.stroke "currentColor"
        , SA.strokeWidth "1.5"
        , SA.strokeLinecap "round"
        , SA.strokeLinejoin "round"
        ]
        [ Svg.circle [ SA.cx "7", SA.cy "7", SA.r "4.5" ] []
        , Svg.path [ SA.d "M10.5 10.5L14 14" ] []
        ]


vmenuLockSvg : Html msg
vmenuLockSvg =
    Svg.svg
        [ SA.class "doc-lock"
        , SA.viewBox "0 0 24 24"
        , SA.fill "none"
        , SA.stroke "currentColor"
        , SA.strokeWidth "2"
        , SA.strokeLinecap "round"
        , SA.strokeLinejoin "round"
        ]
        [ Svg.title [] [ Svg.text "In your personal bucket: only you can see this view" ]
        , Svg.rect [ SA.x "3", SA.y "11", SA.width "18", SA.height "11", SA.rx "2", SA.ry "2" ] []
        , Svg.path [ SA.d "M7 11V7a5 5 0 0 1 10 0v4" ] []
        ]


vmenuPinSvg : Html msg
vmenuPinSvg =
    Svg.svg
        [ SA.class "vmenu-pin"
        , SA.viewBox "0 0 24 24"
        , SA.fill "none"
        , SA.stroke "currentColor"
        , SA.strokeWidth "2"
        , SA.strokeLinecap "round"
        , SA.strokeLinejoin "round"
        ]
        [ Svg.title [] [ Svg.text "Pinned to sidebar" ]
        , Svg.path [ SA.d "M12 17v5" ] []
        , Svg.path [ SA.d "M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V6h1a2 2 0 0 0 0-4H8a2 2 0 0 0 0 4h1z" ] []
        ]
