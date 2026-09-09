module Auth.Ui exposing
    ( brand
    , copyHint
    , errorLine
    , tokenField
    )

{-| Shared auth-card fragments used by the signup / login / invite pages.
Markup mirrors the LiveViews byte-for-byte (same classes, ids, inline
styles); behavior that lived in JS hooks (CopyToken / TrackCopy) is
driven from Elm state plus the `[data-copy-target]` click delegation in
`assets/js/fe-auth.js`.

Owned by the fe-auth page agent.

-}

import Html exposing (Html, button, div, input, span, text)
import Html.Attributes exposing (attribute, class, id, readonly, style, title, type_, value)
import Html.Events exposing (on, onClick)
import Json.Decode as Decode
import Svg
import Svg.Attributes as SvgA


{-| The `A · aveline` brand header at the top of every auth card.
-}
brand : Html msg
brand =
    div [ class "auth-brand auth-brand-hero" ]
        [ span [ class "nav-brand-mark", style "width" "36px", style "height" "36px" ] [ text "A" ]
        , span [ class "auth-brand-name", style "font-size" "26px" ] [ text "aveline" ]
        ]


{-| The readonly API-key preview with its copy button. `onCopy` fires on
the button click (the actual clipboard write happens in fe-auth.js via
`data-copy-target`); `onNativeCopy` fires when the user copies straight
from the input (Ctrl/Cmd+C), matching the TrackCopy hook.
-}
tokenField :
    { token : String
    , copied : Bool
    , onCopy : msg
    , onNativeCopy : msg
    }
    -> Html msg
tokenField config =
    div [ class "token-field" ]
        [ input
            [ type_ "text"
            , id "preview-token-value"
            , class "token-field-input"
            , value config.token
            , readonly True
            , on "copy" (Decode.succeed config.onNativeCopy)
            ]
            []
        , button
            [ type_ "button"
            , id "preview-copy-btn"
            , class
                (if config.copied then
                    "token-field-copy copied"

                 else
                    "token-field-copy"
                )
            , attribute "data-copy-target" "#preview-token-value"
            , title "Copy"
            , onClick config.onCopy
            ]
            [ Svg.svg
                [ SvgA.viewBox "0 0 24 24"
                , SvgA.fill "none"
                , SvgA.stroke "currentColor"
                , SvgA.strokeWidth "1.7"
                , SvgA.strokeLinecap "round"
                , SvgA.strokeLinejoin "round"
                ]
                [ Svg.rect [ SvgA.x "9", SvgA.y "9", SvgA.width "12", SvgA.height "12", SvgA.rx "2" ] []
                , Svg.path [ SvgA.d "M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" ] []
                ]
            , span [ class "token-field-copy-label" ]
                [ text
                    (if config.copied then
                        "Copied ✓"

                     else
                        "Copy"
                    )
                ]
            ]
        ]


{-| The "Copy this now" line under the token field.
-}
copyHint : Html msg
copyHint =
    div [ class "auth-hint" ]
        [ text "Copy this now. You will not be able to see it again." ]


{-| The centered error line the signup / invite forms show under the
submit button. Renders nothing when there is no error (the LiveViews
omit the node entirely).
-}
errorLine : Maybe String -> Html msg
errorLine maybeError =
    case maybeError of
        Nothing ->
            text ""

        Just err ->
            div [ class "auth-error", style "margin-top" "14px", style "text-align" "center" ]
                [ text err ]
