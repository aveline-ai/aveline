module Doc.Blocks exposing
    ( Block(..)
    , Cell(..)
    , ChartBlock
    , ChartResult(..)
    , CodeBlock
    , DocLinkBlock
    , DocLinkTarget
    , HeadingBlock
    , ListItem
    , Listing
    , Mention
    , ParagraphBlock
    , RunResult
    , SeriesSpec
    , Source
    , Span
    , SpanLink(..)
    , TableBlock
    , Viz(..)
    , blockDecoder
    , blockId
    , blockSnippet
    , cellText
    , chartResultDecoder
    , runResultDecoder
    , spanDecoder
    , spanText
    )

{-| The v0 block model as read from the API — every block type in
`Aveline.Contract` plus the read-time echoes `Docs.enrich_blocks` merges
in (doc\_link `target`, chart `source` / `query_sql` / `result`).
Mirrors what `AvelineWeb.BlockRenderer` consumes.
-}

import Json.Decode as Decode exposing (Decoder)


type Block
    = Heading HeadingBlock
    | Paragraph ParagraphBlock
    | Code CodeBlock
    | Listed Listing
    | Table TableBlock
    | DocLink DocLinkBlock
    | Chart ChartBlock
    | Unknown String


type alias HeadingBlock =
    { id : Maybe String
    , level : Int
    , text : String
    }


type alias ParagraphBlock =
    { id : Maybe String
    , content : List Span
    }


type alias CodeBlock =
    { id : Maybe String
    , language : Maybe String
    , content : String
    }


type alias Listing =
    { id : Maybe String
    , ordered : Bool
    , items : List ListItem
    }


type alias ListItem =
    { id : Maybe String
    , content : List Span
    }


type alias TableBlock =
    { id : Maybe String
    , headers : List String
    , rows : List (List (List Span))
    }


type alias DocLinkBlock =
    { id : Maybe String
    , target : Maybe DocLinkTarget
    , note : Maybe (List Span)
    }


{-| Read-time echo of the linked doc. `deleted`/`inaccessible` degrade
the card; a live target has a slug.
-}
type alias DocLinkTarget =
    { slug : Maybe String
    , title : Maybe String
    , summary : Maybe String
    , tags : List String
    , deleted : Bool
    , inaccessible : Bool
    }


type alias ChartBlock =
    { id : Maybe String
    , queryRef : Maybe String
    , dataSourceId : Maybe String
    , inlineQuery : Maybe String
    , querySql : Maybe String
    , viz : Viz
    , source : Maybe Source
    , result : ChartResult
    }


type Viz
    = TableViz
    | XYViz { kind : String, x : String, y : String }
    | ComboViz { x : String, series : List SeriesSpec }
    | UnknownViz


type alias SeriesSpec =
    { y : String
    , seriesType : String
    , axis : Maybe String
    }


type alias Source =
    { name : Maybe String
    , adapter : Maybe String
    }


type ChartResult
    = Pending
    | Idle
    | Failed String
    | Rows RunResult


type alias RunResult =
    { columns : List String
    , rows : List (List Cell)
    , truncated : Bool
    , truncatedInputs : List String

    -- The untouched server rows JSON, passed straight through to the
    -- <aveline-chart> spec so cell values never round-trip lossily.
    , rawRows : Decode.Value
    }


type Cell
    = CellNull
    | CellString String
    | CellNumber Float
    | CellBool Bool



-- ===== Inline spans =====


type alias Span =
    { text : String
    , marks : List String
    , link : Maybe SpanLink
    }


type SpanLink
    = Href String
    | DocMention Mention


type alias Mention =
    { docId : String
    , target : Maybe DocLinkTarget
    }



-- ===== Decoders =====


blockDecoder : Decoder Block
blockDecoder =
    Decode.field "type" Decode.string
        |> Decode.andThen
            (\t ->
                case t of
                    "heading" ->
                        Decode.map Heading headingDecoder

                    "paragraph" ->
                        Decode.map Paragraph paragraphDecoder

                    "code" ->
                        Decode.map Code codeDecoder

                    "list" ->
                        Decode.map Listed listingDecoder

                    "table" ->
                        Decode.map Table tableDecoder

                    "doc_link" ->
                        Decode.map DocLink docLinkDecoder

                    "chart" ->
                        Decode.map Chart chartDecoder

                    other ->
                        Decode.succeed (Unknown other)
            )


