module Api.Doc exposing
    ( Disposition
    , Doc
    , KudosState
    , Member
    , Milestone
    , Share
    , ShareInfo
    , Version
    , createComment
    , deleteComment
    , docDecoder
    , getComments
    , getDoc
    , getHistory
    , getKudos
    , getMembers
    , getMilestones
    , getShares
    , getTagColors
    , getVersion
    , rerunBlock
    , resolveComment
    , runBlock
    , setVisibility
    , shareDoc
    , toggleKudos
    , undeleteComment
    , unresolveComment
    , unshareDoc
    , updateComment
    , versionDecoder
    )

{-| Doc-show reads and writes over /papi. Shapes mirror
`AvelineWeb.Api.Views` (doc\_full, doc\_version, comment) plus the
fe-doc-show reader endpoints (`AvelineWeb.Api.DocShowController`).
-}

import Api
import Dict exposing (Dict)
import Doc.Blocks as Blocks exposing (Block)
import Doc.Comments as Comments exposing (Comment, UserRef)
import Iso8601
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Session exposing (Session)
import Time exposing (Posix)
import Url


type alias Doc =
    { id : String
    , baseDocId : String
    , slug : String
    , title : String
    , summary : Maybe String
    , tags : List String
    , versionNumber : Int
    , owner : Maybe UserRef
    , updatedAt : Maybe Posix
    , intent : Maybe String
    , actorType : String
    , actorUser : Maybe UserRef
    , blocks : List Block
    }


type alias Version =
    { id : String
    , versionNumber : Int
    , intent : Maybe String
    , actorType : String
    , actorUser : Maybe UserRef
    , insertedAt : Maybe Posix
    , updatedAt : Maybe Posix
    , dispositions : List Disposition
    }


type alias Disposition =
    { action : String }


type alias KudosState =
    { givenByMe : Bool
    , count : Int
    }


type alias ShareInfo =
    { visibility : String
    , shares : List Share
    }


type alias Share =
    { username : Maybe String
    , role : String
    }


type alias Member =
    { id : String
    , username : String
    }


type alias Milestone =
    { name : String
    , date : String
    , description : Maybe String
    }



-- ===== Decoders =====


docDecoder : Decoder Doc
docDecoder =
    Decode.succeed Doc
        |> andMap (Decode.field "id" Decode.string)
        |> andMap (Decode.field "base_doc_id" Decode.string)
        |> andMap (Decode.field "slug" Decode.string)
        |> andMap (withDefault "" (optionalField "title" Decode.string))
        |> andMap (optionalField "summary" Decode.string)
        |> andMap (withDefault [] (optionalField "tags" (Decode.list Decode.string)))
        |> andMap (Decode.field "version_number" Decode.int)
        |> andMap (optionalField "owner" userRefDecoder)
        |> andMap (optionalField "updated_at" Iso8601.decoder)
        |> andMap (optionalField "intent" Decode.string)
        |> andMap (withDefault "" (optionalAt [ "actor", "type" ] Decode.string))
        |> andMap (optionalAt [ "actor", "user" ] userRefDecoder)
        |> andMap (withDefault [] (optionalField "blocks" (Decode.list Blocks.blockDecoder)))


versionDecoder : Decoder Version
versionDecoder =
    Decode.succeed Version
        |> andMap (Decode.field "id" Decode.string)
        |> andMap (Decode.field "version_number" Decode.int)
        |> andMap (optionalField "intent" Decode.string)
        |> andMap (withDefault "" (optionalAt [ "actor", "type" ] Decode.string))
        |> andMap (optionalAt [ "actor", "user" ] userRefDecoder)
        |> andMap (optionalField "inserted_at" Iso8601.decoder)
        |> andMap (optionalField "updated_at" Iso8601.decoder)
        |> andMap (withDefault [] (optionalField "comment_dispositions" (Decode.list dispositionDecoder)))


dispositionDecoder : Decoder Disposition
dispositionDecoder =
    Decode.map Disposition
        (withDefault "" (optionalField "action" Decode.string))


userRefDecoder : Decoder UserRef
userRefDecoder =
    Decode.map2 UserRef
        (Decode.field "id" Decode.string)
        (Decode.field "username" Decode.string)



-- ===== Reads =====


{-| The current doc via the reader endpoint — same `doc_full` shape as
GET /docs/:slug but records a human read instead of an agent one.
-}
getDoc : Session -> String -> String -> (Result Api.Error Doc -> msg) -> Cmd msg
getDoc session slug docSlug toMsg =
    Api.get session (docPath slug docSlug "/reader") (Decode.field "doc" docDecoder) toMsg


