module Ui.StoryCard exposing (Card, pinIcon, view)

{-| The compact "story" card: title, summary, up to three tag chips.
The home page's pinned shelf is made of these, and a grouped docs
list uses the same card for its pinned "no <scope>" shelf, so the
two surfaces read as one idea.
-}

import Html exposing (Html, a, div, span, text)
import Html.Attributes exposing (class, href)
import Route
import Svg
import Svg.Attributes as SA


type alias Card =
    { slug : String
    , title : String
    , summary : Maybe String
    , tags : List String
    }


view : String -> Card -> Html msg
view wsSlug d =
    a [ href (Route.href (Route.DocShow wsSlug d.slug)), class "story-card" ]
        (List.filterMap identity
            [ Just
                (div [ class "story-card-top" ]
                    [ span [ class "story-card-title" ] [ text d.title ] ]
                )
            , Maybe.map
                (\s -> div [ class "story-card-summary" ] [ text s ])
                d.summary
            , if List.isEmpty d.tags then
                Nothing

              else
                Just
                    (div [ class "story-card-tags" ]
                        (List.map
                            (\t -> span [ class "story-card-tag" ] [ text t ])
                            (List.take 3 d.tags)
                        )
                    )
            ]
        )


{-| Lucide pin, the shelf-head glyph for pinned things.
-}
pinIcon : Html msg
pinIcon =
    Svg.svg
        [ SA.viewBox "0 0 24 24"
        , SA.fill "none"
        , SA.stroke "currentColor"
        , SA.strokeWidth "2"
        , SA.strokeLinecap "round"
        , SA.strokeLinejoin "round"
        ]
        [ Svg.path [ SA.d "M12 17v5" ] []
        , Svg.path [ SA.d "M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 0 1 1 1z" ] []
        ]