idField : Decoder (Maybe String)
idField =
    optional "id" Decode.string


headingDecoder : Decoder HeadingBlock
headingDecoder =
    Decode.map3 HeadingBlock
        idField
        (withDefault 3 (optional "level" Decode.int))
        (withDefault "" (optional "text" Decode.string))


paragraphDecoder : Decoder ParagraphBlock
paragraphDecoder =
    Decode.map2 ParagraphBlock
        idField
        spansField


codeDecoder : Decoder CodeBlock
codeDecoder =
    Decode.map3 CodeBlock
        idField
        (optional "language" Decode.string)
        (withDefault "" (optional "content" Decode.string))


listingDecoder : Decoder Listing
listingDecoder =
    Decode.map3 Listing
        idField
        (withDefault False (optional "ordered" Decode.bool))
        (withDefault [] (optional "items" (Decode.list listItemDecoder)))


listItemDecoder : Decoder ListItem
listItemDecoder =
    Decode.map2 ListItem
        idField
        spansField


tableDecoder : Decoder TableBlock
tableDecoder =
    Decode.map3 TableBlock
        idField
        (withDefault [] (optional "headers" (Decode.list Decode.string)))
        (withDefault []
            (optional "rows"
                (Decode.list (Decode.list (nullDefault [] (Decode.list spanDecoder))))
            )
        )


docLinkDecoder : Decoder DocLinkBlock
docLinkDecoder =
    Decode.map3 DocLinkBlock
        idField
        (optional "target" targetDecoder)
        (optional "note" (Decode.list spanDecoder))


targetDecoder : Decoder DocLinkTarget
targetDecoder =
    Decode.map6 DocLinkTarget
        (optional "slug" Decode.string)
        (optional "title" Decode.string)
        (optional "summary" Decode.string)
        (withDefault [] (optional "tags" (Decode.list Decode.string)))
        (withDefault False (optional "deleted" Decode.bool))
        (withDefault False (optional "inaccessible" Decode.bool))


chartDecoder : Decoder ChartBlock
chartDecoder =
    Decode.map8 ChartBlock
        idField
        (optional "query_ref" Decode.string)
        (optional "data_source_id" Decode.string)
        (optional "query" Decode.string)
        (optional "query_sql" Decode.string)
        (withDefault TableViz (optional "viz" vizDecoder))
        (optional "source" sourceDecoder)
        (withDefault (Failed "no result") (optional "result" chartResultDecoder))


vizDecoder : Decoder Viz
vizDecoder =
    optional "type" Decode.string
        |> Decode.andThen
            (\t ->
                case Maybe.withDefault "table" t of
                    "table" ->
                        Decode.succeed TableViz

                    "line" ->
                        xyDecoder "line"

                    "bar" ->
                        xyDecoder "bar"

                    "combo" ->
                        Decode.map2 (\x series -> ComboViz { x = x, series = series })
                            (withDefault "" (optional "x" Decode.string))
                            (withDefault [] (optional "series" (Decode.list seriesSpecDecoder)))

                    _ ->
                        Decode.succeed UnknownViz
            )


xyDecoder : String -> Decoder Viz
xyDecoder kind =
    Decode.map2 (\x y -> XYViz { kind = kind, x = x, y = y })
        (withDefault "" (optional "x" Decode.string))
        (withDefault "" (optional "y" Decode.string))


seriesSpecDecoder : Decoder SeriesSpec
seriesSpecDecoder =
    Decode.map3 SeriesSpec
        (withDefault "" (optional "y" Decode.string))
        (withDefault "line" (optional "type" Decode.string))
        (optional "axis" Decode.string)


sourceDecoder : Decoder Source
sourceDecoder =
    Decode.map2 Source
        (optional "name" Decode.string)
        (optional "adapter" Decode.string)


