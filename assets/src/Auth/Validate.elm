module Auth.Validate exposing
    ( Context(..)
    , checkUsername
    , deriveSlug
    , normalizeUsername
    )

{-| Pure ports of the server-side validation helpers the auth LiveViews
run on every change/submit:

  - `checkUsername` — SignupLive.check\_username / InviteLive.check\_username
    (identical rules, differently worded messages). The "Username taken."
    check needs the DB, so it stays server-side.
  - `deriveSlug` — Aveline.Slug.derive (lowercase, collapse runs of
    non-alphanumerics to `-`, trim `-`, max 60 chars).

Owned by the fe-auth page agent.

-}


type Context
    = SignupContext
    | InviteContext


normalizeUsername : String -> String
normalizeUsername =
    String.trim >> String.toLower


{-| Format-level username errors, with the exact copy of the LiveView the
context names. Empty input is not an error (the submit button gates it).
`Nothing` means "fine as far as the client can tell" — the server still
owns the "Username taken." check.
-}
checkUsername : Context -> String -> Maybe String
checkUsername context raw =
    let
        username =
            normalizeUsername raw
    in
    if username == "" then
        Nothing

    else if String.length username < 2 then
        Just <|
            case context of
                SignupContext ->
                    "Username too short (min 2)."

                InviteContext ->
                    "Too short (minimum 2 characters)."

    else if String.length username > 60 then
        Just <|
            case context of
                SignupContext ->
                    "Username too long (max 60)."

                InviteContext ->
                    "Too long (max 60 characters)."

    else if not (validFormat username) then
        Just <|
            case context of
                SignupContext ->
                    "Lowercase letters, digits, and hyphens only."

                InviteContext ->
                    "Use lowercase letters, digits, and hyphens. Must start with a letter or digit."

    else
        Nothing


{-| `^[a-z0-9][a-z0-9-]*$` without elm/regex.
-}
validFormat : String -> Bool
validFormat s =
    case String.uncons s of
        Nothing ->
            False

        Just ( first, rest ) ->
            isLowerAlnum first
                && String.all (\c -> isLowerAlnum c || c == '-') rest


isLowerAlnum : Char -> Bool
isLowerAlnum c =
    (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')


{-| Aveline.Slug.derive: Nothing when no letter or digit survives.
-}
deriveSlug : String -> Maybe String
deriveSlug text =
    let
        derived =
            text
                |> String.toLower
                |> String.toList
                |> List.map
                    (\c ->
                        if isLowerAlnum c then
                            c

                        else
                            '-'
                    )
                |> collapseDashes
                |> trimDashes
                |> List.take 60
                |> trimDashes
                |> String.fromList
    in
    if derived == "" then
        Nothing

    else
        Just derived


collapseDashes : List Char -> List Char
collapseDashes chars =
    List.foldr
        (\c acc ->
            case acc of
                next :: _ ->
                    if c == '-' && next == '-' then
                        acc

                    else
                        c :: acc

                [] ->
                    [ c ]
        )
        []
        chars


trimDashes : List Char -> List Char
trimDashes chars =
    chars
        |> dropWhileDash
        |> List.reverse
        |> dropWhileDash
        |> List.reverse


dropWhileDash : List Char -> List Char
dropWhileDash chars =
    case chars of
        '-' :: rest ->
            dropWhileDash rest

        _ ->
            chars
