module Api.Docs exposing
    ( Bucket
    , DocSummary
    , DocsPage
    , Facets
    , Member
    , TagInfo
    , UserRef
    , ViewConfig
    , ViewDef
    , docsPageDecoder
    , facetsDecoder
    , fetchDocs
    , fetchFacets
    , fetchMembers
    , fetchTags
    , fetchViews
    , membersDecoder
    , tagsDecoder
    , viewsDecoder
    )

{-| Types + decoders + requests for the Docs page (fe-docs-list).

Reads:

  - GET /papi/workspaces/:slug/tags — workspace tag registry (order =
    registry order: COALESCE(sort\_key, slug)), with colors.
  - GET /papi/workspaces/:slug/members — workspace members (author chips).
  - GET /papi/workspaces/:slug/views — saved views usable by the viewer.
  - GET /papi/workspaces/:slug/fe/docs-list — enriched doc list
    (card fields + per-doc view/kudos counts + has\_more).
  - GET /papi/workspaces/:slug/fe/docs-facets — corpus-wide facet counts.

-}

import Api
import Dict exposing (Dict)
import Iso8601
import Json.Decode as Decode exposing (Decoder)
import Session exposing (Session)
import Time
import Url.Builder


type alias UserRef =
    { id : String
    , username : String
    }


type alias DocSummary =
    { id : String
    , baseDocId : String
    , slug : String
    , title : String
    , summary : Maybe String
    , tags : List String
    , visibility : String
    , actorUser : Maybe UserRef
    , updatedAt : Maybe Time.Posix
    , viewCount : Int
    , kudosCount : Int
    }


type alias DocsPage =
    { docs : List DocSummary
    , hasMore : Bool
    }


type alias TagInfo =
    { slug : String
    , color : Maybe String
    }


type alias Member =
    { username : String
    }


type alias Bucket =
    { name : String
    , kind : String
    }


