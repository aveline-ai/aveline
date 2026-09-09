module UiTimeTest exposing (suite)

{-| Coverage for the Notion-style timestamp port (UIHelpers).
-}

import Expect
import Test exposing (Test, describe, test)
import Time
import Ui.Time


{-| 2026-09-08 12:00:00 UTC (a Tuesday).
-}
now : Time.Posix
now =
    Time.millisToPosix 1788868800000


ago : Int -> Time.Posix
ago seconds =
    Time.millisToPosix (Time.posixToMillis now - seconds * 1000)


suite : Test
suite =
    describe "Ui.Time"
        [ test "under a minute is just now" <|
            \_ -> Expect.equal "just now" (Ui.Time.relativeTime now (ago 30))
        , test "under an hour is minutes ago" <|
            \_ -> Expect.equal "5m ago" (Ui.Time.relativeTime now (ago 300))
        , test "same UTC day is hours ago" <|
            \_ -> Expect.equal "3h ago" (Ui.Time.relativeTime now (ago (3 * 3600)))
        , test "previous calendar day is Yesterday" <|
            \_ -> Expect.equal "Yesterday" (Ui.Time.relativeTime now (ago (24 * 3600)))
        , test "2-6 days back is the weekday name" <|
            \_ ->
                -- Three days before a Tuesday is a Saturday.
                Expect.equal "Saturday" (Ui.Time.relativeTime now (ago (3 * 24 * 3600)))
        , test "earlier this year is month + day" <|
            \_ ->
                Expect.equal "Mar 12"
                    (Ui.Time.relativeTime now (Time.millisToPosix 1773316800000))
        , test "older than this year carries the year" <|
            \_ ->
                Expect.equal "Sep 8, 2025"
                    (Ui.Time.relativeTime now (ago (365 * 24 * 3600)))
        , test "absoluteTime formats the tooltip form" <|
            \_ ->
                -- 2026-09-08 15:42 UTC
                Expect.equal "Sep 8, 2026 at 3:42 PM UTC"
                    (Ui.Time.absoluteTime (Time.millisToPosix 1788882120000))
        ]
