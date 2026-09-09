module CommentsTest exposing (suite)

{-| Comment decoding + the thread bookkeeping ported from the LiveView:
view filtering, grouping (anchored / doc-level / orphaned) and
resolved-thread reply collapsing.
-}

import Dict
import Doc.Comments as Comments exposing (Comment, CommentView(..))
import Expect
import Json.Decode as Decode
import Test exposing (Test, describe, test)
import Time


base : Comment
base =
    { id = "c1"
    , docId = "v1"
    , blockId = Nothing
    , parentId = Nothing
    , body = "hello"
    , actorType = "human"
    , actorUser = Just { id = "u1", username = "ada" }
    , resolvedAt = Nothing
    , resolvedBy = Nothing
    , resolvedInVersion = Nothing
    , resolvedByDocId = Nothing
    , editedAt = Nothing
    , deletedAt = Nothing
    , deletedBy = Nothing
    , createdAt = Nothing
    , contextSnippet = Nothing
    }


mk : String -> Maybe String -> Maybe String -> Comment
mk id parentId blockId =
    { base | id = id, parentId = parentId, blockId = blockId }


resolved : Comment -> Comment
resolved c =
    { c | resolvedAt = Just (Time.millisToPosix 0) }


suite : Test
suite =
    describe "Doc.Comments"
        [ describe "commentDecoder"
            [ test "decodes the reader comment shape" <|
                \_ ->
                    Decode.decodeString Comments.commentDecoder
                        """{
                            "id":"base-1","version_id":"row-9","version_number":2,
                            "doc_id":"v-1","block_id":"b_x","parent_comment_id":null,
                            "body":"why?",
                            "actor":{"type":"agent","user":{"id":"u-2","username":"bot","display_name":null,"email":null}},
                            "resolved_at":"2026-09-01T10:00:00Z",
                            "resolved_by":{"id":"u-1","username":"ada"},
                            "resolved_in_version":4,
                            "resolved_by_doc_id":"v-4",
                            "edited_at":null,"deleted_at":null,"deleted_by":null,
                            "created_at":"2026-08-30T09:00:00Z",
                            "context_snippet":"Intro"
                        }"""
                        |> Result.map
                            (\c ->
                                ( ( c.id, c.docId, c.blockId )
                                , ( c.actorType, Maybe.map .username c.actorUser, c.resolvedInVersion )
                                , ( c.resolvedByDocId, c.contextSnippet, c.resolvedAt /= Nothing )
                                )
                            )
                        |> Expect.equal
                            (Ok
                                ( ( "base-1", "v-1", Just "b_x" )
                                , ( "agent", Just "bot", Just 4 )
                                , ( Just "v-4", Just "Intro", True )
                                )
                            )
            , test "tolerates missing optional fields" <|
                \_ ->
                    Decode.decodeString Comments.commentDecoder
                        """{"id":"c","doc_id":"v","body":"b","actor":{"type":"human","user":null}}"""
                        |> Result.map (\c -> ( c.actorUser, c.deletedAt, c.contextSnippet ))
                        |> Expect.equal (Ok ( Nothing, Nothing, Nothing ))
            ]
        , describe "filterForView"
            [ test "open view drops resolved top-level threads and their replies" <|
                \_ ->
                    let
                        comments =
                            [ resolved (mk "t1" Nothing Nothing)
                            , mk "r1" (Just "t1") Nothing
                            , mk "t2" Nothing Nothing
                            , mk "r2" (Just "t2") Nothing
                            ]
                    in
                    Comments.filterForView Open comments
                        |> List.map .id
                        |> Expect.equal [ "t2", "r2" ]
            , test "all view passes everything through" <|
                \_ ->
                    let
                        comments =
                            [ resolved (mk "t1" Nothing Nothing), mk "r1" (Just "t1") Nothing ]
                    in
                    Comments.filterForView All comments
                        |> List.map .id
                        |> Expect.equal [ "t1", "r1" ]
            ]
        , describe "groupThreads"
            [ test "splits anchored / doc-level / orphaned" <|
                \_ ->
                    let
                        comments =
                            [ mk "anchored" Nothing (Just "b_live")
                            , mk "reply" (Just "anchored") (Just "b_live")
                            , mk "doclevel" Nothing Nothing
                            , mk "empty-block" Nothing (Just "")
                            , mk "orphan" Nothing (Just "b_gone")
                            ]

                        grouped =
                            Comments.groupThreads [ "b_live", "b_other" ] comments
                    in
                    Expect.all
                        [ \g ->
                            Dict.get "b_live" g.byBlock
                                |> Maybe.map (List.map (\t -> ( t.parent.id, List.map .id t.replies )))
                                |> Expect.equal (Just [ ( "anchored", [ "reply" ] ) ])
                        , \g ->
                            List.map (.parent >> .id) g.docLevel
                                |> Expect.equal [ "doclevel", "empty-block" ]
                        , \g ->
                            List.map (.parent >> .id) g.orphans
                                |> Expect.equal [ "orphan" ]
                        ]
                        grouped
            , test "replies attach by parent base id" <|
                \_ ->
                    let
                        grouped =
                            Comments.groupThreads []
                                [ mk "t" Nothing Nothing
                                , mk "r1" (Just "t") Nothing
                                , mk "r2" (Just "t") Nothing
                                ]
                    in
                    grouped.docLevel
                        |> List.map (\t -> List.map .id t.replies)
                        |> Expect.equal [ [ "r1", "r2" ] ]
            ]
        , describe "partitionReplies"
            [ test "open thread keeps all replies visible" <|
                \_ ->
                    Comments.partitionReplies
                        { parent = mk "t" Nothing Nothing
                        , replies = [ mk "r1" (Just "t") Nothing, mk "r2" (Just "t") Nothing ]
                        }
                        |> (\p -> ( List.map .id p.hidden, List.map .id p.tail ))
                        |> Expect.equal ( [], [ "r1", "r2" ] )
            , test "resolved thread collapses everything but the resolving reply" <|
                \_ ->
                    let
                        parent =
                            { base | id = "t", resolvedAt = Just (Time.millisToPosix 0), resolvedByDocId = Just "v-9" }

                        resolvingReply =
                            { base | id = "r2", parentId = Just "t", docId = "v-9" }
                    in
                    Comments.partitionReplies
                        { parent = parent
                        , replies = [ mk "r1" (Just "t") Nothing, resolvingReply, mk "r3" (Just "t") Nothing ]
                        }
                        |> (\p -> ( List.map .id p.hidden, List.map .id p.tail ))
                        |> Expect.equal ( [ "r1", "r3" ], [ "r2" ] )
            , test "resolved thread without a resolving reply keeps the last one" <|
                \_ ->
                    Comments.partitionReplies
                        { parent = resolved (mk "t" Nothing Nothing)
                        , replies = [ mk "r1" (Just "t") Nothing, mk "r2" (Just "t") Nothing ]
                        }
                        |> (\p -> ( List.map .id p.hidden, List.map .id p.tail ))
                        |> Expect.equal ( [ "r1" ], [ "r2" ] )
            , test "resolved thread with no replies collapses nothing" <|
                \_ ->
                    Comments.partitionReplies { parent = resolved (mk "t" Nothing Nothing), replies = [] }
                        |> Expect.equal { hidden = [], tail = [] }
            ]
        ]
