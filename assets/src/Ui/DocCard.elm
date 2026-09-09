module Ui.DocCard exposing (view)

{-| The doc card — port of the LV's doc\_card component plus the
`<.tag>` / `<.author>` badges (AvelineWeb.Badges) it composes.
-}

import Api.Docs exposing (DocSummary)
import Dict exposing (Dict)
import Html exposing (Html, a, div, span, text)
import Html.Attributes exposing (attribute, class, href, title)
import Route
import Svg
import Svg.Attributes as SA
import Time
import Ui.Time


type alias Config =
    { wsSlug : String
    , now : Maybe Time.Posix
    , tagColors : Dict String String
    }


view : Config -> DocSummary -> Html msg
view config doc =
    a
        [ href (Route.href (Route.DocShow config.wsSlug doc.slug))
        , class "card"
        ]
        [ div [ class "card-title" ]
            ((if doc.visibility == "private" then
                [ lockSvg ]

              else
                []
             )
                ++ [ text doc.title ]
            )
        , case doc.summary of
            Just summary ->
                div [ class "card-summary" ] [ text summary ]

            Nothing ->
                text ""
        , div [ class "card-meta" ]
            (List.concat
                [ case doc.actorUser of
                    Just u ->
                        [ authorChip u.username
                        , span [ class "card-meta-dot" ] [ text "·" ]
                        ]

                    Nothing ->
                        []
                , [ span
                        [ class "card-date"
                        , title ("Last edited " ++ maybeTime Ui.Time.absoluteTime doc.updatedAt)
                        ]
                        [ editSvg
                        , span []
                            [ text
                                (case ( config.now, doc.updatedAt ) of
                                    ( Just now, Just at ) ->
                                        Ui.Time.relativeTime now at

                                    _ ->
                                        ""
                                )
                            ]
                        ]
                  , span [ class "card-meta-dot" ] [ text "·" ]
                  , stat (String.fromInt doc.viewCount ++ " views") eyeSvg doc.viewCount
                  , stat (String.fromInt doc.kudosCount ++ " kudos") kudosSvg doc.kudosCount
                  ]
                , if doc.tags /= [] then
                    [ span [ class "card-meta-dot" ] [ text "·" ]
                    , span [ attribute "style" "display:flex;gap:4px;flex-wrap:wrap" ]
                        (List.map (tagChip config.tagColors) doc.tags)
                    ]

                  else
                    []
                ]
            )
        ]


maybeTime : (Time.Posix -> String) -> Maybe Time.Posix -> String
maybeTime fmt maybeAt =
    maybeAt |> Maybe.map fmt |> Maybe.withDefault ""


stat : String -> Html msg -> Int -> Html msg
stat tooltip icon count =
    span [ class "card-stat", title tooltip ]
        [ icon
        , span [] [ text (String.fromInt count) ]
        ]


authorChip : String -> Html msg
authorChip username =
    span [ class "chip chip-author" ]
        [ span [ class "chip-text" ] [ text username ] ]


tagChip : Dict String String -> String -> Html msg
tagChip colors tag =
    let
        styleAttrs =
            case Dict.get tag colors of
                Just c ->
                    -- Rebind the chip's CSS variables (hex+alpha for
                    -- dim/border), same as Badges.tag.
                    [ attribute "style"
                        ("--tag: " ++ c ++ "; --tag-dim: " ++ c ++ "14; --tag-border: " ++ c ++ "40")
                    ]

                Nothing ->
                    []
    in
    span (class "chip chip-tag" :: styleAttrs)
        [ span [ class "chip-text" ] [ text tag ] ]



-- ===== Icons =====


lockSvg : Html msg
lockSvg =
    Svg.svg
        [ SA.class "doc-lock"
        , SA.viewBox "0 0 24 24"
        , SA.fill "none"
        , SA.stroke "currentColor"
        , SA.strokeWidth "2"
        , SA.strokeLinecap "round"
        , SA.strokeLinejoin "round"
        ]
        [ Svg.title [] [ Svg.text "Private doc" ]
        , Svg.rect [ SA.x "3", SA.y "11", SA.width "18", SA.height "11", SA.rx "2", SA.ry "2" ] []
        , Svg.path [ SA.d "M7 11V7a5 5 0 0 1 10 0v4" ] []
        ]


editSvg : Html msg
editSvg =
    Svg.svg
        [ SA.viewBox "0 0 24 24"
        , SA.fill "none"
        , SA.stroke "currentColor"
        , SA.strokeWidth "1.8"
        , SA.strokeLinecap "round"
        , SA.strokeLinejoin "round"
        ]
        [ Svg.path [ SA.d "M12 20h9" ] []
        , Svg.path [ SA.d "M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z" ] []
        ]


eyeSvg : Html msg
eyeSvg =
    Svg.svg
        [ SA.viewBox "0 0 24 24"
        , SA.fill "none"
        , SA.stroke "currentColor"
        , SA.strokeWidth "1.8"
        , SA.strokeLinecap "round"
        , SA.strokeLinejoin "round"
        ]
        [ Svg.path [ SA.d "M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z" ] []
        , Svg.circle [ SA.cx "12", SA.cy "12", SA.r "3" ] []
        ]


kudosSvg : Html msg
kudosSvg =
    Svg.svg
        [ SA.viewBox "0 0 24 24"
        , SA.fill "none"
        , SA.stroke "currentColor"
        , SA.strokeWidth "1.8"
        , SA.strokeLinecap "round"
        , SA.strokeLinejoin "round"
        ]
        [ Svg.path [ SA.d "M6 9H4.5a2.5 2.5 0 0 1 0-5H6" ] []
        , Svg.path [ SA.d "M18 9h1.5a2.5 2.5 0 0 0 0-5H18" ] []
        , Svg.path [ SA.d "M4 22h16" ] []
        , Svg.path [ SA.d "M10 14.66V17c0 .55-.47.98-.97 1.21C7.85 18.75 7 20.24 7 22" ] []
        , Svg.path [ SA.d "M14 14.66V17c0 .55.47.98.97 1.21C16.15 18.75 17 20.24 17 22" ] []
        , Svg.path [ SA.d "M18 2H6v7a6 6 0 0 0 12 0V2z" ] []
        ]
