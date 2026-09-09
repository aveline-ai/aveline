module TimeFmtTest exposing (suite)

{-| Coverage for the ported UiHelpers time formatting.
-}

import Expect
import Test exposing (Test, describe, test)
import Time
import TimeFmt


{-| 2026-09-08T12:00:00Z
-}
noon : Time.Posix
noon =
    Time.millisToPosix 1788868800000


minutesEarlier : Int -> Time.Posix
minutesEarlier m =
    Time.millisToPosix (Time.posixToMillis noon - m * 60000)


suite : Test
suite =
    describe "TimeFmt"
        [ describe "diffDays"
            [ test "same date" <|
                \_ ->
                    TimeFmt.diffDays { year = 2026, month = 9, day = 8 } { year = 2026, month = 9, day = 8 }
                        |> Expect.equal 0
            , test "across a leap February" <|
                \_ ->
                    TimeFmt.diffDays { year = 2024, month = 3, day = 1 } { year = 2024, month = 2, day = 1 }
                        |> Expect.equal 29
            , test "across a year boundary" <|
                \_ ->
                    TimeFmt.diffDays { year = 2026, month = 1, day = 1 } { year = 2025, month = 12, day = 31 }
                        |> Expect.equal 1
            ]
        , describe "relativeTime"
            [ test "just now" <|
                \_ -> TimeFmt.relativeTime noon (minutesEarlier 0) |> Expect.equal "just now"
            , test "minutes ago" <|
                \_ -> TimeFmt.relativeTime noon (minutesEarlier 12) |> Expect.equal "12m ago"
            , test "hours ago, same day" <|
                \_ -> TimeFmt.relativeTime noon (minutesEarlier 180) |> Expect.equal "3h ago"
            , test "yesterday" <|
                \_ ->
                    TimeFmt.relativeTime noon (minutesEarlier (26 * 60)) |> Expect.equal "Yesterday"
            , test "weekday inside the last week" <|
                \_ ->
                    -- 2026-09-08 is a Tuesday; three days back is Saturday.
                    TimeFmt.relativeTime noon (minutesEarlier (3 * 24 * 60)) |> Expect.equal "Saturday"
            , test "same year gives month + day" <|
                \_ ->
                    TimeFmt.relativeTime noon (minutesEarlier (60 * 24 * 60)) |> Expect.equal "Jul 10"
            , test "earlier years include the year" <|
                \_ ->
                    TimeFmt.relativeTime noon (minutesEarlier (400 * 24 * 60)) |> Expect.equal "Aug 4, 2025"
            ]
        , describe "absoluteTime"
            [ test "PM with 12-hour clock and UTC suffix" <|
                \_ ->
                    TimeFmt.absoluteTime (minutesEarlier -222)
                        |> Expect.equal "Sep 8, 2026 at 3:42 PM UTC"
            , test "midnight is 12 AM" <|
                \_ ->
                    TimeFmt.absoluteTime (minutesEarlier 715)
                        |> Expect.equal "Sep 8, 2026 at 12:05 AM UTC"
            ]
        , test "parseCivilDate accepts ISO dates and rejects junk" <|
            \_ ->
                ( TimeFmt.parseCivilDate "2026-07-06", TimeFmt.parseCivilDate "07/06/2026" )
                    |> Expect.equal ( Just { year = 2026, month = 7, day = 6 }, Nothing )
        ]
