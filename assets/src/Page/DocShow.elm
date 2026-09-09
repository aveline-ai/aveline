module Page.DocShow exposing (Model, Msg, init, update, view)

{-| The doc reading view, ported from
`lib/aveline_web/live/doc_show_live.ex` (+ `BlockRenderer` /
`ChartRenderer`): title/meta/tags, all block types, version time-travel,
comment threads, kudos, visibility & shares, async chart runs.

Renders only the main content region (`.doc-layout`) — sidebar/topbar
chrome is the shell's job.

-}

import Api
import Api.Doc as ApiDoc exposing (Doc, KudosState, Member, Milestone, Share, ShareInfo, Version)
import Browser.Dom
import Dict exposing (Dict)
import Doc.Blocks as Blocks exposing (Block(..), ChartBlock, ChartResult(..), Span, SpanLink(..))
import Doc.Chart as Chart
import Doc.Comments as Comments exposing (Comment, CommentView(..), Thread)
import Html exposing (Html, a, article, br, button, code, details, div, form, h1, h2, h3, header, li, ol, option, p, section, select, span, strong, summary, table, tbody, td, text, textarea, th, thead, tr, ul)
import Html.Attributes exposing (attribute, class, classList, hidden, href, id, name, placeholder, rows, title, type_, value)
import Html.Events as Events
import Json.Decode as Decode
import Json.Encode as Encode
import Route
import Session exposing (Session)
import Set exposing (Set)
import Task
import Time exposing (Posix)
import Ui.Icons as Icons
import Ui.Time



-- ===== MODEL =====


type alias Model =
    { session : Session
    , slug : String
    , docSlug : String
    , versionParam : Maybe Int
    , now : Maybe Posix
    , currentDoc : Remote Doc
    , item : Maybe Doc
    , historical : Bool
    , versions : List Version
    , comments : List Comment
    , commentView : CommentView
    , tagColors : Dict String String
    , milestones : List Milestone
    , kudos : Maybe KudosState
    , shareInfo : Maybe ShareInfo
    , members : List Member
    , expandedThreads : Set String
    , commentingOn : Maybe String -- "__doc__" or a block id
    , editingCommentId : Maybe String
    , replyingTo : Maybe String
    , drafts : Dict String String
    , chartRuns : Dict String ChartRun
    , chartTabs : Dict String String -- block id -> "viz" | "table" | "sql"
    , openMenu : Maybe String
    , shareUsername : String
    , shareRole : String
    , flash : Maybe String
    }


type Remote a
    = Loading
    | Ready a
    | Failed String


type ChartRun
    = Running
    | RunOk Blocks.RunResult
    | RunErr String


type Msg
    = NoOp
    | GotNow Posix
    | GotDoc (Result Api.Error Doc)
    | GotVersionDoc (Result Api.Error Doc)
    | GotHistory (Result Api.Error (List Version))
    | GotComments (Result Api.Error (List Comment))
    | GotTagColors (Result Api.Error (Dict String String))
    | GotMilestones (Result Api.Error (List Milestone))
    | GotKudos (Result Api.Error KudosState)
    | GotShares (Result Api.Error ShareInfo)
    | GotMembers (Result Api.Error (List Member))
    | ChartRan String (Result Api.Error Blocks.RunResult)
    | RerunChart String String -- key, block id
    | SetChartTab String String
    | ToggleMenu String
    | SetCommentView CommentView
    | ToggleKudos
    | KudosToggled (Result Api.Error KudosState)
    | StartBlockComment String
    | CancelBlockComment
    | StartReply String
    | CancelReply
    | StartEditComment String String -- id, current body
    | CancelEditComment
    | SetDraft String String
    | SubmitComment { draftKey : String, blockId : Maybe String, parentId : Maybe String, andResolve : Bool }
    | CommentPosted { draftKey : String, resolveParent : Maybe String } (Result Api.Error String)
    | SubmitEditComment String
    | DeleteComment String
    | UndeleteComment String
    | UnresolveComment String
    | CommentMutated (Result Api.Error ())
    | ToggleThread String
    | SetVisibility String
    | VisibilityChanged (Result Api.Error String)
    | SetShareUsername String
    | SetShareRole String
    | SubmitShare
    | UnshareUser String
    | ShareChanged (Result Api.Error ())
    | DismissFlash


init : Session -> String -> String -> Maybe String -> ( Model, Cmd Msg )
init session slug docSlug version =
    let
        model =
            { session = session
            , slug = slug
            , docSlug = docSlug
            , versionParam = Maybe.andThen String.toInt version
            , now = Nothing
            , currentDoc = Loading
            , item = Nothing
            , historical = False
            , versions = []
            , comments = []
            , commentView = Open
            , tagColors = Dict.empty
            , milestones = []
            , kudos = Nothing
            , shareInfo = Nothing
            , members = []
            , expandedThreads = Set.empty
            , commentingOn = Nothing
            , editingCommentId = Nothing
            , replyingTo = Nothing
            , drafts = Dict.empty
            , chartRuns = Dict.empty
            , chartTabs = Dict.empty
            , openMenu = Nothing
            , shareUsername = ""
            , shareRole = "viewer"
            , flash = Nothing
            }
    in
    ( model
    , Cmd.batch
        [ Task.perform GotNow Time.now
        , ApiDoc.getDoc session slug docSlug GotDoc
        , ApiDoc.getHistory session slug docSlug GotHistory
        , ApiDoc.getTagColors session slug GotTagColors
        , ApiDoc.getMilestones session slug GotMilestones
        , ApiDoc.getKudos session slug docSlug GotKudos
        , ApiDoc.getShares session slug docSlug GotShares
        , ApiDoc.getMembers session slug GotMembers
        ]
    )



