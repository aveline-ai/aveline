module Doc.Comments exposing
    ( Comment
    , CommentView(..)
    , Grouped
    , Thread
    , UserRef
    , commentDecoder
    , commentViewWord
    , filterForView
    , groupThreads
    , partitionReplies
    )

{-| Comment shapes + the thread bookkeeping the LiveView did in
`render/1`: view filtering, grouping into threads (anchored / doc-level
/ orphaned) and resolved-thread reply collapsing. All pure, all
unit-tested.
-}

import Dict exposing (Dict)
import Iso8601
import Json.Decode as Decode exposing (Decoder)
import Set exposing (Set)
import Time exposing (Posix)


type alias UserRef =
    { id : String
    , username : String
    }


type alias Comment =
    { id : String -- base_comment_id: the stable logical id
    , docId : String -- the doc-version row this comment is pinned to
    , blockId : Maybe String
    , parentId : Maybe String
    , body : String
    , actorType : String
    , actorUser : Maybe UserRef
    , resolvedAt : Maybe Posix
    , resolvedBy : Maybe UserRef
    , resolvedInVersion : Maybe Int
    , resolvedByDocId : Maybe String
    , editedAt : Maybe Posix
    , deletedAt : Maybe Posix
    , deletedBy : Maybe UserRef
    , createdAt : Maybe Posix
    , contextSnippet : Maybe String
    }


type alias Thread =
    { parent : Comment
    , replies : List Comment
    }


type alias Grouped =
    { byBlock : Dict String (List Thread)
    , docLevel : List Thread
    , orphans : List Thread
    }


{-| The 3-state comment toggle: open (default working view), all
(includes resolved + deleted), hide (clean reading mode).
-}
type CommentView
    = Open
    | All
    | Hide


commentViewWord : CommentView -> String
commentViewWord view =
    case view of
        Open ->
            "open"

        All ->
            "all"

        Hide ->
            "hidden"



-- ===== Decoder =====


commentDecoder : Decoder Comment
commentDecoder =
    Decode.succeed Comment
        |> andMap (Decode.field "id" Decode.string)
        |> andMap (Decode.field "doc_id" Decode.string)
        |> andMap (optionalField "block_id" Decode.string)
        |> andMap (optionalField "parent_comment_id" Decode.string)
        |> andMap (withDefault "" (optionalField "body" Decode.string))
        |> andMap (withDefault "" (optionalAt [ "actor", "type" ] Decode.string))
        |> andMap (optionalAt [ "actor", "user" ] userRefDecoder)
        |> andMap (optionalField "resolved_at" Iso8601.decoder)
        |> andMap (optionalField "resolved_by" userRefDecoder)
        |> andMap (optionalField "resolved_in_version" Decode.int)
        |> andMap (optionalField "resolved_by_doc_id" Decode.string)
        |> andMap (optionalField "edited_at" Iso8601.decoder)
        |> andMap (optionalField "deleted_at" Iso8601.decoder)
        |> andMap (optionalField "deleted_by" userRefDecoder)
        |> andMap (optionalField "created_at" Iso8601.decoder)
        |> andMap (optionalField "context_snippet" Decode.string)


userRefDecoder : Decoder UserRef
userRefDecoder =
    Decode.map2 UserRef
        (Decode.field "id" Decode.string)
        (Decode.field "username" Decode.string)


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
optionalAt fieldPath decoder =
    Decode.oneOf
        [ Decode.at fieldPath (Decode.nullable decoder)
        , Decode.succeed Nothing
        ]


withDefault : a -> Decoder (Maybe a) -> Decoder a
withDefault fallback =
    Decode.map (Maybe.withDefault fallback)



-- ===== View filtering =====


{-| In Open view resolved top-level threads (and their replies) drop
out. All/Hide pass through (hide renders nothing downstream). Port of
`filter_messages_for_view/2`.
-}
filterForView : CommentView -> List Comment -> List Comment
filterForView view comments =
    case view of
        Open ->
            let
                resolvedTops =
                    comments
                        |> List.filter (\c -> c.parentId == Nothing && c.resolvedAt /= Nothing)
                        |> List.map .id
                        |> Set.fromList

                hidden c =
                    case c.parentId of
                        Nothing ->
                            Set.member c.id resolvedTops

                        Just pid ->
                            Set.member pid resolvedTops
            in
            List.filter (not << hidden) comments

        _ ->
            comments



-- ===== Grouping =====


{-| Builds {anchored-by-block, doc-level, orphans}. Anchored threads
whose block still exists render inline under the block; doc-level ones
(no block\_id) at the top; orphans (block deleted in a later edit) in
their own section. Port of `group_threads/2`.
-}
groupThreads : List String -> List Comment -> Grouped
groupThreads currentBlockIds comments =
    let
        blockSet =
            Set.fromList currentBlockIds

        topLevels =
            List.filter (\c -> c.parentId == Nothing) comments

        repliesFor parentId =
            List.filter (\c -> c.parentId == Just parentId) comments

        threads =
            List.map (\p -> { parent = p, replies = repliesFor p.id }) topLevels

        place thread grouped =
            case thread.parent.blockId of
                Nothing ->
                    { grouped | docLevel = grouped.docLevel ++ [ thread ] }

                Just "" ->
                    { grouped | docLevel = grouped.docLevel ++ [ thread ] }

                Just bid ->
                    if Set.member bid blockSet then
                        { grouped
                            | byBlock =
                                Dict.update bid
                                    (\existing -> Just (Maybe.withDefault [] existing ++ [ thread ]))
                                    grouped.byBlock
                        }

                    else
                        { grouped | orphans = grouped.orphans ++ [ thread ] }
    in
    List.foldl place { byBlock = Dict.empty, docLevel = [], orphans = [] } threads



-- ===== Resolved-thread collapsing =====


{-| For a resolved thread, collapse everything between the question and
the reply that actually resolved it (`tail` = the resolving reply, or
the last one as fallback; `hidden` = the rest). Open threads keep every
reply visible. Port of `partition_replies/1`.
-}
partitionReplies : Thread -> { hidden : List Comment, tail : List Comment }
partitionReplies thread =
    if thread.parent.resolvedAt == Nothing || List.isEmpty thread.replies then
        { hidden = [], tail = thread.replies }

    else
        let
            resolving =
                thread.replies
                    |> List.filter (\r -> Just r.docId == thread.parent.resolvedByDocId)
                    |> List.head
                    |> Maybe.withDefault
                        (thread.replies
                            |> List.reverse
                            |> List.head
                            |> Maybe.withDefault thread.parent
                        )
        in
        { hidden = List.filter (\r -> r.id /= resolving.id) thread.replies
        , tail = [ resolving ]
        }
