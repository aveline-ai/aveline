module ApiDocsTest exposing (suite)

{-| Decoder coverage for the Docs page's API payloads (envelope bodies
from /tags, /members, /views, /fe/docs-list, /fe/docs-facets).
-}

import Api.Docs as ApiDocs
import Dict
import Expect
import Json.Decode as Decode
import Test exposing (Test, describe, test)
import Time


docJson : String
docJson =
    """
    { "ok": true,
      "has_more": true,
      "docs": [
        { "id": "v-1",
          "base_doc_id": "b-1",
          "slug": "deploy-runbook",
          "title": "Deploy runbook",
          "summary": "How we ship",
          "tags": ["runbook", "status:done"],
          "pin_slot": null,
          "orientation": false,
          "version_number": 3,
          "owner": {"id": "u-1", "username": "arie", "display_name": null, "email": null},
          "updated_at": "2026-09-01T12:30:00Z",
          "visibility": "private",
          "actor_user": {"id": "u-1", "username": "arie", "display_name": null, "email": null},
          "view_count": 7,
          "kudos_count": 2
        },
        { "id": "v-2",
          "base_doc_id": "b-2",
          "slug": "notes",
          "title": "Notes",
          "summary": null,
          "tags": [],
          "updated_at": null,
          "visibility": "workspace",
          "actor_user": null,
          "view_count": 0,
          "kudos_count": 0
        }
      ]
    }
    """


suite : Test
suite =
    describe "Api.Docs decoders"
        [ test "docsPageDecoder decodes enriched docs + has_more" <|
            \_ ->
                case Decode.decodeString ApiDocs.docsPageDecoder docJson of
                    Err e ->
                        Expect.fail (Decode.errorToString e)

                    Ok page ->
                        case page.docs of
                            [ first, second ] ->
                                Expect.all
                                    [ \_ -> Expect.equal True page.hasMore
                                    , \_ -> Expect.equal "b-1" first.baseDocId
                                    , \_ -> Expect.equal (Just "How we ship") first.summary
                                    , \_ -> Expect.equal [ "runbook", "status:done" ] first.tags
                                    , \_ -> Expect.equal "private" first.visibility
                                    , \_ -> Expect.equal (Just "arie") (first.actorUser |> Maybe.map .username)
                                    , \_ ->
                                        Expect.equal (Just 1788265800000)
                                            (first.updatedAt |> Maybe.map Time.posixToMillis)
                                    , \_ -> Expect.equal 7 first.viewCount
                                    , \_ -> Expect.equal 2 first.kudosCount
                                    , \_ -> Expect.equal Nothing second.summary
                                    , \_ -> Expect.equal Nothing second.actorUser
                                    , \_ -> Expect.equal Nothing second.updatedAt
                                    ]
                                    ()

                            _ ->
                                Expect.fail "expected exactly two docs"
        , test "tagsDecoder keeps registry order and colors" <|
            \_ ->
                """{"ok": true, "tags": [
                     {"slug": "status:todo", "description": "…", "color": "#ff0000", "sort_key": "1", "doc_count": 2},
                     {"slug": "runbook", "description": "…", "color": null, "doc_count": 0}
                   ]}"""
                    |> Decode.decodeString ApiDocs.tagsDecoder
                    |> Expect.equal
                        (Ok
                            [ { slug = "status:todo", color = Just "#ff0000" }
                            , { slug = "runbook", color = Nothing }
                            ]
                        )
        , test "membersDecoder pulls usernames" <|
            \_ ->
                """{"ok": true, "members": [
                     {"id": "u-1", "username": "zoe", "role": "member", "joined_at": "2026-01-01T00:00:00Z"},
                     {"id": "u-2", "username": "arie", "role": "owner", "joined_at": "2026-01-01T00:00:00Z"}
                   ]}"""
                    |> Decode.decodeString ApiDocs.membersDecoder
                    |> Expect.equal (Ok [ { username = "zoe" }, { username = "arie" } ])
        , test "viewsDecoder decodes config knobs, bucket, pinned" <|
            \_ ->
                """{"ok": true, "views": [
                     { "name": "roadmap",
                       "description": "What's next",
                       "config": {"tags": ["roadmap"], "group_by": "status", "sort": "kudos"},
                       "pinned": true,
                       "bucket": {"name": "team", "kind": "team"},
                       "version_number": 1,
                       "created_at": "2026-06-01T00:00:00Z"
                     },
                     { "name": "bare", "description": null, "config": {}, "pinned": false, "bucket": null }
                   ]}"""
                    |> Decode.decodeString ApiDocs.viewsDecoder
                    |> Expect.equal
                        (Ok
                            [ { name = "roadmap"
                              , description = Just "What's next"
                              , config =
                                    { tags = [ "roadmap" ]
                                    , groupBy = Just "status"
                                    , subGroupBy = Nothing
                                    , sort = Just "kudos"
                                    , edited = Nothing
                                    }
                              , pinned = True
                              , bucket = Just { name = "team", kind = "team" }
                              }
                            , { name = "bare"
                              , description = Nothing
                              , config =
                                    { tags = []
                                    , groupBy = Nothing
                                    , subGroupBy = Nothing
                                    , sort = Nothing
                                    , edited = Nothing
                                    }
                              , pinned = False
                              , bucket = Nothing
                              }
                            ]
                        )
        , test "facetsDecoder decodes tag + author count maps" <|
            \_ ->
                """{"ok": true, "tags": {"runbook": 3, "status:todo": 1}, "authors": {"arie": 4, "zoe": 0}}"""
                    |> Decode.decodeString ApiDocs.facetsDecoder
                    |> Expect.equal
                        (Ok
                            { tags = Dict.fromList [ ( "runbook", 3 ), ( "status:todo", 1 ) ]
                            , authors = Dict.fromList [ ( "arie", 4 ), ( "zoe", 0 ) ]
                            }
                        )
        ]