-- ===== UPDATE =====


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NoOp ->
            ( model, Cmd.none )

        GotNow now ->
            ( { model | now = Just now }, Cmd.none )

        GotDoc (Ok doc) ->
            case model.versionParam of
                Just n ->
                    if n == doc.versionNumber then
                        showItem { model | currentDoc = Ready doc } doc False

                    else
                        ( { model | currentDoc = Ready doc }
                        , ApiDoc.getVersion model.session model.slug model.docSlug n GotVersionDoc
                        )

                Nothing ->
                    showItem { model | currentDoc = Ready doc } doc False

        GotDoc (Err err) ->
            ( { model | currentDoc = Failed (Api.errorMessage err) }, Cmd.none )

        GotVersionDoc (Ok doc) ->
            showItem model doc True

        GotVersionDoc (Err _) ->
            -- Unknown version falls back to the current view, exactly
            -- like the LV's resolve_version :error branch.
            case model.currentDoc of
                Ready doc ->
                    showItem model doc False

                _ ->
                    ( model, Cmd.none )

        GotHistory (Ok versions) ->
            ( { model | versions = versions }, Cmd.none )

        GotHistory (Err _) ->
            ( model, Cmd.none )

        GotComments (Ok comments) ->
            ( { model | comments = comments }, Cmd.none )

        GotComments (Err _) ->
            ( model, Cmd.none )

        GotTagColors (Ok colors) ->
            ( { model | tagColors = colors }, Cmd.none )

        GotTagColors (Err _) ->
            ( model, Cmd.none )

        GotMilestones (Ok milestones) ->
            ( { model | milestones = milestones }, Cmd.none )

        GotMilestones (Err _) ->
            ( model, Cmd.none )

        GotKudos (Ok kudos) ->
            ( { model | kudos = Just kudos }, Cmd.none )

        GotKudos (Err _) ->
            ( model, Cmd.none )

        GotShares (Ok info) ->
            ( { model | shareInfo = Just info }, Cmd.none )

        GotShares (Err _) ->
            ( model, Cmd.none )

        GotMembers (Ok members) ->
            ( { model | members = members }, Cmd.none )

        GotMembers (Err _) ->
            ( model, Cmd.none )

        ChartRan key result ->
            let
                run =
                    case result of
                        Ok rows ->
                            RunOk rows

                        Err err ->
                            RunErr (Api.errorMessage err)
            in
            ( { model | chartRuns = Dict.insert key run model.chartRuns }, Cmd.none )

        RerunChart key blockId ->
            ( { model | chartRuns = Dict.insert key Running model.chartRuns }
            , ApiDoc.rerunBlock model.session
                model.slug
                model.docSlug
                blockId
                (if model.historical then
                    Maybe.map .versionNumber model.item

                 else
                    Nothing
                )
                (ChartRan key)
            )

        SetChartTab blockId tab ->
            ( { model | chartTabs = Dict.insert blockId tab model.chartTabs }, Cmd.none )

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

        SetCommentView view_ ->
            let
                fetch =
                    case ( view_, model.item ) of
                        ( Hide, _ ) ->
                            Cmd.none

                        ( _, Just item ) ->
                            ApiDoc.getComments model.session
                                model.slug
                                model.docSlug
                                item.versionNumber
                                (view_ == All)
                                GotComments

                        _ ->
                            Cmd.none
            in
            ( { model | commentView = view_, openMenu = Nothing }, fetch )

        ToggleKudos ->
            ( model, ApiDoc.toggleKudos model.session model.slug model.docSlug KudosToggled )

        KudosToggled (Ok kudos) ->
            ( { model | kudos = Just kudos }, Cmd.none )

        KudosToggled (Err err) ->
            ( flash (Api.errorMessage err) model, Cmd.none )

        StartBlockComment blockId ->
            ( { model | commentingOn = Just blockId }
            , focus (composerId blockId)
            )

        CancelBlockComment ->
            ( { model | commentingOn = Nothing }, Cmd.none )

        StartReply threadId ->
            ( { model | replyingTo = Just threadId }
            , focus ("reply-input-" ++ threadId)
            )

        CancelReply ->
            ( { model | replyingTo = Nothing }, Cmd.none )

        StartEditComment commentId body ->
            ( { model
                | editingCommentId = Just commentId
                , drafts = Dict.insert ("edit-" ++ commentId) body model.drafts
              }
            , focus ("edit-input-" ++ commentId)
            )

        CancelEditComment ->
            ( { model | editingCommentId = Nothing }, Cmd.none )

        SetDraft key text_ ->
            ( { model | drafts = Dict.insert key text_ model.drafts }, Cmd.none )

        SubmitComment params ->
            let
                body =
                    String.trim (draft params.draftKey model)
            in
            if guardWrite model then
                ( model, Cmd.none )

            else if model.session.user == Nothing then
                ( flash "Sign in to post." model, Cmd.none )

            else if body == "" then
                ( model, Cmd.none )

            else
                ( model
                , ApiDoc.createComment model.session
                    model.slug
                    model.docSlug
                    { body = body, blockId = params.blockId, parentId = params.parentId }
                    (CommentPosted
                        { draftKey = params.draftKey
                        , resolveParent =
                            if params.andResolve then
                                params.parentId

                            else
                                Nothing
                        }
                    )
                )

        CommentPosted meta (Ok _) ->
            let
                cleared =
                    { model
                        | drafts = Dict.remove meta.draftKey model.drafts
                        , commentingOn = Nothing
                        , replyingTo = Nothing
                    }
            in
            case meta.resolveParent of
                Just parentId ->
                    ( cleared
                    , ApiDoc.resolveComment model.session model.slug parentId CommentMutated
                    )

                Nothing ->
                    ( cleared, refetchComments cleared )

        CommentPosted _ (Err _) ->
            ( flash "Could not post." model, Cmd.none )

        SubmitEditComment commentId ->
            let
                body =
                    String.trim (draft ("edit-" ++ commentId) model)
            in
            if guardWrite model || body == "" then
                ( model, Cmd.none )

            else
                ( { model | editingCommentId = Nothing }
                , ApiDoc.updateComment model.session model.slug commentId body CommentMutated
                )

        DeleteComment commentId ->
            if guardWrite model then
                ( model, Cmd.none )

            else
                ( model, ApiDoc.deleteComment model.session model.slug commentId CommentMutated )

        UndeleteComment commentId ->
            if guardWrite model then
                ( model, Cmd.none )

            else
                ( model, ApiDoc.undeleteComment model.session model.slug commentId CommentMutated )

        UnresolveComment commentId ->
            if guardWrite model then
                ( model, Cmd.none )

            else
                ( model, ApiDoc.unresolveComment model.session model.slug commentId CommentMutated )

        CommentMutated (Ok ()) ->
            ( model, refetchComments model )

        CommentMutated (Err err) ->
            ( flash (Api.errorMessage err) model, refetchComments model )

        ToggleThread threadId ->
            ( { model
                | expandedThreads =
                    if Set.member threadId model.expandedThreads then
                        Set.remove threadId model.expandedThreads

                    else
                        Set.insert threadId model.expandedThreads
              }
            , Cmd.none
            )

        SetVisibility visibility ->
            ( model
            , ApiDoc.setVisibility model.session model.slug model.docSlug visibility VisibilityChanged
            )

        VisibilityChanged (Ok _) ->
            ( model, ApiDoc.getShares model.session model.slug model.docSlug GotShares )

        VisibilityChanged (Err err) ->
            ( flash (Api.errorMessage err) model, Cmd.none )

        SetShareUsername username ->
            ( { model | shareUsername = username }, Cmd.none )

        SetShareRole role ->
            ( { model | shareRole = role }, Cmd.none )

        SubmitShare ->
            let
                username =
                    if model.shareUsername == "" then
                        model
                            |> shareCandidates
                            |> List.head
                            |> Maybe.map .username
                            |> Maybe.withDefault ""

                    else
                        model.shareUsername
            in
            if username == "" then
                ( model, Cmd.none )

            else
                ( model
                , ApiDoc.shareDoc model.session model.slug model.docSlug username model.shareRole ShareChanged
                )

        UnshareUser username ->
            ( model, ApiDoc.unshareDoc model.session model.slug model.docSlug username ShareChanged )

        ShareChanged (Ok ()) ->
            ( model, ApiDoc.getShares model.session model.slug model.docSlug GotShares )

        ShareChanged (Err err) ->
            ( flash (Api.errorMessage err) model, Cmd.none )

        DismissFlash ->
            ( { model | flash = Nothing }, Cmd.none )


{-| Set `item` (what we render) and kick off comments + chart runs.
Historical views never auto-run charts — their pending placeholders
become idle Run controls instead.
-}
showItem : Model -> Doc -> Bool -> ( Model, Cmd Msg )
showItem model doc historical =
    let
        newModel =
            { model | item = Just doc, historical = historical }

        chartCmds =
            if historical then
                []

            else
                autoRunCharts newModel doc

        withRuns =
            { newModel
                | chartRuns =
                    List.foldl (\( key, _ ) acc -> Dict.insert key Running acc)
                        newModel.chartRuns
                        (if historical then
                            []

                         else
                            runnableCharts newModel doc
                        )
            }
    in
    ( withRuns
    , Cmd.batch
        (ApiDoc.getComments model.session
            model.slug
            model.docSlug
            doc.versionNumber
            (model.commentView == All)
            GotComments
            :: chartCmds
        )
    )


{-| One run per distinct chart key not already run or running — charts
sharing a query share one run and never diverge.
-}
runnableCharts : Model -> Doc -> List ( String, String )
runnableCharts model doc =
    doc.blocks
        |> List.filterMap
            (\block ->
                case block of
                    Chart chart ->
                        case ( chart.result, Chart.chartKey chart, chart.id ) of
                            ( Pending, Just key, Just blockId ) ->
                                if Dict.member key model.chartRuns then
                                    Nothing

                                else
                                    Just ( key, blockId )

                            _ ->
                                Nothing

                    _ ->
                        Nothing
            )
        |> dedupeByFirst


