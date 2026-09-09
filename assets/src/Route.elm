module Route exposing (Route(..), fromUrl, href, workspaceSlug)

{-| Client-side routes, mirroring the server's browser routes exactly.
STABLE shared surface — page agents must not edit this file.
-}

import Url exposing (Url)
import Url.Parser as Parser exposing ((</>), Parser, map, oneOf, s, string, top)


type Route
    = Signup
    | Login
    | Invite String
    | WorkspaceNew
    | Home String
    | Welcome String
    | Docs String
    | DocsView String String
    | DocShow String String
    | DocShowVersion String String String
    | Activity String
    | DataSources String
    | Team String
    | Settings String


parser : Parser (Route -> a) a
parser =
    oneOf
        [ map Signup top
        , map Signup (s "signup")
        , map Login (s "login")
        , map Invite (s "invite" </> string)
        , map WorkspaceNew (s "new-workspace")
        , map Home (s "w" </> string)
        , map Welcome (s "w" </> string </> s "welcome")
        , map Docs (s "w" </> string </> s "docs")
        , map DocsView (s "w" </> string </> s "v" </> string)
        , map DocShow (s "w" </> string </> s "d" </> string)
        , map DocShowVersion (s "w" </> string </> s "d" </> string </> s "v" </> string)
        , map Activity (s "w" </> string </> s "activity")
        , map DataSources (s "w" </> string </> s "data-sources")
        , map Team (s "w" </> string </> s "team")
        , map Settings (s "w" </> string </> s "settings")
        ]


fromUrl : Url -> Maybe Route
fromUrl =
    Parser.parse parser


{-| The workspace slug a route is scoped to — `Just` for in-app pages
that render inside the shared chrome, `Nothing` for bare auth routes.
-}
workspaceSlug : Route -> Maybe String
workspaceSlug route =
    case route of
        Signup ->
            Nothing

        Login ->
            Nothing

        Invite _ ->
            Nothing

        WorkspaceNew ->
            Nothing

        Home slug ->
            Just slug

        Welcome slug ->
            Just slug

        Docs slug ->
            Just slug

        DocsView slug _ ->
            Just slug

        DocShow slug _ ->
            Just slug

        DocShowVersion slug _ _ ->
            Just slug

        Activity slug ->
            Just slug

        DataSources slug ->
            Just slug

        Team slug ->
            Just slug

        Settings slug ->
            Just slug


href : Route -> String
href route =
    case route of
        Signup ->
            "/signup"

        Login ->
            "/login"

        Invite code ->
            "/invite/" ++ code

        WorkspaceNew ->
            "/new-workspace"

        Home slug ->
            "/w/" ++ slug

        Welcome slug ->
            "/w/" ++ slug ++ "/welcome"

        Docs slug ->
            "/w/" ++ slug ++ "/docs"

        DocsView slug name ->
            "/w/" ++ slug ++ "/v/" ++ name

        DocShow slug docSlug ->
            "/w/" ++ slug ++ "/d/" ++ docSlug

        DocShowVersion slug docSlug version ->
            "/w/" ++ slug ++ "/d/" ++ docSlug ++ "/v/" ++ version

        Activity slug ->
            "/w/" ++ slug ++ "/activity"

        DataSources slug ->
            "/w/" ++ slug ++ "/data-sources"

        Team slug ->
            "/w/" ++ slug ++ "/team"

        Settings slug ->
            "/w/" ++ slug ++ "/settings"
