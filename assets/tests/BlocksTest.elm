module BlocksTest exposing (suite)

{-| Decoder coverage for every block type in `Aveline.Contract`
(heading / paragraph / code / list / table / doc\_link / chart) plus the
read-time echoes (`doc_link.target`, chart `source`/`result` states) and
the full doc shape (`Views.doc_full`).
-}

import Api.Doc
import Doc.Blocks as Blocks exposing (Block(..), Cell(..), ChartResult(..), SpanLink(..), Viz(..))
import Expect
import Json.Decode as Decode
import Test exposing (Test, describe, test)


decodeBlock : String -> Result Decode.Error Block
decodeBlock =
    Decode.decodeString Blocks.blockDecoder


suite : Test
suite =
    describe "Doc.Blocks"
        [ describe "contract block types"
            [ test "heading" <|
                \_ ->
                    decodeBlock """{"type":"heading","level":2,"text":"Section title","id":"b_h"}"""
                        |> Expect.equal (Ok (Heading { id = Just "b_h", level = 2, text = "Section title" }))
            , test "heading defaults level to 3" <|
                \_ ->
                    decodeBlock """{"type":"heading","text":"T"}"""
                        |> Expect.equal (Ok (Heading { id = Nothing, level = 3, text = "T" }))
            , test "paragraph with marks and external link" <|
                \_ ->
                    decodeBlock
                        """{"type":"paragraph","id":"b_p","content":[
                            {"text":"Plain, then "},
                            {"text":"bold","marks":["bold"]},
                            {"text":"link","link":{"href":"https://example.com"}}
                        ]}"""
                        |> Expect.equal
                            (Ok
                                (Paragraph
                                    { id = Just "b_p"
                                    , content =
                                        [ { text = "Plain, then ", marks = [], link = Nothing }
                                        , { text = "bold", marks = [ "bold" ], link = Nothing }
                                        , { text = "link", marks = [], link = Just (Href "https://example.com") }
                                        ]
                                    }
                                )
                            )
            , test "paragraph doc-mention span with enriched target" <|
                \_ ->
                    decodeBlock
                        """{"type":"paragraph","content":[
                            {"text":"see","link":{"doc_id":"u-1","target":{"slug":"runbook","title":"Runbook","deleted":false}}}
                        ]}"""
                        |> Result.map
                            (\block ->
                                case block of
                                    Paragraph p ->
                                        List.map .link p.content

                                    _ ->
                                        []
                            )
                        |> Expect.equal
                            (Ok
                                [ Just
                                    (DocMention
                                        { docId = "u-1"
                                        , target =
                                            Just
                                                { slug = Just "runbook"
                                                , title = Just "Runbook"
                                                , summary = Nothing
                                                , tags = []
                                                , deleted = False
                                                , inaccessible = False
                                                }
                                        }
                                    )
                                ]
                            )
            , test "code" <|
                \_ ->
                    decodeBlock """{"type":"code","language":"elixir","content":"IO.puts(\\"hi\\")"}"""
                        |> Expect.equal (Ok (Code { id = Nothing, language = Just "elixir", content = "IO.puts(\"hi\")" }))
            , test "code with null language" <|
                \_ ->
                    decodeBlock """{"type":"code","language":null,"content":"x"}"""
                        |> Expect.equal (Ok (Code { id = Nothing, language = Nothing, content = "x" }))
            , test "list (unordered default)" <|
                \_ ->
                    decodeBlock
                        """{"type":"list","items":[
                            {"id":"li_1","content":[{"text":"first item"}]},
                            {"content":[{"text":"second item"}]}
                        ]}"""
                        |> Expect.equal
                            (Ok
                                (Listed
                                    { id = Nothing
                                    , ordered = False
                                    , items =
                                        [ { id = Just "li_1", content = [ { text = "first item", marks = [], link = Nothing } ] }
                                        , { id = Nothing, content = [ { text = "second item", marks = [], link = Nothing } ] }
                                        ]
                                    }
                                )
                            )
            , test "ordered list" <|
                \_ ->
                    decodeBlock """{"type":"list","ordered":true,"items":[]}"""
                        |> Expect.equal (Ok (Listed { id = Nothing, ordered = True, items = [] }))
            , test "table" <|
                \_ ->
                    decodeBlock
                        """{"type":"table","headers":["Name","Role"],"rows":[
                            [[{"text":"Ada"}],[{"text":"Engineer"}]]
                        ]}"""
                        |> Expect.equal
                            (Ok
                                (Table
                                    { id = Nothing
                                    , headers = [ "Name", "Role" ]
                                    , rows =
                                        [ [ [ { text = "Ada", marks = [], link = Nothing } ]
                                          , [ { text = "Engineer", marks = [], link = Nothing } ]
                                          ]
                                        ]
                                    }
                                )
                            )
            , test "doc_link with live target echo" <|
                \_ ->
                    decodeBlock
                        """{"type":"doc_link","id":"b_dl","doc_id":"u-2",
                            "note":[{"text":"See the deploy runbook."}],
                            "target":{"slug":"deploy","title":"Deploy","summary":"How to","tags":["ops"],"deleted":false}}"""
                        |> Expect.equal
                            (Ok
                                (DocLink
                                    { id = Just "b_dl"
                                    , target =
                                        Just
                                            { slug = Just "deploy"
                                            , title = Just "Deploy"
                                            , summary = Just "How to"
                                            , tags = [ "ops" ]
                                            , deleted = False
                                            , inaccessible = False
                                            }
                                    , note = Just [ { text = "See the deploy runbook.", marks = [], link = Nothing } ]
                                    }
                                )
                            )
            , test "doc_link with inaccessible target" <|
                \_ ->
                    decodeBlock """{"type":"doc_link","target":{"inaccessible":true}}"""
                        |> Result.map
                            (\block ->
                                case block of
                                    DocLink dl ->
                                        Maybe.map .inaccessible dl.target

                                    _ ->
                                        Nothing
                            )
                        |> Expect.equal (Ok (Just True))
            , test "chart (query_ref, bar viz, pending echo)" <|
                \_ ->
                    decodeBlock
                        """{"type":"chart","id":"b_c","query_ref":"daily_growth",
                            "viz":{"type":"bar","x":"day","y":"signups"},
                            "source":{"name":"prod","adapter":"postgres"},
                            "query_sql":"select 1",
                            "result":{"pending":true}}"""
                        |> Result.map
                            (\block ->
                                case block of
                                    Chart c ->
                                        Just
                                            ( c.queryRef
                                            , ( c.viz, c.result )
                                            , ( Maybe.andThen .adapter c.source, c.querySql )
                                            )

                                    _ ->
                                        Nothing
                            )
                        |> Expect.equal
                            (Ok
                                (Just
                                    ( Just "daily_growth"
                                    , ( XYViz { kind = "bar", x = "day", y = "signups" }, Pending )
                                    , ( Just "postgres", Just "select 1" )
                                    )
                                )
                            )
            , test "unknown type" <|
                \_ ->
                    decodeBlock """{"type":"mystery"}"""
                        |> Expect.equal (Ok (Unknown "mystery"))
            ]
        , describe "chart result states"
            [ test "error" <|
                \_ ->
                    Decode.decodeString Blocks.chartResultDecoder """{"error":"boom"}"""
                        |> Expect.equal (Ok (Failed "boom"))
            , test "idle" <|
                \_ ->
                    Decode.decodeString Blocks.chartResultDecoder """{"idle":true}"""
                        |> Expect.equal (Ok Idle)
            , test "rows with mixed cells" <|
                \_ ->
                    Decode.decodeString Blocks.chartResultDecoder
                        """{"columns":["day","n"],"rows":[["2026-01-01",3],["2026-01-02",null]],"truncated":true}"""
                        |> Result.map
                            (\result ->
                                case result of
                                    Rows r ->
                                        Just ( r.columns, r.rows, r.truncated )

                                    _ ->
                                        Nothing
                            )
                        |> Expect.equal
                            (Ok
                                (Just
                                    ( [ "day", "n" ]
                                    , [ [ CellString "2026-01-01", CellNumber 3 ]
                                      , [ CellString "2026-01-02", CellNull ]
                                      ]
                                    , True
                                    )
                                )
                            )
            ]
        , describe "chart viz variants"
            [ test "combo viz with axes" <|
                \_ ->
                    decodeBlock
                        """{"type":"chart","viz":{"type":"combo","x":"day","series":[
                            {"y":"a","type":"bar"},{"y":"b","type":"line","axis":"right"}
                        ]},"result":{"error":"x"}}"""
                        |> Result.map
                            (\block ->
                                case block of
                                    Chart c ->
                                        Just c.viz

                                    _ ->
                                        Nothing
                            )
                        |> Expect.equal
                            (Ok
                                (Just
                                    (ComboViz
                                        { x = "day"
                                        , series =
                                            [ { y = "a", seriesType = "bar", axis = Nothing }
                                            , { y = "b", seriesType = "line", axis = Just "right" }
                                            ]
                                        }
                                    )
                                )
                            )
            , test "missing viz defaults to table" <|
                \_ ->
                    decodeBlock """{"type":"chart","result":{"error":"x"}}"""
                        |> Result.map
                            (\block ->
                                case block of
                                    Chart c ->
                                        Just c.viz

                                    _ ->
                                        Nothing
                            )
                        |> Expect.equal (Ok (Just TableViz))
            ]
        , describe "helpers"
            [ test "blockSnippet on heading" <|
                \_ ->
                    decodeBlock """{"type":"heading","text":"Intro"}"""
                        |> Result.map Blocks.blockSnippet
                        |> Expect.equal (Ok (Just "Intro"))
            , test "cellText" <|
                \_ ->
                    List.map Blocks.cellText
                        [ CellNull, CellString "x", CellNumber 3, CellNumber 1.5, CellBool True ]
                        |> Expect.equal [ "", "x", "3", "1.5", "true" ]
            ]
        , describe "doc_full decoder"
            [ test "decodes the Views.doc_full shape" <|
                \_ ->
                    Decode.decodeString Api.Doc.docDecoder
                        """{
                            "id":"v-1","base_doc_id":"b-1","slug":"my-doc","title":"My Doc",
                            "summary":null,"tags":["ops"],"pin_slot":null,"orientation":false,
                            "version_number":3,
                            "owner":{"id":"u-1","username":"ada","display_name":null,"email":null},
                            "updated_at":"2026-09-01T12:00:00Z",
                            "blocks":[{"type":"heading","level":1,"text":"Hello","id":"b_h"}],
                            "intent":"why","operations":[],
                            "actor":{"type":"human","user":{"id":"u-1","username":"ada"}}
                        }"""
                        |> Result.map
                            (\doc ->
                                ( ( doc.slug, doc.versionNumber, doc.actorType )
                                , ( Maybe.map .username doc.owner, List.length doc.blocks )
                                )
                            )
                        |> Expect.equal
                            (Ok ( ( "my-doc", 3, "human" ), ( Just "ada", 1 ) ))
            ]
        ]