autoRunCharts : Model -> Doc -> List (Cmd Msg)
autoRunCharts model doc =
    runnableCharts model doc
        |> List.map
            (\( key, blockId ) ->
                ApiDoc.runBlock model.session model.slug model.docSlug blockId (ChartRan key)
            )


dedupeByFirst : List ( String, a ) -> List ( String, a )
dedupeByFirst list =
    List.foldl
        (\( k, v ) ( seen, acc ) ->
            if Set.member k seen then
                ( seen, acc )

            else
                ( Set.insert k seen, acc ++ [ ( k, v ) ] )
        )
        ( Set.empty, [] )
        list
        |> Tuple.second


refetchComments : Model -> Cmd Msg
refetchComments model =
    case ( model.item, model.commentView ) of
        ( Just item, view_ ) ->
            if view_ == Hide then
                Cmd.none

            else
                ApiDoc.getComments model.session
                    model.slug
                    model.docSlug
                    item.versionNumber
                    (view_ == All)
                    GotComments

        _ ->
            Cmd.none


{-| Time-travel views are READ-ONLY: every comment mutation
short-circuits when historical (same belt-and-suspenders as the LV).
-}
guardWrite : Model -> Bool
guardWrite model =
    model.historical


flash : String -> Model -> Model
flash message model =
    { model | flash = Just message }


draft : String -> Model -> String
draft key model =
    Dict.get key model.drafts |> Maybe.withDefault ""


composerId : String -> String
composerId blockId =
    if blockId == "__doc__" then
        "doc-comment-input"

    else
        "block-comment-input-" ++ blockId


focus : String -> Cmd Msg
focus elementId =
    Task.attempt (always NoOp) (Browser.Dom.focus elementId)


shareCandidates : Model -> List Member
shareCandidates model =
    let
        ownerId =
            case model.currentDoc of
                Ready doc ->
                    doc.owner |> Maybe.map .id |> Maybe.withDefault ""

                _ ->
                    ""
    in
    model.members
        |> List.filter (\m -> m.id /= ownerId)
        |> List.sortBy .username



-- ===== VIEW =====


view : Model -> Html Msg
view model =
    div [ class "doc-layout" ]
        (case ( model.currentDoc, model.item ) of
            ( Failed message, _ ) ->
                [ flashView (Just message) ]

            ( Ready currentDoc, Just item ) ->
                [ flashView model.flash
                , viewArticle model currentDoc item
                ]

            _ ->
                [ flashView model.flash ]
        )


flashView : Maybe String -> Html Msg
flashView maybeMessage =
    case maybeMessage of
        Nothing ->
            text ""

        Just message ->
            div [ class "flash-fixed flash-error", attribute "role" "alert", Events.onClick DismissFlash ]
                [ text message ]


viewArticle : Model -> Doc -> Doc -> Html Msg
viewArticle model currentDoc item =
    let
        blockIds =
            List.filterMap Blocks.blockId item.blocks

        visible =
            if model.commentView == Hide then
                []

            else
                Comments.filterForView model.commentView model.comments

        grouped =
            Comments.groupThreads blockIds visible
    in
    div
        [ classList
            [ ( "doc-article", True )
            , ( "doc-readonly", model.historical )
            , ( "doc-comments-hidden", model.commentView == Hide )
            ]
        ]
        (stateBanner model currentDoc item
            :: viewHeader model currentDoc item
            :: viewTopDiscussion model currentDoc grouped
            :: [ article [ class "prose" ]
                    [ div [ class "blocks" ]
                        (List.concatMap
                            (\block ->
                                [ viewBlock model block
                                , case Blocks.blockId block of
                                    Just bid ->
                                        viewBlockCommentZone model
                                            currentDoc
                                            bid
                                            (Dict.get bid grouped.byBlock |> Maybe.withDefault [])

                                    Nothing ->
                                        text ""
                                ]
                            )
                            item.blocks
                        )
                    ]
               ]
        )



-- ===== Banner =====


stateBanner : Model -> Doc -> Doc -> Html Msg
stateBanner model currentDoc item =
    if model.historical then
        div [ class "doc-banner doc-banner-historical", attribute "role" "status" ]
            [ div [ class "doc-banner-row" ]
                (List.concat
                    [ [ span [ class "doc-banner-tag" ] [ text ("Viewing v" ++ String.fromInt item.versionNumber) ] ]
                    , case item.actorUser of
                        Just user ->
                            [ span [ class "doc-banner-actor" ]
                                [ Icons.actor item.actorType "actor-icon" Nothing
                                , text user.username
                                ]
                            ]

                        Nothing ->
                            []
                    , [ span [ class "card-meta-dot" ] [ text "·" ]
                      , span [ title (absTime model item.updatedAt) ] [ text (relTime model item.updatedAt) ]
                      , span [ class "doc-banner-spacer" ] []
                      , a
                            [ href (Route.href (Route.DocShow model.slug currentDoc.slug))
                            , class "doc-banner-action"
                            ]
                            [ text ("Back to v" ++ String.fromInt currentDoc.versionNumber ++ " (latest) →") ]
                      ]
                    ]
                )
            , case item.intent of
                Just intent ->
                    if intent == "" then
                        text ""

                    else
                        div [ class "doc-banner-detail" ] [ text intent ]

                Nothing ->
                    text ""
            ]

    else
        text ""



-- ===== Header =====


viewHeader : Model -> Doc -> Doc -> Html Msg
viewHeader model currentDoc item =
    let
        user =
            model.session.user

        isOwner =
            case ( user, currentDoc.owner ) of
                ( Just u, Just owner ) ->
                    u.id == owner.id

                _ ->
                    False

        visibility =
            model.shareInfo |> Maybe.map .visibility |> Maybe.withDefault "workspace"
    in
    header [ class "article-header" ]
        [ div [ class "article-title-row blk-anchored" ]
            [ span [ class "block-gutter", attribute "contenteditable" "false" ]
                (Html.node "aveline-copy-link"
                    [ class "block-anchor"
                    , id "anchor-doc"
                    , attribute "data-block-id" ""
                    , title "Copy link to this doc"
                    , attribute "aria-label" "Copy link to this doc"
                    , attribute "role" "link"
                    , attribute "tabindex" "0"
                    ]
                    [ Icons.linkChain ]
                    :: (if user /= Nothing && not model.historical then
                            [ button
                                [ type_ "button"
                                , class "block-comment-btn"
                                , Events.onClick (StartBlockComment "__doc__")
                                , title "Add a doc-level comment"
                                , attribute "aria-label" "Add a doc-level comment"
                                ]
                                [ Icons.commentBubble ]
                            ]

                        else
                            []
                       )
                )
            , h1 [ class "article-title" ]
                ((if visibility == "private" then
                    [ Icons.lock "doc-lock" "Private: only you and people it's shared with can see this doc" ]

                  else
                    []
                 )
                    ++ [ text item.title ]
                )
            , case user of
                Just u ->
                    if not isOwner then
                        kudosButton model

                    else
                        text ""

                Nothing ->
                    text ""
            ]
        , case item.summary of
            Just summary ->
                if summary == "" then
                    text ""

                else
                    p [ class "article-summary" ] [ text summary ]

            Nothing ->
                text ""
        , viewMeta model currentDoc item isOwner visibility
        ]


