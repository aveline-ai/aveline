module TimeFmt exposing
    ( CivilDate
    , absoluteTime
    , civilFromPosix
    , diffDays
    , monthDay
    , monthDayYear
    , parseCivilDate
    , relativeTime
    )

{-| Timestamp presentation, ported from AvelineWeb.UiHelpers
(`relative_time/1`, `absolute_time/1`) plus the calendar-date arithmetic
the Data sources timeline strip needs (`Date.diff` equivalent).
All rendering is UTC, matching the server helpers.
-}

import Time exposing (Month(..), Posix, Weekday(..))


{-| A plain calendar date (what Elixir's `Date` is to `DateTime`).
-}
type alias CivilDate =
    { year : Int
    , month : Int
    , day : Int
    }


civilFromPosix : Posix -> CivilDate
civilFromPosix posix =
    { year = Time.toYear Time.utc posix
    , month = monthNumber (Time.toMonth Time.utc posix)
    , day = Time.toDay Time.utc posix
    }


{-| Parse an ISO calendar date ("2026-07-06").
-}
parseCivilDate : String -> Maybe CivilDate
parseCivilDate raw =
    case String.split "-" raw |> List.map String.toInt of
        [ Just y, Just m, Just d ] ->
            if m >= 1 && m <= 12 && d >= 1 && d <= 31 then
                Just { year = y, month = m, day = d }

            else
                Nothing

        _ ->
            Nothing


{-| Whole days from `from` to `to` — Elixir's `Date.diff(to, from)`.
-}
diffDays : CivilDate -> CivilDate -> Int
diffDays to from =
    rataDie to - rataDie from



-- Howard Hinnant's days-from-civil algorithm, using integer division
-- that truncates toward zero (Elm's // on the shifted year is safe for
-- any date the app will ever see).


rataDie : CivilDate -> Int
rataDie { year, month, day } =
    let
        y =
            if month <= 2 then
                year - 1

            else
                year

        era =
            floorDiv y 400

        yoe =
            y - era * 400

        mp =
            modBy 12 (month + 9)

        doy =
            (153 * mp + 2) // 5 + day - 1

        doe =
            yoe * 365 + yoe // 4 - yoe // 100 + doy
    in
    era * 146097 + doe


floorDiv : Int -> Int -> Int
floorDiv a b =
    if a < 0 && modBy b a /= 0 then
        a // b - 1

    else
        a // b


{-| Compact age, mirroring `UiHelpers.relative_time/1`:
"just now" / "12m ago" / "3h ago" / "Yesterday" / weekday /
"Mar 12" / "Mar 12, 2025".
-}
relativeTime : Posix -> Posix -> String
relativeTime now t =
    let
        diffSec =
            (Time.posixToMillis now - Time.posixToMillis t) // 1000

        dayDiff =
            diffDays (civilFromPosix now) (civilFromPosix t)
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
        weekdayName (Time.toWeekday Time.utc t)

    else if Time.toYear Time.utc t == Time.toYear Time.utc now then
        monthDay (civilFromPosix t)

    else
        monthDayYear (civilFromPosix t)


{-| Long absolute timestamp for tooltips — `UiHelpers.absolute_time/1`:
"Mar 12, 2026 at 3:42 PM UTC".
-}
absoluteTime : Posix -> String
absoluteTime t =
    let
        hour24 =
            Time.toHour Time.utc t

        hour12 =
            case modBy 12 hour24 of
                0 ->
                    12

                h ->
                    h

        meridiem =
            if hour24 < 12 then
                "AM"

            else
                "PM"

        minute =
            String.padLeft 2 '0' (String.fromInt (Time.toMinute Time.utc t))
    in
    monthDayYear (civilFromPosix t)
        ++ " at "
        ++ String.fromInt hour12
        ++ ":"
        ++ minute
        ++ " "
        ++ meridiem
        ++ " UTC"


{-| "Sep 8" — strftime "%b %-d".
-}
monthDay : CivilDate -> String
monthDay date =
    monthShort date.month ++ " " ++ String.fromInt date.day


{-| "Sep 8, 2026" — strftime "%b %-d, %Y".
-}
monthDayYear : CivilDate -> String
monthDayYear date =
    monthDay date ++ ", " ++ String.fromInt date.year


monthShort : Int -> String
monthShort m =
    case m of
        1 ->
            "Jan"

        2 ->
            "Feb"

        3 ->
            "Mar"

        4 ->
            "Apr"

        5 ->
            "May"

        6 ->
            "Jun"

        7 ->
            "Jul"

        8 ->
            "Aug"

        9 ->
            "Sep"

        10 ->
            "Oct"

        11 ->
            "Nov"

        _ ->
            "Dec"


monthNumber : Month -> Int
monthNumber month =
    case month of
        Jan ->
            1

        Feb ->
            2

        Mar ->
            3

        Apr ->
            4

        May ->
            5

        Jun ->
            6

        Jul ->
            7

        Aug ->
            8

        Sep ->
            9

        Oct ->
            10

        Nov ->
            11

        Dec ->
            12


weekdayName : Weekday -> String
weekdayName weekday =
    case weekday of
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