{-| A saved view's display knobs, exactly as stored in `config`.
Raw strings — validation against the workspace's tag scopes happens in
Page.Docs.Logic (mirroring the LV's parse\_group / parse\_sort).
-}
type alias ViewConfig =
    { tags : List String
    , groupBy : Maybe String
    , subGroupBy : Maybe String
    , sort : Maybe String
    , edited : Maybe String
    }


type alias ViewDef =
    { name : String
    , description : Maybe String
    , config : ViewConfig
    , pinned : Bool
    , bucket : Maybe Bucket
    }


type alias Facets =
    { tags : Dict String Int
    , authors : Dict String Int
    }



-- ===== Decoders =====


userRefDecoder : Decoder UserRef
userRefDecoder =
    Decode.map2 UserRef
        (Decode.field "id" Decode.string)
        (Decode.field "username" Decode.string)


docSummaryDecoder : Decoder DocSummary
docSummaryDecoder =
    let
        andMap =
            Decode.map2 (|>)
    in
    Decode.succeed DocSummary
        |> andMap (Decode.field "id" Decode.string)
        |> andMap (Decode.field "base_doc_id" Decode.string)
        |> andMap (Decode.field "slug" Decode.string)
        |> andMap (Decode.field "title" Decode.string)
        |> andMap (Decode.field "summary" (Decode.nullable Decode.string))
        |> andMap (Decode.field "tags" (Decode.list Decode.string))
        |> andMap (Decode.field "visibility" Decode.string)
        |> andMap (Decode.field "actor_user" (Decode.nullable userRefDecoder))
        |> andMap (Decode.field "updated_at" (Decode.nullable posixDecoder))
        |> andMap (Decode.field "view_count" Decode.int)
        |> andMap (Decode.field "kudos_count" Decode.int)


posixDecoder : Decoder Time.Posix
posixDecoder =
    Decode.string
        |> Decode.andThen
            (\s ->
                case Iso8601.toTime s of
                    Ok t ->
                        Decode.succeed t

                    Err _ ->
                        Decode.fail ("bad timestamp: " ++ s)
            )


docsPageDecoder : Decoder DocsPage
docsPageDecoder =
    Decode.map2 DocsPage
        (Decode.field "docs" (Decode.list docSummaryDecoder))
        (Decode.field "has_more" Decode.bool)


tagsDecoder : Decoder (List TagInfo)
tagsDecoder =
    Decode.field "tags"
        (Decode.list
            (Decode.map2 TagInfo
                (Decode.field "slug" Decode.string)
                (Decode.field "color" (Decode.nullable Decode.string))
            )
        )


membersDecoder : Decoder (List Member)
membersDecoder =
    Decode.field "members"
        (Decode.list (Decode.map Member (Decode.field "username" Decode.string)))


optionalField : String -> Decoder a -> a -> Decoder a
optionalField name decoder fallback =
    Decode.oneOf
        [ Decode.field name (Decode.nullable decoder)
            |> Decode.map (Maybe.withDefault fallback)
        , Decode.succeed fallback
        ]


viewConfigDecoder : Decoder ViewConfig
viewConfigDecoder =
    Decode.map5 ViewConfig
        (optionalField "tags" (Decode.list Decode.string) [])
        (optionalField "group_by" (Decode.map Just Decode.string) Nothing)
        (optionalField "sub_group_by" (Decode.map Just Decode.string) Nothing)
        (optionalField "sort" (Decode.map Just Decode.string) Nothing)
        (optionalField "edited" (Decode.map Just Decode.string) Nothing)


viewDefDecoder : Decoder ViewDef
viewDefDecoder =
    Decode.map5 ViewDef
        (Decode.field "name" Decode.string)
        (Decode.field "description" (Decode.nullable Decode.string))
        (optionalField "config" viewConfigDecoder (ViewConfig [] Nothing Nothing Nothing Nothing))
        (optionalField "pinned" Decode.bool False)
        (Decode.field "bucket"
            (Decode.nullable
                (Decode.map2 Bucket
                    (Decode.field "name" Decode.string)
                    (Decode.field "kind" Decode.string)
                )
            )
        )


viewsDecoder : Decoder (List ViewDef)
viewsDecoder =
    Decode.field "views" (Decode.list viewDefDecoder)


countsDecoder : Decoder (Dict String Int)
countsDecoder =
    Decode.dict Decode.int


facetsDecoder : Decoder Facets
facetsDecoder =
    Decode.map2 Facets
        (Decode.field "tags" countsDecoder)
        (Decode.field "authors" countsDecoder)



-- ===== Requests =====


base : String -> String -> String
base slug rest =
    "/papi/workspaces/" ++ slug ++ rest


fetchTags : Session -> String -> (Result Api.Error (List TagInfo) -> msg) -> Cmd msg
fetchTags session slug toMsg =
    Api.get session (base slug "/tags") tagsDecoder toMsg


fetchMembers : Session -> String -> (Result Api.Error (List Member) -> msg) -> Cmd msg
fetchMembers session slug toMsg =
    Api.get session (base slug "/members") membersDecoder toMsg


fetchViews : Session -> String -> (Result Api.Error (List ViewDef) -> msg) -> Cmd msg
fetchViews session slug toMsg =
    Api.get session (base slug "/views") viewsDecoder toMsg


type alias Filter r =
    { r
        | tags : List String
        , authors : List String
        , edited : Maybe String
        , search : String
    }


filterParams : Filter r -> List Url.Builder.QueryParameter
filterParams f =
    List.concat
        [ if f.search == "" then
            []

          else
            [ Url.Builder.string "q" f.search ]
        , case f.tags of
            [] ->
                []

            tags ->
                [ Url.Builder.string "tag" (String.join "," tags) ]
        , case f.authors of
            [] ->
                []

            authors ->
                [ Url.Builder.string "author" (String.join "," authors) ]
        , case f.edited of
            Nothing ->
                []

            Just within ->
                [ Url.Builder.string "edited" within ]
        ]


fetchDocs :
    Session
    -> String
    -> Filter r
    -> { sort : String, offset : Int }
    -> (Result Api.Error DocsPage -> msg)
    -> Cmd msg
fetchDocs session slug filter { sort, offset } toMsg =
    let
        params =
            filterParams filter
                ++ [ Url.Builder.string "sort" sort ]
                ++ (if offset > 0 then
                        [ Url.Builder.int "offset" offset ]

                    else
                        []
                   )
    in
    Api.get session
        (base slug "/fe/docs-list" ++ Url.Builder.toQuery params)
        docsPageDecoder
        toMsg


fetchFacets : Session -> String -> Filter r -> (Result Api.Error Facets -> msg) -> Cmd msg
fetchFacets session slug filter toMsg =
    Api.get session
        (base slug "/fe/docs-facets" ++ Url.Builder.toQuery (filterParams filter))
        facetsDecoder
        toMsg