kudosButton : Model -> Html Msg
kudosButton model =
    let
        given =
            model.kudos |> Maybe.map .givenByMe |> Maybe.withDefault False
    in
    button
        [ type_ "button"
        , Events.onClick ToggleKudos
        , class
            ("article-kudos-btn "
                ++ (if given then
                        "is-given"

                    else
                        ""
                   )
            )
        , title
            (if given then
                "You gave kudos. Click to take it back."

             else
                "Give kudos"
            )
        , attribute "aria-pressed"
            (if given then
                "true"

             else
                "false"
            )
        , attribute "aria-label"
            (if given then
                "Remove kudos"

             else
                "Give kudos"
            )
        ]
        [ Icons.kudosTrophy ]


viewMeta : Model -> Doc -> Doc -> Bool -> String -> Html Msg
viewMeta model currentDoc item isOwner visibility =
    div [ class "article-meta" ]
        (List.concat
            [ [ span [ class "article-meta-item" ]
                    [ span [ class "chip chip-author" ]
                        [ Icons.actor item.actorType "actor-icon" (Just item.actorType)
                        , span [ class "chip-text" ]
                            [ text (item.actorUser |> Maybe.map .username |> Maybe.withDefault "?") ]
                        ]
                    ]
              , metaDot
              ]
            , [ versionSwitcher model currentDoc item ]
            , [ metaDot, commentViewSwitcher model ]
            , [ metaDot, visibilityControl model currentDoc isOwner visibility ]
            , if List.isEmpty item.tags then
                []

              else
                [ metaDot
                , span [ class "chip-row", attribute "style" "gap:6px" ]
                    (List.map (tagChip model True) item.tags)
                ]
            ]
        )


metaDot : Html msg
metaDot =
    span [ class "card-meta-dot" ] [ text "·" ]


tagChip : Model -> Bool -> String -> Html Msg
tagChip model linked tag =
    let
        styleAttr =
            case Dict.get tag model.tagColors of
                Just c ->
                    [ attribute "style"
                        ("--tag: " ++ c ++ "; --tag-dim: " ++ c ++ "14; --tag-border: " ++ c ++ "40")
                    ]

                Nothing ->
                    []
    in
    if linked then
        a
            ([ href (Route.href (Route.Docs model.slug) ++ "?tag=" ++ tag)
             , class "chip chip-tag"
             ]
                ++ styleAttr
            )
            [ text tag ]

    else
        span (class "chip chip-tag" :: styleAttr) [ text tag ]


versionSwitcher : Model -> Doc -> Doc -> Html Msg
versionSwitcher model currentDoc item =
    let
        label =
            "v" ++ String.fromInt item.versionNumber ++ " · " ++ relTime model item.updatedAt
    in
    if List.length model.versions > 1 then
        details
            [ class "version-switcher"
            , menuOpen model "versions"
            ]
            [ summary
                [ class "version-switcher-trigger"
                , title (absTime model item.updatedAt)
                , menuToggle "versions"
                ]
                [ span [ class "article-meta-val" ] [ text label ]
                , Icons.chevronDown "version-switcher-chev"
                ]
            , div [ class "version-switcher-menu" ]
                (div [ class "switcher-label" ]
                    [ text ("History · " ++ String.fromInt (List.length model.versions) ++ " versions") ]
                    :: List.map (versionItem model currentDoc item) model.versions
                )
            ]

    else
        span [ class "article-meta-item", title (absTime model item.updatedAt) ]
            [ span [ class "article-meta-val" ] [ text label ] ]


versionItem : Model -> Doc -> Doc -> Version -> Html Msg
versionItem model currentDoc item v =
    let
        target =
            if v.versionNumber == currentDoc.versionNumber then
                Route.DocShow model.slug currentDoc.slug

            else
                Route.DocShowVersion model.slug currentDoc.slug (String.fromInt v.versionNumber)

        current =
            v.versionNumber == item.versionNumber
    in
    a
        [ href (Route.href target)
        , class
            ("version-switcher-item "
                ++ (if current then
                        "current"

                    else
                        ""
                   )
            )
        ]
        (List.concat
            [ [ span [ class "version-switcher-num" ] [ text ("v" ++ String.fromInt v.versionNumber) ] ]
            , case v.actorUser of
                Just user ->
                    [ span [ class "version-switcher-actor" ]
                        [ Icons.actor v.actorType "actor-icon" Nothing
                        , text user.username
                        ]
                    ]

                Nothing ->
                    []
            , [ span [ class "version-switcher-time", title (absTime model v.insertedAt) ]
                    [ text (relTime model v.insertedAt) ]
              ]
            , if current then
                [ span [ class "check" ] [ text "✓" ] ]

              else
                []
            , case v.intent of
                Just intent ->
                    if intent == "" then
                        []

                    else
                        [ span [ class "version-switcher-intent" ] [ text intent ] ]

                Nothing ->
                    []
            , case dispositionSummary v.dispositions of
                Just summaryText ->
                    [ span [ class "version-switcher-dispo" ] [ text summaryText ] ]

                Nothing ->
                    []
            ]
        )


{-| "Resolved 2 · Re-anchored 1 · Left open 3" — nil when empty.
-}
dispositionSummary : List ApiDoc.Disposition -> Maybe String
dispositionSummary dispositions =
    let
        countOf action =
            List.length (List.filter (\d -> d.action == action) dispositions)

        part action label =
            case countOf action of
                0 ->
                    Nothing

                n ->
                    Just (label ++ " " ++ String.fromInt n)

        parts =
            List.filterMap identity
                [ part "resolve" "Resolved"
                , part "reanchor" "Re-anchored"
                , part "leave" "Left open"
                ]
    in
    if List.isEmpty parts then
        Nothing

    else
        Just (String.join " · " parts)


commentViewSwitcher : Model -> Html Msg
commentViewSwitcher model =
    details
        [ class "version-switcher"
        , id "comment-view-switcher"
        , menuOpen model "comments"
        ]
        [ summary [ class "version-switcher-trigger", menuToggle "comments" ]
            [ span [ class "article-meta-val" ]
                [ text ("Comments · " ++ Comments.commentViewWord model.commentView) ]
            , Icons.chevronDown "version-switcher-chev"
            ]
        , div [ class "version-switcher-menu comment-view-menu" ]
            (div [ class "switcher-label" ] [ text "Comments" ]
                :: List.map (commentViewItem model)
                    [ ( Open, "open", "unresolved threads" )
                    , ( All, "all", "includes resolved + deleted" )
                    , ( Hide, "hidden", "clean canvas, no comments" )
                    ]
            )
        ]


commentViewItem : Model -> ( CommentView, String, String ) -> Html Msg
commentViewItem model ( view_, word, desc ) =
    let
        current =
            model.commentView == view_
    in
    button
        [ type_ "button"
        , Events.onClick (SetCommentView view_)
        , class
            ("version-switcher-item comment-view-item "
                ++ (if current then
                        "current"

                    else
                        ""
                   )
            )
        ]
        (span [ class "comment-view-word" ] [ text word ]
            :: span [ class "comment-view-desc" ] [ text desc ]
            :: (if current then
                    [ span [ class "check" ] [ text "✓" ] ]

                else
                    []
               )
        )


