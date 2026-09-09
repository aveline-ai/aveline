module Ui.Icons exposing
    ( actor
    , chevronDown
    , commentBubble
    , kudosTrophy
    , linkChain
    , lock
    , mention
    , trash
    )

{-| Inline SVG icons, byte-for-byte ports of the ones the LiveView
renders (`AvelineWeb.Icons` + the paths inlined in `doc_show_live.ex`).
-}

import Svg exposing (Svg, circle, path, polyline, rect, svg)
import Svg.Attributes as SA


strokeIcon : String -> String -> List (Svg msg) -> Svg msg
strokeIcon class strokeWidth children =
    svg
        [ SA.class class
        , SA.viewBox "0 0 24 24"
        , SA.fill "none"
        , SA.stroke "currentColor"
        , SA.strokeWidth strokeWidth
        , SA.strokeLinecap "round"
        , SA.strokeLinejoin "round"
        ]
        children


{-| Actor icon: Lucide user for humans, Lucide bot for agents; nothing
for unknown types (matches `AvelineWeb.Icons.actor/1`).
-}
actor : String -> String -> Maybe String -> Svg msg
actor actorType class title =
    let
        titled children =
            case title of
                Just t ->
                    Svg.title [] [ Svg.text t ] :: children

                Nothing ->
                    children
    in
    case actorType of
        "human" ->
            strokeIcon class
                "2"
                (titled
                    [ path [ SA.d "M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" ] []
                    , circle [ SA.cx "12", SA.cy "7", SA.r "4" ] []
                    ]
                )

        "agent" ->
            strokeIcon class
                "2"
                (titled
                    [ path [ SA.d "M12 8V4H8" ] []
                    , rect [ SA.width "16", SA.height "12", SA.x "4", SA.y "8", SA.rx "2" ] []
                    , path [ SA.d "M2 14h2" ] []
                    , path [ SA.d "M20 14h2" ] []
                    , path [ SA.d "M15 13v2" ] []
                    , path [ SA.d "M9 13v2" ] []
                    ]
                )

        _ ->
            Svg.text ""


{-| The block-anchor chain-link glyph.
-}
linkChain : Svg msg
linkChain =
    strokeIcon ""
        "2"
        [ path [ SA.d "M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71" ] []
        , path [ SA.d "M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71" ] []
        ]


{-| The block-comment speech bubble.
-}
commentBubble : Svg msg
commentBubble =
    strokeIcon ""
        "2"
        [ path [ SA.d "M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" ] [] ]


{-| Private-doc padlock (title carries the explainer).
-}
lock : String -> String -> Svg msg
lock class title =
    strokeIcon class
        "2"
        [ Svg.title [] [ Svg.text title ]
        , rect [ SA.x "3", SA.y "11", SA.width "18", SA.height "11", SA.rx "2", SA.ry "2" ] []
        , path [ SA.d "M7 11V7a5 5 0 0 1 10 0v4" ] []
        ]


{-| Kudos trophy (stroke-width 1.8, as in the LV).
-}
kudosTrophy : Svg msg
kudosTrophy =
    strokeIcon ""
        "1.8"
        [ path [ SA.d "M6 9H4.5a2.5 2.5 0 0 1 0-5H6" ] []
        , path [ SA.d "M18 9h1.5a2.5 2.5 0 0 0 0-5H18" ] []
        , path [ SA.d "M4 22h16" ] []
        , path [ SA.d "M10 14.66V17c0 .55-.47.98-.97 1.21C7.85 18.75 7 20.24 7 22" ] []
        , path [ SA.d "M14 14.66V17c0 .55.47.98.97 1.21C16.15 18.75 17 20.24 17 22" ] []
        , path [ SA.d "M18 2H6v7a6 6 0 0 0 12 0V2z" ] []
        ]


{-| The version-switcher chevron.
-}
chevronDown : String -> Svg msg
chevronDown class =
    strokeIcon class "2" [ polyline [ SA.points "6 9 12 15 18 9" ] [] ]


{-| Deleted-comment trash can.
-}
trash : Svg msg
trash =
    strokeIcon ""
        "2"
        [ polyline [ SA.points "3 6 5 6 21 6" ] []
        , path [ SA.d "M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6" ] []
        ]


{-| Inline doc-mention document glyph.
-}
mention : Svg msg
mention =
    strokeIcon "mention-icon"
        "2"
        [ path [ SA.d "M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" ] []
        , polyline [ SA.points "14 2 14 8 20 8" ] []
        ]
