module Ui.Time exposing (absoluteTime, relativeTime)

{-| Ports of `AvelineWeb.UiHelpers.relative_time/1` and
`absolute_time/1` — same buckets, same strings, UTC throughout.
-}

import Time exposing (Month(..), Posix, Weekday(..))


{-| "just now" / "5m ago" / "3h ago" / "Yesterday" / "Tuesday" /
"Mar 12" / "Mar 12, 2025".
-}
relativeTime : Posix -> Posix -> String
relativeTime now then_ =
    let
        diffSec =
            (Time.posixToMillis now - Time.posixToMillis then_) // 1000

        dayDiff =
            utcDayNumber now - utcDayNumber then_
    in
    if diffSec < 60 then
        "just now"

    else if diffSec < 3600 then
        String.fromInt (diffSec // 60) ++ "m ago"

    else if dayDiff == 0 then
        String.fromInt (diffSec // 3600) ++ "h ago"

    else if dayDiff == 1 then
        "Yesterday"

    else if dayDiff >= 2 && dayDiff <= 6 then
        weekdayName (Time.toWeekday Time.utc then_)

    else if Time.toYear Time.utc now == Time.toYear Time.utc then_ then
        monthDay then_

    else
        monthDay then_ ++ ", " ++ String.fromInt (Time.toYear Time.utc then_)


{-| "Mar 12, 2026 at 3:42 PM UTC" — the tooltip timestamp.
-}
absoluteTime : Posix -> String
absoluteTime t =
    let
        hour24 =
            Time.toHour Time.utc t

        ( hour12, meridiem ) =
            if hour24 == 0 then
                ( 12, "AM" )

            else if hour24 < 12 then
                ( hour24, "AM" )

            else if hour24 == 12 then
                ( 12, "PM" )

            else
                ( hour24 - 12, "PM" )

        minutes =
            String.padLeft 2 '0' (String.fromInt (Time.toMinute Time.utc t))
    in
    monthDay t
        ++ ", "
        ++ String.fromInt (Time.toYear Time.utc t)
        ++ " at "
        ++ String.fromInt hour12
        ++ ":"
        ++ minutes
        ++ " "
        ++ meridiem
        ++ " UTC"


monthDay : Posix -> String
monthDay t =
    monthName (Time.toMonth Time.utc t) ++ " " ++ String.fromInt (Time.toDay Time.utc t)


utcDayNumber : Posix -> Int
utcDayNumber t =
    -- UTC days align with epoch-millisecond days.
    floor (toFloat (Time.posixToMillis t) / 86400000)


weekdayName : Weekday -> String
weekdayName wd =
    case wd of
        Mon ->
            "Monday"

        Tue ->
            "Tuesday"

        Wed ->
            "Wednesday"

        Thu ->
            "Thursday"

        Fri ->
            "Friday"

        Sat ->
            "Saturday"

        Sun ->
            "Sunday"


monthName : Month -> String
monthName m =
    case m of
        Jan ->
            "Jan"

        Feb ->
            "Feb"

        Mar ->
            "Mar"

        Apr ->
            "Apr"

        May ->
            "May"

        Jun ->
            "Jun"

        Jul ->
            "Jul"

        Aug ->
            "Aug"

        Sep ->
            "Sep"

        Oct ->
            "Oct"

        Nov ->
            "Nov"

        Dec ->
            "Dec"