chartResultDecoder : Decoder ChartResult
chartResultDecoder =
    Decode.oneOf
        [ Decode.field "pending" Decode.bool
            |> Decode.andThen (always (Decode.succeed Pending))
        , Decode.field "idle" Decode.bool
            |> Decode.andThen (always (Decode.succeed Idle))
        , Decode.field "error" Decode.string |> Decode.map Failed
        , Decode.map Rows runResultDecoder
        ]


runResultDecoder : Decoder RunResult
runResultDecoder =
    Decode.map5 RunResult
        (Decode.field "columns" (Decode.list Decode.string))
        (Decode.field "rows" (Decode.list (Decode.list cellDecoder)))
        (withDefault False (optional "truncated" Decode.bool))
        (withDefault [] (optional "truncated_inputs" (Decode.list Decode.string)))
        (Decode.field "rows" Decode.value)


cellDecoder : Decoder Cell
cellDecoder =
    Decode.oneOf
        [ Decode.null CellNull
        , Decode.map CellNumber Decode.float
        , Decode.map CellBool Decode.bool
        , Decode.map CellString Decode.string
        ]


spansField : Decoder (List Span)
spansField =
    withDefault [] (optional "content" (Decode.list spanDecoder))


spanDecoder : Decoder Span
spanDecoder =
    Decode.map3 Span
        (withDefault "" (optional "text" Decode.string))
        (withDefault [] (optional "marks" (Decode.list Decode.string)))
        (optional "link" spanLinkDecoder |> Decode.map (Maybe.andThen identity))


spanLinkDecoder : Decoder (Maybe SpanLink)
spanLinkDecoder =
    Decode.oneOf
        [ Decode.map2 (\docId target -> Just (DocMention { docId = docId, target = target }))
            (Decode.field "doc_id" Decode.string)
            (optional "target" targetDecoder)
        , Decode.field "href" Decode.string |> Decode.map (Href >> Just)
        , Decode.succeed Nothing
        ]



-- ===== Helpers =====


blockId : Block -> Maybe String
blockId block =
    case block of
        Heading b ->
            b.id

        Paragraph b ->
            b.id

        Code b ->
            b.id

        Listed b ->
            b.id

        Table b ->
            b.id

        DocLink b ->
            b.id

        Chart b ->
            b.id

        Unknown _ ->
            Nothing


{-| First line / first words of a block — the orphan-thread caption
(port of `DocShowLive.block_snippet/1`).
-}
blockSnippet : Block -> Maybe String
blockSnippet block =
    case block of
        Heading b ->
            Just (String.left 80 b.text)

        Code b ->
            Just (String.left 80 b.content)

        Paragraph b ->
            Just (String.left 120 (spanText b.content))

        Listed b ->
            case b.items of
                first :: _ ->
                    case first.content of
                        [] ->
                            Nothing

                        content ->
                            Just (String.left 120 (spanText content))

                [] ->
                    Nothing

        _ ->
            Nothing


spanText : List Span -> String
spanText spans =
    String.concat (List.map .text spans)


{-| Table-cell display text (port of `BlockRenderer.display_cell/1`).
-}
cellText : Cell -> String
cellText cell =
    case cell of
        CellNull ->
            ""

        CellString s ->
            s

        CellBool True ->
            "true"

        CellBool False ->
            "false"

        CellNumber n ->
            if toFloat (round n) == n && abs n < 1.0e15 then
                String.fromInt (round n)

            else
                String.fromFloat n



-- Local decoder helpers (optional field that tolerates null).


optional : String -> Decoder a -> Decoder (Maybe a)
optional field decoder =
    Decode.oneOf
        [ Decode.field field (Decode.nullable decoder)
        , Decode.succeed Nothing
        ]


withDefault : a -> Decoder (Maybe a) -> Decoder a
withDefault fallback =
    Decode.map (Maybe.withDefault fallback)


nullDefault : a -> Decoder a -> Decoder a
nullDefault fallback decoder =
    Decode.oneOf [ Decode.null fallback, decoder ]