visibilityControl : Model -> Doc -> Bool -> String -> Html Msg
visibilityControl model currentDoc isOwner visibility =
    let
        shares =
            model.shareInfo |> Maybe.map .shares |> Maybe.withDefault []
    in
    if isOwner && not model.historical then
        details
            [ class "version-switcher"
            , id "visibility-switcher"
            , menuOpen model "visibility"
            ]
            [ summary
                [ class "version-switcher-trigger"
                , title "Who can see this doc"
                , menuToggle "visibility"
                ]
                [ span [ class "article-meta-val" ]
                    [ text
                        (if visibility == "private" then
                            "Private"
                                ++ (if List.isEmpty shares then
                                        ""

                                    else
                                        " · " ++ String.fromInt (List.length shares)
                                   )

                         else
                            "Team"
                        )
                    ]
                , Icons.chevronDown "version-switcher-chev"
                ]
            , div [ class "version-switcher-menu visibility-menu" ]
                (List.concat
                    [ [ div [ class "switcher-label" ] [ text "Who can see this doc" ]
                      , visibilityItem visibility "workspace" "team" "everyone in this workspace"
                      , visibilityItem visibility "private" "private" "you, plus people you share it with"
                      ]
                    , if visibility == "private" then
                        List.concat
                            [ [ div [ class "switcher-label" ] [ text "Shared with" ] ]
                            , if List.isEmpty shares then
                                [ p [ class "share-empty" ] [ text "No one yet. Only you can see this doc." ] ]

                              else
                                List.map shareRow shares
                            , shareForm model
                            ]

                      else
                        []
                    ]
                )
            ]

    else
        span [ class "article-meta-item", title "Who can see this doc" ]
            [ span [ class "article-meta-val" ]
                [ text
                    (if visibility == "private" then
                        "Private"

                     else
                        "Team"
                    )
                ]
            ]


visibilityItem : String -> String -> String -> String -> Html Msg
visibilityItem current value_ word desc =
    button
        [ type_ "button"
        , Events.onClick (SetVisibility value_)
        , class
            ("version-switcher-item comment-view-item "
                ++ (if current == value_ then
                        "current"

                    else
                        ""
                   )
            )
        ]
        (span [ class "comment-view-word" ] [ text word ]
            :: span [ class "comment-view-desc" ] [ text desc ]
            :: (if current == value_ then
                    [ span [ class "check" ] [ text "✓" ] ]

                else
                    []
               )
        )


shareRow : Share -> Html Msg
shareRow share =
    let
        username =
            Maybe.withDefault "" share.username
    in
    div [ class "share-row" ]
        [ span [ class "share-name" ] [ text username ]
        , span [ class "share-role" ] [ text share.role ]
        , button
            [ type_ "button"
            , class "share-remove"
            , Events.onClick (UnshareUser username)
            , title "Revoke access"
            , attribute "aria-label" ("Revoke access for " ++ username)
            ]
            [ text "×" ]
        ]


shareForm : Model -> List (Html Msg)
shareForm model =
    let
        candidates =
            shareCandidates model
    in
    if List.isEmpty candidates then
        []

    else
        [ form [ Events.onSubmit SubmitShare, class "share-form" ]
            [ select
                [ name "username"
                , class "share-select"
                , Events.onInput SetShareUsername
                ]
                (List.map
                    (\u -> option [ value u.username ] [ text u.username ])
                    candidates
                )
            , select
                [ name "role"
                , class "share-select share-select-role"
                , Events.onInput SetShareRole
                ]
                [ option [ value "viewer" ] [ text "viewer" ]
                , option [ value "editor" ] [ text "editor" ]
                ]
            , button [ type_ "submit", class "share-add-btn" ] [ text "Share" ]
            ]
        ]



-- ===== Top discussion (doc-level + orphans) =====


viewTopDiscussion : Model -> Doc -> Comments.Grouped -> Html Msg
viewTopDiscussion model currentDoc grouped =
    let
        composerOpen =
            model.commentingOn == Just "__doc__"
    in
    if List.isEmpty grouped.docLevel && List.isEmpty grouped.orphans && not composerOpen then
        text ""

    else
        section [ class "doc-discussion doc-discussion-top", id "discussion" ]
            (List.concat
                [ if List.isEmpty grouped.docLevel then
                    []

                  else
                    [ ol [ class "comment-card-list" ]
                        (List.map (threadListItem model currentDoc False) grouped.docLevel)
                    ]
                , if List.isEmpty grouped.orphans then
                    []

                  else
                    [ div [ class "doc-discussion-subheader" ]
                        [ span [] [ text "Orphaned" ]
                        , span [ class "count" ] [ text (String.fromInt (List.length grouped.orphans)) ]
                        , span [ class "doc-discussion-subnote" ]
                            [ text "Block these were on no longer exists in this version." ]
                        ]
                    , ol [ class "comment-card-list" ]
                        (List.map (threadListItem model currentDoc True) grouped.orphans)
                    ]
                , if model.session.user /= Nothing && composerOpen then
                    [ composer model
                        { formId = "doc-comment-form"
                        , inputId = "doc-comment-input"
                        , draftKey = "doc"
                        , placeholderText = "Add a doc-level comment…"
                        , blockId = Nothing
                        , parentId = Nothing
                        , extraClass = "comment-composer-inline"
                        , withResolve = False
                        , submitLabel = "Comment"
                        , cancelMsg = CancelBlockComment
                        }
                    ]

                  else
                    []
                ]
            )


threadListItem : Model -> Doc -> Bool -> Thread -> Html Msg
threadListItem model currentDoc orphan thread =
    li
        [ id ("thread-" ++ thread.parent.id)
        , class
            (String.join " "
                (List.filterMap identity
                    [ Just "comment-card-wrap"
                    , if orphan then
                        Just "comment-card-wrap-orphan"

                      else
                        Nothing
                    , if thread.parent.resolvedAt /= Nothing then
                        Just "comment-card-wrap-resolved"

                      else
                        Nothing
                    ]
                )
            )
        ]
        (List.concat
            [ if orphan then
                case thread.parent.contextSnippet of
                    Just caption ->
                        [ div [ class "orphan-snippet" ]
                            [ span [ class "orphan-snippet-label" ] [ text "originally on" ]
                            , span [ class "orphan-snippet-text" ] [ text ("\"" ++ caption ++ "\"") ]
                            ]
                        ]

                    Nothing ->
                        []

              else
                []
            , [ commentCard model currentDoc thread ]
            ]
        )



-- ===== Per-block comment zone =====


viewBlockCommentZone : Model -> Doc -> String -> List Thread -> Html Msg
viewBlockCommentZone model currentDoc blockId threads =
    let
        composerOpen =
            model.commentingOn == Just blockId
    in
    if List.isEmpty threads && not composerOpen then
        text ""

    else
        div [ class "block-comments" ]
            (List.concat
                [ if List.isEmpty threads then
                    []

                  else
                    [ ol [ class "comment-card-list" ]
                        (List.map (threadListItem model currentDoc False) threads)
                    ]
                , if model.session.user /= Nothing && composerOpen then
                    [ composer model
                        { formId = "block-comment-form-" ++ blockId
                        , inputId = "block-comment-input-" ++ blockId
                        , draftKey = "block-" ++ blockId
                        , placeholderText = "Ask a question about this block…"
                        , blockId = Just blockId
                        , parentId = Nothing
                        , extraClass = "comment-composer-inline"
                        , withResolve = False
                        , submitLabel = "Comment"
                        , cancelMsg = CancelBlockComment
                        }
                    ]

                  else
                    []
                ]
            )



-- ===== Comment cards =====


commentCard : Model -> Doc -> Thread -> Html Msg
commentCard model currentDoc thread =
    let
        partitioned =
            Comments.partitionReplies thread

        expanded =
            Set.member thread.parent.id model.expandedThreads

        replyRow reply =
            li [ id ("m-" ++ reply.id) ]
                [ commentRow model currentDoc reply True ]
    in
    article [ class "comment-card" ]
        (List.concat
            [ [ commentRow model currentDoc thread.parent False ]
            , if List.isEmpty thread.replies then
                []

              else
                [ ol [ class "comment-card-replies" ]
                    (if not (List.isEmpty partitioned.hidden) && not expanded then
                        li [ class "comment-card-collapsed" ]
                            [ button
                                [ type_ "button"
                                , Events.onClick (ToggleThread thread.parent.id)
                                , class "comment-card-expand-btn"
                                , title "Show all replies in this thread"
                                ]
                                [ text
                                    ("Show "
                                        ++ String.fromInt (List.length partitioned.hidden)
                                        ++ " hidden "
                                        ++ (if List.length partitioned.hidden == 1 then
                                                "reply"

                                            else
                                                "replies"
                                           )
                                    )
                                ]
                            ]
                            :: List.map replyRow partitioned.tail

                     else
                        List.map replyRow thread.replies
                    )
                ]
            , viewReplyZone model thread
            ]
        )


