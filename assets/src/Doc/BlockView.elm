module Doc.BlockView exposing
    ( Config
    , blockIdAttr
    , chartStatic
    , resultsTable
    , view
    , viewSpans
    )

{-| The block renderer shared by every page that shows doc blocks —
the port of `AvelineWeb.BlockRenderer`. `Page.DocShow` drives it with
its live gutter (copy-link + comment button) and async chart runs; the
read-only pages (`Page.Guide`) pass a silent gutter and `chartStatic`.

Everything that varies per host page comes in through `Config`; the
block markup and classes themselves are identical everywhere, so the
stylesheet's `.blk-*` rules apply unchanged.

-}

import Doc.Blocks as Blocks exposing (Block(..), ChartBlock, ChartResult(..), Span, SpanLink(..))
import Html exposing (Html, a, code, div, h1, h2, h3, li, ol, p, span, strong, table, tbody, td, text, th, thead, tr, ul)
import Html.Attributes exposing (attribute, class, href, id, title)
import Route
import Ui.Icons as Icons


{-| What a host page contributes to each block:

  - `slug` — the workspace, for doc-mention and doc-link hrefs.
  - `gutter` — the per-block gutter (anchor + comment button on the
    doc page); `always (text "")` for read-only pages.
  - `tagChip` — how a tag on a doc-link card is drawn (the doc page
    colours them from its tag palette).
  - `chart` — the chart block renderer (`chartStatic` when the page
    can't run queries).

-}
type alias Config msg =
    { slug : String
    , gutter : Maybe String -> Html msg
    , tagChip : String -> Html msg
    , chart : ChartBlock -> Html msg
    }


view : Config msg -> Block -> Html msg
view config block =
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
                [ config.gutter b.id, text b.text ]

        Paragraph b ->
            p (blockIdAttr b.id ++ [ class "blk-p blk-anchored" ])
                (config.gutter b.id :: viewSpans config b.content)

        Code b ->
            div [ class "blk-code-wrap blk-anchored" ]
                [ config.gutter b.id
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
                (config.gutter b.id
                    :: List.map
                        (\item ->
                            li (blockIdAttr item.id) (viewSpans config item.content)
                        )
                        b.items
                )

        Table b ->
            div [ class "blk-table-wrap blk-anchored" ]
                [ config.gutter b.id
                , table (blockIdAttr b.id ++ [ class "blk-table" ])
                    [ thead []
                        [ tr [] (List.map (\h -> th [] [ text h ]) b.headers) ]
                    , tbody []
                        (List.map
                            (\row ->
                                tr [] (List.map (\cell -> td [] (viewSpans config cell)) row)
                            )
                            b.rows
                        )
                    ]
                ]

        DocLink b ->
            viewDocLink config b

        Chart b ->
            config.chart b

        Unknown typeName ->
            div [ class "blk-unknown" ] [ text ("Unknown block type: " ++ typeName) ]


blockIdAttr : Maybe String -> List (Html.Attribute msg)
blockIdAttr maybeId =
    case maybeId of
        Just theId ->
            [ id theId ]

        Nothing ->
            []



-- ===== Inline spans =====


viewSpans : Config msg -> List Span -> List (Html msg)
viewSpans config spans =
    List.map (\s -> span [] [ viewSpan config s ]) spans


viewSpan : Config msg -> Span -> Html msg
viewSpan config s =
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
                                , href (Route.href (Route.DocShow config.slug slug))
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


viewDocLink : Config msg -> Blocks.DocLinkBlock -> Html msg
viewDocLink config b =
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
            [ [ config.gutter b.id ]
            , [ case ( live, b.target ) of
                    ( True, Just target ) ->
                        a
                            [ href (Route.href (Route.DocShow config.slug (Maybe.withDefault "" target.slug)))
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
                                        (List.map config.tagChip target.tags)
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
                    [ p [ class "doc-link-note" ] (viewSpans config note) ]

                Nothing ->
                    []
            ]
        )



-- ===== chart =====


{-| A chart block on a page that cannot run queries: the rows the
server echoed, as a table, or a one-line note. No tabs, no refresh.
-}
chartStatic : ChartBlock -> Html msg
chartStatic chart =
    div (blockIdAttr chart.id ++ [ class "blk-chart blk-anchored" ])
        [ case chart.result of
            Rows rows ->
                resultsTable rows

            Blocks.Failed message ->
                div [ class "chart-error" ] [ text message ]

            _ ->
                div [ class "chart-placeholder" ]
                    [ span [ class "chart-idle-note" ] [ text "chart — open the doc to run it" ] ]
        ]


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
