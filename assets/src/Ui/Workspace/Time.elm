module Ui.Workspace.Time exposing (absoluteTime, relativeTime)

{-| Timestamp formatting for the workspace pages, ported from
`AvelineWeb.UIHelpers` (relative\_time/1 and absolute\_time/1) so the
Elm pages render the exact same strings the LiveViews did.

All calendar boundaries use UTC, same as the server.

-}

import Time exposing (Month(..), Posix, Weekday(..))


{-| Notion-style relative timestamp. First argument is "now", second is
the moment being described.

    0-59 sec ago       -> "just now"
    < 1 hour           -> "5m ago"
    same calendar day  -> "2h ago"
    previous cal. day  -> "Yesterday"
    2-6 cal. days back -> "Tuesday"
    this year          -> "Mar 12"
    older              -> "Mar 12, 2026"

-}
relativeTime : Posix -> Posix -> String
relativeTime now dt =
    let
        diffSec =
            (Time.posixToMillis now - Time.posixToMillis dt) // 1000

        dayDiff =
            epochDay now - epochDay dt
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
        weekdayName (Time.toWeekday Time.utc dt)

    else if Time.toYear Time.utc dt == Time.toYear Time.utc now then
        monthDay dt

    else
        monthDay dt ++ ", " ++ String.fromInt (Time.toYear Time.utc dt)


{-| Long absolute timestamp for tooltips: "Mar 12, 2026 at 3:42 PM UTC".
-}
absoluteTime : Posix -> String
absoluteTime dt =
    let
        hour24 =
            Time.toHour Time.utc dt

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
    in
    monthDay dt
        ++ ", "
        ++ String.fromInt (Time.toYear Time.utc dt)
        ++ " at "
        ++ String.fromInt hour12
        ++ ":"
        ++ String.padLeft 2 '0' (String.fromInt (Time.toMinute Time.utc dt))
        ++ " "
        ++ meridiem
        ++ " UTC"


epochDay : Posix -> Int
epochDay t =
    floor (toFloat (Time.posixToMillis t) / 86400000)


monthDay : Posix -> String
monthDay dt =
    monthName (Time.toMonth Time.utc dt) ++ " " ++ String.fromInt (Time.toDay Time.utc dt)


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