viewReplyZone : Model -> Thread -> List (Html Msg)
viewReplyZone model thread =
    -- Historical versions are read-only: the CSS hides the composer, so
    -- don't dangle a Reply button that could never open one.
    if not model.historical && model.session.user /= Nothing && thread.parent.resolvedAt == Nothing then
        if model.replyingTo == Just thread.parent.id then
            [ composer model
                { formId = "reply-form-" ++ thread.parent.id
                , inputId = "reply-input-" ++ thread.parent.id
                , draftKey = "reply-" ++ thread.parent.id
                , placeholderText =
                    "Reply to "
                        ++ (thread.parent.actorUser
                                |> Maybe.map .username
                                |> Maybe.withDefault "this thread"
                           )
                        ++ "…"
                , blockId = Nothing
                , parentId = Just thread.parent.id
                , extraClass = "comment-composer-reply"
                , withResolve = True
                , submitLabel = "Reply"
                , cancelMsg = CancelReply
                }
            ]

        else
            [ div [ class "comment-card-reply-prompt" ]
                [ button
                    [ type_ "button"
                    , Events.onClick (StartReply thread.parent.id)
                    , class "comment-card-reply-btn"
                    ]
                    [ text "Reply" ]
                ]
            ]

    else
        []


commentRow : Model -> Doc -> Comment -> Bool -> Html Msg
commentRow model currentDoc message isReply =
    let
        user =
            model.session.user

        mine =
            case ( user, message.actorUser ) of
                ( Just u, Just actorUser ) ->
                    u.id == actorUser.id

                _ ->
                    False

        editing =
            model.editingCommentId == Just message.id
    in
    div [ class "thread-body" ]
        [ div [ class "thread-meta" ]
            (List.concat
                [ [ Icons.actor message.actorType "actor-icon" (Just message.actorType)
                  , span [ class "thread-author" ]
                        [ text (message.actorUser |> Maybe.map .username |> Maybe.withDefault "?") ]
                  , metaDot
                  , span [ title (absTime model message.createdAt) ] [ text (relTime model message.createdAt) ]
                  ]
                , case message.editedAt of
                    Just editedAt ->
                        [ metaDot
                        , span [ class "thread-edited", title (absTime model (Just editedAt)) ] [ text "edited" ]
                        ]

                    Nothing ->
                        []
                , if not isReply && message.resolvedAt /= Nothing then
                    List.concat
                        [ [ metaDot
                          , span [ class "thread-resolved", title (absTime model message.resolvedAt) ]
                                [ text (resolvedLabel message) ]
                          ]
                        , case message.resolvedInVersion of
                            Just n ->
                                [ a
                                    [ href (resolverPath model currentDoc n)
                                    , class "thread-version-badge"
                                    , title "Open the version that resolved this"
                                    ]
                                    [ text ("see v" ++ String.fromInt n) ]
                                ]

                            Nothing ->
                                []
                        ]

                  else
                    []
                , case message.deletedAt of
                    Just deletedAt ->
                        [ metaDot
                        , span [ class "thread-deleted-tag", title (absTime model (Just deletedAt)) ]
                            [ Icons.trash
                            , span []
                                [ text
                                    ("deleted"
                                        ++ (message.deletedBy
                                                |> Maybe.map (\u -> " by " ++ u.username)
                                                |> Maybe.withDefault ""
                                           )
                                    )
                                ]
                            ]
                        ]

                    Nothing ->
                        []
                , [ span [ class "thread-actions" ]
                        (List.concat
                            [ if user /= Nothing && not isReply && message.resolvedAt /= Nothing then
                                [ threadActionBtn "unresolve" (UnresolveComment message.id) ]

                              else
                                []
                            , if mine then
                                threadActionBtn "edit" (StartEditComment message.id message.body)
                                    :: (case message.deletedAt of
                                            Just _ ->
                                                [ threadActionBtn "undelete" (UndeleteComment message.id) ]

                                            Nothing ->
                                                [ threadActionBtn "delete" (DeleteComment message.id) ]
                                       )

                              else
                                []
                            ]
                        )
                  ]
                ]
            )
        , if editing then
            editForm model message

          else
            div
                [ class
                    ("thread-content "
                        ++ (if message.resolvedAt /= Nothing then
                                "thread-content-resolved"

                            else
                                ""
                           )
                    )
                ]
                (plainTextLines message.body)
        ]


resolvedLabel : Comment -> String
resolvedLabel message =
    "resolved"
        ++ (case ( message.resolvedInVersion, message.resolvedBy ) of
                ( Just n, _ ) ->
                    " in v" ++ String.fromInt n

                ( Nothing, Just user ) ->
                    " by " ++ user.username

                _ ->
                    ""
           )


resolverPath : Model -> Doc -> Int -> String
resolverPath model currentDoc n =
    if n == currentDoc.versionNumber then
        Route.href (Route.DocShow model.slug currentDoc.slug)

    else
        Route.href (Route.DocShowVersion model.slug currentDoc.slug (String.fromInt n))


threadActionBtn : String -> Msg -> Html Msg
threadActionBtn label msg =
    button [ type_ "button", Events.onClick msg, class "thread-action-btn" ] [ text label ]


editForm : Model -> Comment -> Html Msg
editForm model message =
    let
        draftKey =
            "edit-" ++ message.id
    in
    form
        [ Events.onSubmit (SubmitEditComment message.id)
        , id ("edit-form-" ++ message.id)
        , class "comment-edit-form"
        ]
        [ textarea
            [ id ("edit-input-" ++ message.id)
            , name "body"
            , class "comment-composer-input"
            , rows 2
            , value (draft draftKey model)
            , Events.onInput (SetDraft draftKey)
            , onCmdEnter (SubmitEditComment message.id)
            ]
            []
        , div [ class "comment-composer-footer" ]
            [ span [ class "comment-composer-hint" ] [ text "Cmd+Enter to save" ]
            , button [ type_ "button", Events.onClick CancelEditComment, class "comment-composer-cancel" ] [ text "Cancel" ]
            , button [ type_ "submit", class "comment-composer-submit" ] [ text "Save" ]
            ]
        ]


type alias ComposerConfig =
    { formId : String
    , inputId : String
    , draftKey : String
    , placeholderText : String
    , blockId : Maybe String
    , parentId : Maybe String
    , extraClass : String
    , withResolve : Bool
    , submitLabel : String
    , cancelMsg : Msg
    }


composer : Model -> ComposerConfig -> Html Msg
composer model config =
    let
        submitMsg andResolve =
            SubmitComment
                { draftKey = config.draftKey
                , blockId = config.blockId
                , parentId = config.parentId
                , andResolve = andResolve
                }
    in
    form
        [ Events.onSubmit (submitMsg False)
        , id config.formId
        , class ("comment-composer " ++ config.extraClass)
        ]
        [ textarea
            [ id config.inputId
            , name "body"
            , class "comment-composer-input"
            , placeholder config.placeholderText
            , rows 2
            , value (draft config.draftKey model)
            , Events.onInput (SetDraft config.draftKey)
            , onCmdEnter (submitMsg False)
            ]
            []
        , div [ class "comment-composer-footer" ]
            (List.concat
                [ [ span [ class "comment-composer-hint" ]
                        [ text
                            (if config.withResolve then
                                "Cmd+Enter to reply"

                             else
                                "Cmd+Enter to post"
                            )
                        ]
                  , button [ type_ "button", Events.onClick config.cancelMsg, class "comment-composer-cancel" ] [ text "Cancel" ]
                  ]
                , if config.withResolve then
                    [ button
                        [ type_ "button"
                        , Events.onClick (submitMsg True)
                        , class "comment-composer-submit comment-composer-submit-resolve"
                        , title "Post reply and mark this thread resolved"
                        ]
                        [ text "Reply & resolve" ]
                    ]

                  else
                    []
                , [ button [ type_ "submit", class "comment-composer-submit" ] [ text config.submitLabel ] ]
                ]
            )
        ]


