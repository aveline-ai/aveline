module UiWorkspaceHelpersTest exposing (suite)

{-| Tests for the workspace pages' formatting helpers, pinned to the
behaviour of `AvelineWeb.UIHelpers` (relative\_time, absolute\_time,
format\_number, initial).
-}

import Expect
import Test exposing (Test, describe, test)
import Time
import Ui.Workspace.Format as Format
import Ui.Workspace.Time as WsTime


{-| 2026-03-12T15:42:00Z (a Thursday).
-}
now : Time.Posix
now =
    Time.millisToPosix 1773330120000


ago : Int -> Time.Posix
ago seconds =
    Time.millisToPosix (Time.posixToMillis now - seconds * 1000)


suite : Test
suite =
    describe "Ui.Workspace helpers"
        [ describe "relativeTime"
            [ test "under a minute is just now" <|
                \_ -> WsTime.relativeTime now (ago 30) |> Expect.equal "just now"
            , test "under an hour is minutes" <|
                \_ -> WsTime.relativeTime now (ago 300) |> Expect.equal "5m ago"
            , test "same calendar day is hours" <|
                \_ -> WsTime.relativeTime now (ago (2 * 3600)) |> Expect.equal "2h ago"
            , test "previous calendar day is Yesterday" <|
                \_ -> WsTime.relativeTime now (ago (24 * 3600)) |> Expect.equal "Yesterday"
            , test "2-6 days back is the weekday name" <|
                \_ -> WsTime.relativeTime now (ago (3 * 24 * 3600)) |> Expect.equal "Monday"
            , test "same year is a short date" <|
                \_ -> WsTime.relativeTime now (ago (40 * 24 * 3600)) |> Expect.equal "Jan 31"
            , test "older years carry the year" <|
                \_ -> WsTime.relativeTime now (ago (400 * 24 * 3600)) |> Expect.equal "Feb 5, 2025"
            ]
        , describe "absoluteTime"
            [ test "formats the full timestamp in UTC" <|
                \_ ->
                    WsTime.absoluteTime now
                        |> Expect.equal "Mar 12, 2026 at 3:42 PM UTC"
            , test "midnight renders as 12 AM" <|
                \_ ->
                    WsTime.absoluteTime (Time.millisToPosix 1773273600000)
                        |> Expect.equal "Mar 12, 2026 at 12:00 AM UTC"
            ]
        , describe "formatNumber"
            [ test "small numbers pass through" <|
                \_ -> Format.formatNumber 999 |> Expect.equal "999"
            , test "thousands get commas" <|
                \_ -> Format.formatNumber 1234 |> Expect.equal "1,234"
            , test "ten thousands get k" <|
                \_ -> Format.formatNumber 12000 |> Expect.equal "12k"
            , test "k keeps one decimal when it matters" <|
                \_ -> Format.formatNumber 12345 |> Expect.equal "12.3k"
            , test "small k remainders are dropped" <|
                \_ -> Format.formatNumber 12045 |> Expect.equal "12k"
            , test "millions get M" <|
                \_ -> Format.formatNumber 3400000 |> Expect.equal "3M"
            ]
        , describe "initial"
            [ test "uppercases the first character" <|
                \_ -> Format.initial "alice" |> Expect.equal "A"
            , test "empty falls back to ?" <|
                \_ -> Format.initial "" |> Expect.equal "?"
            ]
        , describe "avatarHue"
            [ test "is stable and in range" <|
                \_ ->
                    Format.avatarHue "alice"
                        |> Expect.all
                            [ Expect.equal (Format.avatarHue "alice")
                            , Expect.atLeast 0
                            , Expect.lessThan 360
                            ]
            ]
        ]
