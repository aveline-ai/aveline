module Ui.Workspace.Format exposing (avatarHue, formatNumber, hash, initial)

{-| Small formatting helpers for the workspace pages, ported from
`AvelineWeb.UIHelpers`.

`avatarHue` (and other hash-derived values) use a simple deterministic
string hash instead of Erlang's `phash2`, so hues are stable across the
SPA but differ from what the server-rendered pages picked.

-}


{-| Compact number formatter: "999", "1,234", "12k", "12.3k", "3M".
Mirrors `UIHelpers.format_number/1` branch for branch.
-}
formatNumber : Int -> String
formatNumber n =
    if n < 1000 then
        String.fromInt n

    else if n < 10000 then
        comma n

    else if n < 1000000 then
        let
            r =
                modBy 1000 n
        in
        if r < 100 then
            String.fromInt (n // 1000) ++ "k"

        else
            String.fromInt (n // 1000) ++ "." ++ String.fromInt (r // 100) ++ "k"

    else
        String.fromInt (n // 1000000) ++ "M"


comma : Int -> String
comma n =
    let
        s =
            String.fromInt n

        len =
            String.length s
    in
    if len > 3 then
        comma (n // 1000) ++ "," ++ String.right 3 s

    else
        s


{-| First character of a username, uppercased — for avatar circles.
-}
initial : String -> String
initial username =
    case String.uncons username of
        Nothing ->
            "?"

        Just ( c, _ ) ->
            String.toUpper (String.fromChar c)


{-| Deterministic accent hue (0-359) for a user, stable by username.
-}
avatarHue : String -> Int
avatarHue username =
    if username == "" then
        240

    else
        modBy 360 (hash username)


{-| Deterministic non-negative string hash (a stand-in for
`:erlang.phash2`) shared by avatar hues and the welcome backdrop.
-}
hash : String -> Int
hash s =
    String.foldl (\c h -> modBy 100000007 (h * 31 + Char.toCode c)) 7 s
