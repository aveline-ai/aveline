module AuthValidateTest exposing (suite)

{-| Tests for Auth.Validate — the client-side ports of
SignupLive/InviteLive.check\_username and Aveline.Slug.derive.
-}

import Auth.Validate as V
import Expect
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Auth.Validate"
        [ describe "deriveSlug (mirrors Aveline.Slug.derive)"
            [ test "lowercases and collapses runs of non-alphanumerics" <|
                \_ ->
                    V.deriveSlug "Aveline  AI!"
                        |> Expect.equal (Just "aveline-ai")
            , test "trims leading and trailing dashes" <|
                \_ ->
                    V.deriveSlug "--Hello World--"
                        |> Expect.equal (Just "hello-world")
            , test "returns Nothing when no letter or digit survives" <|
                \_ ->
                    V.deriveSlug "!!! ???"
                        |> Expect.equal Nothing
            , test "returns Nothing for empty input" <|
                \_ ->
                    V.deriveSlug ""
                        |> Expect.equal Nothing
            , test "keeps digits and existing hyphens" <|
                \_ ->
                    V.deriveSlug "team-42"
                        |> Expect.equal (Just "team-42")
            , test "caps at 60 chars then trims dashes again" <|
                \_ ->
                    V.deriveSlug (String.repeat 59 "a" ++ " b")
                        |> Expect.equal (Just (String.repeat 59 "a"))
            ]
        , describe "checkUsername"
            [ test "empty username is not an error (submit button gates it)" <|
                \_ ->
                    V.checkUsername V.SignupContext ""
                        |> Expect.equal Nothing
            , test "valid username passes" <|
                \_ ->
                    V.checkUsername V.SignupContext "arie-42"
                        |> Expect.equal Nothing
            , test "too short — signup wording" <|
                \_ ->
                    V.checkUsername V.SignupContext "a"
                        |> Expect.equal (Just "Username too short (min 2).")
            , test "too short — invite wording" <|
                \_ ->
                    V.checkUsername V.InviteContext "a"
                        |> Expect.equal (Just "Too short (minimum 2 characters).")
            , test "too long — signup wording" <|
                \_ ->
                    V.checkUsername V.SignupContext (String.repeat 61 "a")
                        |> Expect.equal (Just "Username too long (max 60).")
            , test "too long — invite wording" <|
                \_ ->
                    V.checkUsername V.InviteContext (String.repeat 61 "a")
                        |> Expect.equal (Just "Too long (max 60 characters).")
            , test "bad characters — signup wording" <|
                \_ ->
                    V.checkUsername V.SignupContext "arie_m"
                        |> Expect.equal (Just "Lowercase letters, digits, and hyphens only.")
            , test "leading hyphen — invite wording" <|
                \_ ->
                    V.checkUsername V.InviteContext "-arie"
                        |> Expect.equal
                            (Just "Use lowercase letters, digits, and hyphens. Must start with a letter or digit.")
            , test "input is normalized (trim + downcase) before checking" <|
                \_ ->
                    V.checkUsername V.SignupContext "  ARIE  "
                        |> Expect.equal Nothing
            ]
        , describe "normalizeUsername"
            [ test "trims and downcases" <|
                \_ ->
                    V.normalizeUsername "  ARIE-42 "
                        |> Expect.equal "arie-42"
            ]
        ]