getVersion : Session -> String -> String -> Int -> (Result Api.Error Doc -> msg) -> Cmd msg
getVersion session slug docSlug n toMsg =
    Api.get session
        (docPath slug docSlug ("/versions/" ++ String.fromInt n))
        (Decode.field "doc" docDecoder)
        toMsg


getHistory : Session -> String -> String -> (Result Api.Error (List Version) -> msg) -> Cmd msg
getHistory session slug docSlug toMsg =
    Api.get session
        (docPath slug docSlug "/history")
        (Decode.field "versions" (Decode.list versionDecoder))
        toMsg


getComments : Session -> String -> String -> Int -> Bool -> (Result Api.Error (List Comment) -> msg) -> Cmd msg
getComments session slug docSlug versionNumber includeDeleted toMsg =
    let
        query =
            if includeDeleted then
                "?include_deleted=true"

            else
                ""
    in
    Api.get session
        (docPath slug docSlug ("/versions/" ++ String.fromInt versionNumber ++ "/comments") ++ query)
        (Decode.field "comments" (Decode.list Comments.commentDecoder))
        toMsg


getKudos : Session -> String -> String -> (Result Api.Error KudosState -> msg) -> Cmd msg
getKudos session slug docSlug toMsg =
    Api.get session (docPath slug docSlug "/kudos") kudosDecoder toMsg


getShares : Session -> String -> String -> (Result Api.Error ShareInfo -> msg) -> Cmd msg
getShares session slug docSlug toMsg =
    Api.get session (docPath slug docSlug "/shares") shareInfoDecoder toMsg


getMembers : Session -> String -> (Result Api.Error (List Member) -> msg) -> Cmd msg
getMembers session slug toMsg =
    Api.get session
        (wsPath slug "/members")
        (Decode.field "members" (Decode.list memberDecoder))
        toMsg


{-| tag slug → hex color, for the `--tag` CSS variables on chips.
-}
getTagColors : Session -> String -> (Result Api.Error (Dict String String) -> msg) -> Cmd msg
getTagColors session slug toMsg =
    Api.get session
        (wsPath slug "/tags")
        (Decode.field "tags" (Decode.list tagColorDecoder)
            |> Decode.map (List.filterMap identity >> Dict.fromList)
        )
        toMsg


getMilestones : Session -> String -> (Result Api.Error (List Milestone) -> msg) -> Cmd msg
getMilestones session slug toMsg =
    Api.get session
        (wsPath slug "/milestones")
        (Decode.field "milestones" (Decode.list milestoneDecoder))
        toMsg


runBlock : Session -> String -> String -> String -> (Result Api.Error Blocks.RunResult -> msg) -> Cmd msg
runBlock session slug docSlug blockId toMsg =
    Api.post session
        (docPath slug docSlug ("/blocks/" ++ Url.percentEncode blockId ++ "/run"))
        (Encode.object [])
        Blocks.runResultDecoder
        toMsg


{-| Bust the cache, then run — the ↻ refresh / historical Run control.
`version` locates the block in a historical doc-version.
-}
rerunBlock : Session -> String -> String -> String -> Maybe Int -> (Result Api.Error Blocks.RunResult -> msg) -> Cmd msg
rerunBlock session slug docSlug blockId version toMsg =
    let
        query =
            case version of
                Just n ->
                    "?version=" ++ String.fromInt n

                Nothing ->
                    ""
    in
    Api.post session
        (docPath slug docSlug ("/blocks/" ++ Url.percentEncode blockId ++ "/rerun") ++ query)
        (Encode.object [])
        Blocks.runResultDecoder
        toMsg



-- ===== Writes =====


toggleKudos : Session -> String -> String -> (Result Api.Error KudosState -> msg) -> Cmd msg
toggleKudos session slug docSlug toMsg =
    Api.post session (docPath slug docSlug "/kudos") (Encode.object []) kudosDecoder toMsg


setVisibility : Session -> String -> String -> String -> (Result Api.Error String -> msg) -> Cmd msg
setVisibility session slug docSlug visibility toMsg =
    Api.put session
        (docPath slug docSlug "/visibility")
        (Encode.object [ ( "visibility", Encode.string visibility ) ])
        (Decode.field "visibility" Decode.string)
        toMsg


shareDoc : Session -> String -> String -> String -> String -> (Result Api.Error () -> msg) -> Cmd msg
shareDoc session slug docSlug username role toMsg =
    Api.post session
        (docPath slug docSlug "/shares")
        (Encode.object
            [ ( "username", Encode.string username )
            , ( "role", Encode.string role )
            ]
        )
        (Decode.succeed ())
        toMsg