{-| Plain-text bodies (no markdown): newlines become <br>.
-}
plainTextLines : String -> List (Html msg)
plainTextLines body =
    body
        |> String.split "\n"
        |> List.map text
        |> List.intersperse (br [] [])


onCmdEnter : Msg -> Html.Attribute Msg
onCmdEnter msg =
    Events.preventDefaultOn "keydown"
        (Decode.map3
            (\key meta ctrl ->
                if key == "Enter" && (meta || ctrl) then
                    ( msg, True )

                else
                    ( NoOp, False )
            )
            (Decode.field "key" Decode.string)
            (Decode.field "metaKey" Decode.bool)
            (Decode.field "ctrlKey" Decode.bool)
        )



-- ===== Blocks =====


viewBlock : Model -> Block -> Html Msg
viewBlock model block =
    case block of
        Heading b ->
            let
                ( tag, cls ) =
                    case b.level of
                        1 ->
                            ( h1, "blk-h1 blk-anchored" )

                        2 ->
                            ( h2, "blk-h2 blk-anchored" )

                        _ ->
                            ( h3, "blk-h3 blk-anchored" )
            in
            tag (blockIdAttr b.id ++ [ class cls ])
                [ blockAnchor model b.id, text b.text ]

        Paragraph b ->
            p (blockIdAttr b.id ++ [ class "blk-p blk-anchored" ])
                (blockAnchor model b.id :: viewSpans model b.content)

        Code b ->
            div [ class "blk-code-wrap blk-anchored" ]
                [ blockAnchor model b.id
                , Html.node "aveline-code"
                    (blockIdAttr b.id
                        ++ [ attribute "lang" (Maybe.withDefault "" b.language)
                           , attribute "code" b.content
                           ]
                    )
                    []
                ]

        Listed b ->
            let
                tag =
                    if b.ordered then
                        ol

                    else
                        ul
            in
            tag (blockIdAttr b.id ++ [ class "blk-list blk-anchored" ])
                (blockAnchor model b.id
                    :: List.map
                        (\item ->
                            li (blockIdAttr item.id) (viewSpans model item.content)
                        )
                        b.items
                )

        Table b ->
            div [ class "blk-table-wrap blk-anchored" ]
                [ blockAnchor model b.id
                , table (blockIdAttr b.id ++ [ class "blk-table" ])
                    [ thead []
                        [ tr [] (List.map (\h -> th [] [ text h ]) b.headers) ]
                    , tbody []
                        (List.map
                            (\row ->
                                tr [] (List.map (\cell -> td [] (viewSpans model cell)) row)
                            )
                            b.rows
                        )
                    ]
                ]

        DocLink b ->
            viewDocLink model b

        Chart b ->
            viewChart model b

        Unknown typeName ->
            div [ class "blk-unknown" ] [ text ("Unknown block type: " ++ typeName) ]


blockIdAttr : Maybe String -> List (Html.Attribute msg)
blockIdAttr maybeId =
    case maybeId of
        Just theId ->
            [ id theId ]

        Nothing ->
            []


{-| The per-block gutter: copy-link anchor + comment button. The anchor
is an `<aveline-copy-link>` custom element (clipboard needs JS).
-}
blockAnchor : Model -> Maybe String -> Html Msg
blockAnchor model maybeId =
    case maybeId of
        Nothing ->
            text ""

        Just blockId ->
            span [ class "block-gutter", attribute "contenteditable" "false" ]
                [ Html.node "aveline-copy-link"
                    [ class "block-anchor"
                    , id ("anchor-" ++ blockId)
                    , attribute "data-block-id" blockId
                    , title "Copy link to this block"
                    , attribute "aria-label" "Copy link to this block"
                    , attribute "role" "link"
                    , attribute "tabindex" "0"
                    ]
                    [ Icons.linkChain ]
                , button
                    [ type_ "button"
                    , class "block-comment-btn"
                    , Events.onClick (StartBlockComment blockId)
                    , title "Comment on this block"
                    , attribute "aria-label" "Comment on this block"
                    ]
                    [ Icons.commentBubble ]
                ]



-- ===== Inline spans =====


viewSpans : Model -> List Span -> List (Html Msg)
viewSpans model spans =
    List.map (\s -> span [] [ viewSpan model s ]) spans


viewSpan : Model -> Span -> Html Msg
viewSpan model s =
    let
        inner =
            markedText s
    in
    case s.link of
        Just (DocMention mention) ->
            case mention.target of
                Just target ->
                    case ( target.deleted, target.slug ) of
                        ( False, Just slug ) ->
                            a
                                [ class "blk-doc-mention"
                                , href (Route.href (Route.DocShow model.slug slug))
                                , title (Maybe.withDefault "" target.title)
                                ]
                                [ Icons.mention, inner ]

                        _ ->
                            inner

                Nothing ->
                    inner

        Just (Href url) ->
            a [ class "blk-link", href url ] [ inner ]

        Nothing ->
            inner


{-| Wrap the text in its marks, innermost-first — same nesting as
`safe_text_with_marks/2`.
-}
markedText : Span -> Html msg
markedText s =
    List.foldl
        (\mark inner ->
            case mark of
                "bold" ->
                    strong [] [ inner ]

                "italic" ->
                    Html.em [] [ inner ]

                "code" ->
                    code [ class "blk-inline-code" ] [ inner ]

                "strike" ->
                    Html.s [] [ inner ]

                _ ->
                    inner
        )
        (text s.text)
        s.marks



-- ===== doc_link =====


viewDocLink : Model -> Blocks.DocLinkBlock -> Html Msg
viewDocLink model b =
    let
        live =
            case b.target of
                Just target ->
                    not target.deleted && not target.inaccessible && target.slug /= Nothing

                Nothing ->
                    False
    in
    div (blockIdAttr b.id ++ [ class "blk-doc-link blk-anchored" ])
        (List.concat
            [ [ blockAnchor model b.id ]
            , [ case ( live, b.target ) of
                    ( True, Just target ) ->
                        a
                            [ href (Route.href (Route.DocShow model.slug (Maybe.withDefault "" target.slug)))
                            , class "doc-link-card"
                            ]
                            (List.concat
                                [ [ div [ class "doc-link-card-title" ]
                                        [ text (Maybe.withDefault "" target.title) ]
                                  ]
                                , case target.summary of
                                    Just summary ->
                                        [ div [ class "doc-link-card-summary" ] [ text summary ] ]

                                    Nothing ->
                                        []
                                , if List.isEmpty target.tags then
                                    []

                                  else
                                    [ div
                                        [ class "doc-link-card-tags chip-row"
                                        , attribute "style" "gap:6px"
                                        ]
                                        (List.map (tagChip model False) target.tags)
                                    ]
                                ]
                            )

                    _ ->
                        div [ class "doc-link-card doc-link-card-dead" ]
                            [ div [ class "doc-link-card-title" ]
                                [ text
                                    (b.target
                                        |> Maybe.andThen .title
                                        |> Maybe.withDefault "Removed doc"
                                    )
                                ]
                            , div [ class "doc-link-card-summary" ]
                                [ text "This stop's doc was deleted. Restore it to bring the stop back." ]
                            ]
              ]
            , case b.note of
                Just note ->
                    [ p [ class "doc-link-note" ] (viewSpans model note) ]

                Nothing ->
                    []
            ]
        )



