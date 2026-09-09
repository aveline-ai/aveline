module Ui.AuthBg exposing (split)

{-| Split-screen background frame for auth pages (signup / login /
invite). Port of `AvelineWeb.AuthBg.split/1` — same DOM, same ids and
classes. The canvas animations come from the fe-auth block in
`assets/js/fe-auth.js` (a MutationObserver boots the same OrganicCanvas /
MatrixCanvas animations app.js runs as LiveView hooks).

Owned by the fe-auth page agent.

-}

import Html exposing (Html, canvas, div)
import Html.Attributes exposing (attribute, class, id)


{-| The two background panes. Render them as the first children of the
`.auth-shell` element, before the `.auth-card`.
-}
split : List (Html msg)
split =
    [ div [ class "auth-pane auth-pane-human", attribute "aria-hidden" "true" ]
        [ canvas [ class "canvas-organic", id "auth-canvas-organic" ] [] ]
    , div [ class "auth-pane auth-pane-agent", attribute "aria-hidden" "true" ]
        [ canvas [ class "canvas-matrix", id "auth-canvas-matrix" ] [] ]
    ]