unshareDoc : Session -> String -> String -> String -> (Result Api.Error () -> msg) -> Cmd msg
unshareDoc session slug docSlug username toMsg =
    Api.delete session
        (docPath slug docSlug ("/shares/" ++ Url.percentEncode username))
        (Decode.succeed ())
        toMsg


createComment :
    Session
    -> String
    -> String
    -> { body : String, blockId : Maybe String, parentId : Maybe String }
    -> (Result Api.Error String -> msg)
    -> Cmd msg
createComment session slug docSlug params toMsg =
    Api.post session
        (docPath slug docSlug "/comments")
        (Encode.object
            (( "body", Encode.string params.body )
                :: ( "actor", Encode.string "human" )
                :: List.filterMap identity
                    [ Maybe.map (\b -> ( "block_id", Encode.string b )) params.blockId
                    , Maybe.map (\p -> ( "parent_comment_id", Encode.string p )) params.parentId
                    ]
            )
        )
        (Decode.field "id" Decode.string)
        toMsg


updateComment : Session -> String -> String -> String -> (Result Api.Error () -> msg) -> Cmd msg
updateComment session slug commentId body toMsg =
    Api.patch session
        (commentPath slug commentId "")
        (Encode.object [ ( "body", Encode.string body ) ])
        (Decode.succeed ())
        toMsg


deleteComment : Session -> String -> String -> (Result Api.Error () -> msg) -> Cmd msg
deleteComment session slug commentId toMsg =
    Api.delete session (commentPath slug commentId "") (Decode.succeed ()) toMsg


undeleteComment : Session -> String -> String -> (Result Api.Error () -> msg) -> Cmd msg
undeleteComment session slug commentId toMsg =
    Api.post session (commentPath slug commentId "/undelete") (Encode.object []) (Decode.succeed ()) toMsg


resolveComment : Session -> String -> String -> (Result Api.Error () -> msg) -> Cmd msg
resolveComment session slug commentId toMsg =
    Api.post session (commentPath slug commentId "/resolve") (Encode.object []) (Decode.succeed ()) toMsg


unresolveComment : Session -> String -> String -> (Result Api.Error () -> msg) -> Cmd msg
unresolveComment session slug commentId toMsg =
    Api.post session (commentPath slug commentId "/unresolve") (Encode.object []) (Decode.succeed ()) toMsg



-- ===== Paths & small decoders =====


wsPath : String -> String -> String
wsPath slug rest =
    "/papi/workspaces/" ++ Url.percentEncode slug ++ rest


docPath : String -> String -> String -> String
docPath slug docSlug rest =
    wsPath slug ("/docs/" ++ Url.percentEncode docSlug ++ rest)


commentPath : String -> String -> String -> String
commentPath slug commentId rest =
    wsPath slug ("/comments/" ++ Url.percentEncode commentId ++ rest)


kudosDecoder : Decoder KudosState
kudosDecoder =
    Decode.map2 KudosState
        (Decode.field "given_by_me" Decode.bool)
        (Decode.field "count" Decode.int)


shareInfoDecoder : Decoder ShareInfo
shareInfoDecoder =
    Decode.map2 ShareInfo
        (Decode.field "visibility" Decode.string)
        (Decode.field "shares" (Decode.list shareDecoder))


shareDecoder : Decoder Share
shareDecoder =
    Decode.map2 Share
        (optionalField "username" Decode.string)
        (withDefault "viewer" (optionalField "role" Decode.string))


memberDecoder : Decoder Member
memberDecoder =
    Decode.map2 Member
        (Decode.field "id" Decode.string)
        (Decode.field "username" Decode.string)


tagColorDecoder : Decoder (Maybe ( String, String ))
tagColorDecoder =
    Decode.map2
        (\slug color -> Maybe.map (Tuple.pair slug) color)
        (Decode.field "slug" Decode.string)
        (optionalField "color" Decode.string)


milestoneDecoder : Decoder Milestone
milestoneDecoder =
    Decode.map3 Milestone
        (Decode.field "name" Decode.string)
        (withDefault "" (optionalField "date" Decode.string))
        (optionalField "description" Decode.string)


andMap : Decoder a -> Decoder (a -> b) -> Decoder b
andMap =
    Decode.map2 (|>)


optionalField : String -> Decoder a -> Decoder (Maybe a)
optionalField field decoder =
    Decode.oneOf
        [ Decode.field field (Decode.nullable decoder)
        , Decode.succeed Nothing
        ]


optionalAt : List String -> Decoder a -> Decoder (Maybe a)
optionalAt path decoder =
    Decode.oneOf
        [ Decode.at path (Decode.nullable decoder)
        , Decode.succeed Nothing
        ]


withDefault : a -> Decoder (Maybe a) -> Decoder a
withDefault fallback =
    Decode.map (Maybe.withDefault fallback)
