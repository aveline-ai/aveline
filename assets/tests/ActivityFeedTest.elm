module ActivityFeedTest exposing (suite)

{-| Decoder and cursor-pagination coverage for the Activity feed
(Activity.Feed), matching the /papi events wire shape from
AvelineWeb.Api.Views.event/1 and ActivityLive's load\_page logic.
-}

import Activity.Feed as Feed
import Expect
import Json.Decode as Decode
import Test exposing (Test, describe, test)
import Time


fullEventJson : String
fullEventJson =
    """
    {
      "id": "ev-42",
      "action": "doc_created",
      "target_kind": "doc",
      "target_id": "d-1",
      "target_slug": "welcome",
      "target_label": "Welcome",
      "actor": {"type": "agent", "user": {"id": "u-1", "username": "arie", "display_name": null, "email": null}},
      "data": {"tags": ["ops", "metrics"], "intent": "seed the workspace"},
      "occurred_at": "2026-09-08T12:30:00Z"
    }
    """


minimalEventJson : String
minimalEventJson =
    """
    {
      "id": "ev-1",
      "action": "member_joined",
      "target_kind": null,
      "target_id": null,
      "target_slug": null,
      "target_label": "member",
      "actor": {"type": "human", "user": null},
      "data": {},
      "occurred_at": "2026-09-08T12:30:00.123456Z"
    }
    """


mkEvent : String -> Feed.Event
mkEvent id =
    { id = id
    , action = "doc_edited"
    , targetKind = Just "doc"
    , targetSlug = Just "s"
    , targetLabel = Just "S"
    , actorType = "human"
    , actorName = Just "arie"
    , tags = []
    , intent = Nothing
    , occurredAt = Time.millisToPosix 0
    }


suite : Test
suite =
    describe "Activity.Feed"
        [ describe "eventDecoder"
            [ test "decodes a fully populated event" <|
                \_ ->
                    Decode.decodeString Feed.eventDecoder fullEventJson
                        |> Expect.equal
                            (Ok
                                { id = "ev-42"
                                , action = "doc_created"
                                , targetKind = Just "doc"
                                , targetSlug = Just "welcome"
                                , targetLabel = Just "Welcome"
                                , actorType = "agent"
                                , actorName = Just "arie"
                                , tags = [ "ops", "metrics" ]
                                , intent = Just "seed the workspace"
                                , occurredAt = Time.millisToPosix 1788870600000
                                }
                            )
            , test "decodes null target fields, null actor user, and empty data" <|
                \_ ->
                    Decode.decodeString Feed.eventDecoder minimalEventJson
                        |> Result.map
                            (\e ->
                                ( ( e.targetKind, e.targetSlug, e.actorName )
                                , ( e.tags, e.intent, e.targetLabel )
                                )
                            )
                        |> Expect.equal
                            (Ok ( ( Nothing, Nothing, Nothing ), ( [], Nothing, Just "member" ) ))
            , test "responseDecoder unwraps the events field" <|
                \_ ->
                    Decode.decodeString Feed.responseDecoder
                        ("{\"ok\": true, \"events\": [" ++ fullEventJson ++ "], \"next_before_id\": \"ev-42\"}")
                        |> Result.map (List.map .id)
                        |> Expect.equal (Ok [ "ev-42" ])
            ]
        , describe "splitPage"
            [ test "a short page has no more" <|
                \_ ->
                    Feed.splitPage (List.map (String.fromInt >> mkEvent) (List.range 1 3))
                        |> Expect.equal
                            { events = List.map (String.fromInt >> mkEvent) (List.range 1 3)
                            , hasMore = False
                            }
            , test "exactly pageSize rows has no more" <|
                \_ ->
                    Feed.splitPage (List.map (String.fromInt >> mkEvent) (List.range 1 Feed.pageSize))
                        |> .hasMore
                        |> Expect.equal False
            , test "the sentinel extra row flags more and is not shown" <|
                \_ ->
                    let
                        page =
                            Feed.splitPage
                                (List.map (String.fromInt >> mkEvent) (List.range 1 Feed.requestLimit))
                    in
                    ( List.length page.events, page.hasMore )
                        |> Expect.equal ( Feed.pageSize, True )
            , test "empty page" <|
                \_ ->
                    Feed.splitPage []
                        |> Expect.equal { events = [], hasMore = False }
            ]
        , describe "nextCursor"
            [ test "is the id of the oldest (last) shown event" <|
                \_ ->
                    Feed.nextCursor [ mkEvent "new", mkEvent "mid", mkEvent "old" ]
                        |> Expect.equal (Just "old")
            , test "is Nothing for an empty feed" <|
                \_ ->
                    Feed.nextCursor [] |> Expect.equal Nothing
            ]
        , describe "verb"
            [ test "maps known actions" <|
                \_ ->
                    Feed.verb "comment_resolved" |> Expect.equal "resolved a comment on"
            , test "falls back to underscores-to-spaces" <|
                \_ ->
                    Feed.verb "view_pinned" |> Expect.equal "view pinned"
            ]
        , describe "detail"
            [ test "doc_created with tags wins over intent" <|
                \_ ->
                    Decode.decodeString Feed.eventDecoder fullEventJson
                        |> Result.map Feed.detail
                        |> Expect.equal (Ok (Just "tagged #ops · #metrics"))
            , test "doc_edited shows the intent" <|
                \_ ->
                    Feed.detail
                        (mkEvent "e" |> (\e -> { e | action = "doc_edited", intent = Just "tighten copy" }))
                        |> Expect.equal (Just "tighten copy")
            , test "blank intent is suppressed" <|
                \_ ->
                    Feed.detail
                        (mkEvent "e" |> (\e -> { e | action = "doc_edited", intent = Just "" }))
                        |> Expect.equal Nothing
            , test "other actions have no detail" <|
                \_ ->
                    Feed.detail
                        (mkEvent "e" |> (\e -> { e | action = "doc_deleted", intent = Just "x" }))
                        |> Expect.equal Nothing
            ]
        ]