-- ===== chart =====


{-| The block's enriched result, overridden by any completed/running
client-side run for its key, with historical pending → idle.
-}
effectiveResult : Model -> ChartBlock -> ChartResult
effectiveResult model chart =
    let
        base =
            case Chart.chartKey chart |> Maybe.andThen (\key -> Dict.get key model.chartRuns) of
                Just Running ->
                    Pending

                Just (RunOk rows) ->
                    Rows rows

                Just (RunErr message) ->
                    Blocks.Failed message

                Nothing ->
                    chart.result
    in
    if model.historical && base == Pending && not (chartRunning model chart) then
        Idle

    else
        base


chartRunning : Model -> ChartBlock -> Bool
chartRunning model chart =
    (Chart.chartKey chart |> Maybe.andThen (\key -> Dict.get key model.chartRuns)) == Just Running


viewChart : Model -> ChartBlock -> Html Msg
viewChart model chart =
    let
        blockId =
            Maybe.withDefault "" chart.id

        result =
            effectiveResult model chart

        tablePrimary =
            Chart.tablePrimary chart

        activeTab =
            Dict.get blockId model.chartTabs |> Maybe.withDefault "viz"

        rerunMsg =
            case Chart.chartKey chart of
                Just key ->
                    RerunChart key blockId

                Nothing ->
                    NoOp

        tabButton tabId label =
            button
                [ type_ "button"
                , id (blockId ++ "-tab-" ++ tabId)
                , class
                    ("chart-tab"
                        ++ (if activeTab == tabId then
                                " chart-tab-active"

                            else
                                ""
                           )
                    )
                , Events.onClick (SetChartTab blockId tabId)
                ]
                [ text label ]
    in
    div (blockIdAttr chart.id ++ [ class "blk-chart blk-anchored" ])
        [ blockAnchor model chart.id
        , div [ class "chart-tabs" ]
            (List.concat
                [ [ tabButton "viz"
                        (if tablePrimary then
                            "table"

                         else
                            "chart"
                        )
                  ]
                , if tablePrimary then
                    []

                  else
                    [ tabButton "table" "table" ]
                , [ tabButton "sql" "sql" ]
                ]
            )
        , div [ id (blockId ++ "-pane-viz"), hidden (activeTab /= "viz") ]
            [ vizPane model chart blockId result tablePrimary rerunMsg ]
        , if tablePrimary then
            text ""

          else
            div [ id (blockId ++ "-pane-table"), hidden (activeTab /= "table") ]
                [ tablePane result ]
        , if activeTab == "sql" then
            div [ id (blockId ++ "-pane-sql") ]
                [ Html.node "aveline-sql"
                    [ id (blockId ++ "-sqlcode")
                    , attribute "dialect" (Chart.sqlDialect chart.source)
                    , attribute "code"
                        (chart.querySql
                            |> orElse chart.inlineQuery
                            |> Maybe.withDefault ""
                        )
                    ]
                    []
                ]

          else
            text ""
        , div [ class "chart-caption" ]
            (List.concat
                [ [ span [ class "chart-source" ] [ text (Chart.caption chart) ] ]
                , case result of
                    Rows rows ->
                        List.concat
                            [ if rows.truncated then
                                [ span [ class "chart-truncated" ]
                                    [ text "truncated to first 1000 rows" ]
                                ]

                              else
                                []
                            , if List.isEmpty rows.truncatedInputs then
                                []

                              else
                                [ span [ class "chart-truncated" ]
                                    [ text
                                        ("⚠ input truncated at 1000 rows: "
                                            ++ String.join ", " rows.truncatedInputs
                                            ++ " — stats over partial data"
                                        )
                                    ]
                                ]
                            ]

                    _ ->
                        []
                , if result == Pending || result == Idle then
                    []

                  else
                    [ button
                        [ type_ "button"
                        , class "chart-refresh"
                        , title "re-run this query (refreshes every chart sharing it)"
                        , Events.onClick rerunMsg
                        ]
                        [ text "↻ refresh" ]
                    ]
                ]
            )
        ]


vizPane : Model -> ChartBlock -> String -> ChartResult -> Bool -> Msg -> Html Msg
vizPane model chart blockId result tablePrimary rerunMsg =
    case result of
        Pending ->
            chartPlaceholder

        Idle ->
            div [ class "chart-placeholder" ]
                [ button
                    [ type_ "button"
                    , class "chart-run-btn"
                    , Events.onClick rerunMsg
                    ]
                    [ text "▶ Run query" ]
                , span [ class "chart-idle-note" ] [ text "historical version: charts don't auto-run" ]
                ]

        Blocks.Failed message ->
            chartError message (Just rerunMsg)

        Rows rows ->
            if tablePrimary then
                resultsTable rows

            else
                case Chart.spec rows chart.viz of
                    Ok spec ->
                        Html.node "aveline-chart"
                            [ id (blockId ++ "-echart")
                            , class "chart-plot"
                            , attribute "spec" (Encode.encode 0 (Chart.encodeSpec spec model.milestones))
                            ]
                            []

                    Err message ->
                        chartError message (Just rerunMsg)


tablePane : ChartResult -> Html Msg
tablePane result =
    case result of
        Pending ->
            chartPlaceholder

        Idle ->
            div [ class "chart-placeholder" ]
                [ span [ class "chart-idle-note" ]
                    [ text "run the query from the chart tab to see rows" ]
                ]

        Rows rows ->
            resultsTable rows

        Blocks.Failed message ->
            div [ class "chart-error" ] [ text message ]


chartPlaceholder : Html msg
chartPlaceholder =
    div [ class "chart-placeholder" ]
        [ span [ class "chart-spinner" ] [], text " running query…" ]


chartError : String -> Maybe Msg -> Html Msg
chartError message maybeRerun =
    div [ class "chart-error" ]
        (text message
            :: (case maybeRerun of
                    Just rerun ->
                        [ button
                            [ type_ "button"
                            , class "chart-run-btn"
                            , Events.onClick rerun
                            ]
                            [ text "try again" ]
                        ]

                    Nothing ->
                        []
               )
        )


resultsTable : Blocks.RunResult -> Html msg
resultsTable rows =
    div [ class "blk-table-wrap" ]
        [ table [ class "blk-table" ]
            [ thead []
                [ tr [] (List.map (\c -> th [] [ text c ]) rows.columns) ]
            , tbody []
                (List.map
                    (\row ->
                        tr [] (List.map (\cell -> td [] [ text (Blocks.cellText cell) ]) row)
                    )
                    rows.rows
                )
            ]
        ]



-- ===== Small helpers =====


menuOpen : Model -> String -> Html.Attribute msg
menuOpen model menuId =
    if model.openMenu == Just menuId then
        attribute "open" ""

    else
        class ""


menuToggle : String -> Html.Attribute Msg
menuToggle menuId =
    Events.preventDefaultOn "click" (Decode.succeed ( ToggleMenu menuId, True ))


relTime : Model -> Maybe Posix -> String
relTime model maybeTime =
    case ( model.now, maybeTime ) of
        ( Just now, Just t ) ->
            Ui.Time.relativeTime now t

        _ ->
            ""


absTime : Model -> Maybe Posix -> String
absTime model maybeTime =
    case maybeTime of
        Just t ->
            Ui.Time.absoluteTime t

        Nothing ->
            ""


orElse : Maybe a -> Maybe a -> Maybe a
orElse fallback primary =
    case primary of
        Just _ ->
            primary

        Nothing ->
            fallback
