module Activity.Feed exposing
    ( Event
    , FetchedPage
    , detail
    , eventDecoder
    , nextCursor
    , pageSize
    , requestLimit
    , responseDecoder
    , splitPage
    , verb
    )

{-| The activity feed's data layer: the /papi events wire shape and the
cursor pagination logic ported from ActivityLive (`load_page/3`).

The LV fetches `page_size + 1` rows to learn whether more pages exist
without a COUNT; we do the same over GET /events with `limit` and a
`before_id` cursor (the id of the last VISIBLE event — strictly-older
keyset pagination server-side, so no duplicates on ties).

-}

import Iso8601
import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Extra as DecodeExtra
import Time exposing (Posix)


type alias Event =
    { id : String
    , action : String
    , targetKind : Maybe String
    , targetSlug : Maybe String
    , targetLabel : Maybe String
    , actorType : String
    , actorName : Maybe String
    , tags : List String
    , intent : Maybe String
    , occurredAt : Posix
    }


{-| One decoded page split into what's shown and whether to offer more.
-}
type alias FetchedPage =
    { events : List Event
    , hasMore : Bool
    }


{-| Aveline.Pagination.default\_page\_size().
-}
pageSize : Int
pageSize =
    25


{-| Ask for one extra row so `splitPage` can flag `hasMore`.
-}
requestLimit : Int
requestLimit =
    pageSize + 1


{-| Mirror of ActivityLive.load\_page/3: if the server returned more
than a page, show `pageSize` and remember there's more.
-}
splitPage : List Event -> FetchedPage
splitPage fetched =
    if List.length fetched > pageSize then
        { events = List.take pageSize fetched, hasMore = True }

    else
        { events = fetched, hasMore = False }


{-| Cursor for the next request: the id of the oldest event currently
shown (feed is newest-first). Nothing when the list is empty.
-}
nextCursor : List Event -> Maybe String
nextCursor shown =
    List.head (List.reverse shown) |> Maybe.map .id


responseDecoder : Decoder (List Event)
responseDecoder =
    Decode.field "events" (Decode.list eventDecoder)


eventDecoder : Decoder Event
eventDecoder =
    let
        nullableField field =
            DecodeExtra.optionalField field (Decode.nullable Decode.string)
                |> Decode.map (Maybe.andThen identity)

        dataField field decoder =
            Decode.maybe (Decode.at [ "data", field ] decoder)
    in
    Decode.succeed Event
        |> DecodeExtra.andMap (Decode.field "id" Decode.string)
        |> DecodeExtra.andMap (Decode.field "action" Decode.string)
        |> DecodeExtra.andMap (nullableField "target_kind")
        |> DecodeExtra.andMap (nullableField "target_slug")
        |> DecodeExtra.andMap (nullableField "target_label")
        |> DecodeExtra.andMap (Decode.at [ "actor", "type" ] Decode.string)
        |> DecodeExtra.andMap
            (Decode.at [ "actor", "user" ]
                (Decode.nullable (Decode.field "username" Decode.string))
            )
        |> DecodeExtra.andMap
            (dataField "tags" (Decode.list Decode.string)
                |> Decode.map (Maybe.withDefault [])
            )
        |> DecodeExtra.andMap (dataField "intent" Decode.string)
        |> DecodeExtra.andMap (Decode.field "occurred_at" Iso8601.decoder)


{-| Verb phrasing per action — ActivityLive.verb/1 verbatim.
-}
verb : String -> String
verb action =
    case action of
        "doc_created" ->
            "created"

        "doc_edited" ->
            "edited"

        "doc_deleted" ->
            "deleted"

        "doc_restored" ->
            "restored"

        "doc_pinned" ->
            "pinned"

        "doc_unpinned" ->
            "unpinned"

        "doc_viewed" ->
            "read"

        "comment_created" ->
            "commented on"

        "comment_resolved" ->
            "resolved a comment on"

        "comment_unresolved" ->
            "reopened a comment on"

        "comment_deleted" ->
            "deleted a comment on"

        "kudos_given" ->
            "gave kudos to"

        "kudos_revoked" ->
            "took back kudos from"

        "member_joined" ->
            "joined as"

        "member_removed" ->
            "removed"

        "tag_renamed" ->
            "renamed tag"

        "tag_merged" ->
            "merged tag into"

        "tag_deleted" ->
            "deleted tag"

        other ->
            String.replace "_" " " other


{-| Optional one-liner after the target link — ActivityLive.detail/1:
tag list on doc\_created, else the intent on doc\_created / doc\_edited.
-}
detail : Event -> Maybe String
detail event =
    if event.action == "doc_created" && not (List.isEmpty event.tags) then
        Just ("tagged " ++ String.join " · " (List.map (\t -> "#" ++ t) event.tags))

    else if List.member event.action [ "doc_created", "doc_edited" ] then
        case event.intent of
            Just intent ->
                if intent == "" then
                    Nothing

                else
                    Just intent

            Nothing ->
                Nothing

    else
        Nothing
