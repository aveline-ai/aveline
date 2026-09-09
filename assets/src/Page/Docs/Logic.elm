module Page.Docs.Logic exposing
    ( Knobs
    , Section
    , Sort(..)
    , SubSection
    , defaultKnobs
    , groupedSections
    , groupedTags
    , isModified
    , normalizeWithin
    , parseGroup
    , parseSort
    , scopeMembers
    , scopeOf
    , seedKnobs
    , sortLabel
    , sortToParam
    , valueOf
    , viewSections
    , workspaceScopes
    )

{-| Pure logic ported from WorkspaceShowLive: tag scope grammar
("scope:value"), grouped (kanban) section building, saved-view knob
seeding + the "modified" indicator, and the edited-within grammar.
-}

import Api.Docs exposing (Bucket, ViewConfig, ViewDef)


{-| The page's display knobs — what the LV kept in the URL.
-}
type alias Knobs =
    { tags : List String
    , authors : List String
    , groupBy : Maybe String
    , subGroupBy : Maybe String
    , edited : Maybe String
    , sort : Sort
    , search : String
    }


type Sort
    = Recent
    | Kudos
    | Views


defaultKnobs : Knobs
defaultKnobs =
    { tags = []
    , authors = []
    , groupBy = Nothing
    , subGroupBy = Nothing
    , edited = Nothing
    , sort = Recent
    , search = ""
    }



-- ===== Tag scope grammar =====


{-| The scope of a scoped tag — Just "status" for "status:todo",
Nothing for plain tags. Mirrors Tags.scope\_of.
-}
scopeOf : String -> Maybe String
scopeOf slug =
    case String.indexes ":" slug of
        [] ->
            Nothing

        i :: _ ->
            Just (String.left i slug)


{-| The value of a scoped tag — "todo" for "status:todo"; the slug
itself for plain tags. Mirrors Tags.value\_of.
-}
valueOf : String -> String
valueOf slug =
    case String.indexes ":" slug of
        [] ->
            slug

        i :: _ ->
            String.dropLeft (i + 1) slug


{-| Plain tags first, then one (scope, members) section per scope,
sections sorted by scope name; members keep registry order. Mirrors
grouped\_tags/1.
-}
groupedTags : List String -> ( List String, List ( String, List String ) )
groupedTags tags =
    let
        plain =
            List.filter (\t -> scopeOf t == Nothing) tags

        scopes =
            workspaceScopes tags |> List.sort
    in
    ( plain
    , List.map (\scope -> ( scope, scopeMembers tags scope )) scopes
    )


{-| Scopes (with members) present in the workspace tags, in order of
first appearance, deduplicated. Mirrors workspace\_scopes/1.
-}
workspaceScopes : List String -> List String
workspaceScopes tags =
    tags
        |> List.filterMap scopeOf
        |> uniq


{-| Members of a scope in registry order — mirrors
Tags.list\_scope\_members (the full tag list is already in registry
order, so filtering preserves it).
-}
scopeMembers : List String -> String -> List String
scopeMembers tags scope =
    List.filter (\t -> String.startsWith (scope ++ ":") t) tags


{-| A group value is a tag scope with members; anything else means
ungrouped. Mirrors parse\_group/2.
-}
parseGroup : List String -> Maybe String -> Maybe String
parseGroup tags maybeScope =
    case maybeScope of
        Nothing ->
            Nothing

        Just "" ->
            Nothing

        Just scope ->
            if scopeMembers tags scope == [] then
                Nothing

            else
                Just scope


uniq : List String -> List String
uniq list =
    List.foldl
        (\x acc ->
            if List.member x acc then
                acc

            else
                acc ++ [ x ]
        )
        []
        list



-- ===== Grouped (kanban) sections =====


type alias Section doc =
    { key : Maybe String
    , label : String
    , count : Int
    , docs : List doc
    , subs : Maybe (List (SubSection doc))
    }


{-| Sub-groups never nest further — one level, like the LV.
-}
type alias SubSection doc =
    { key : Maybe String
    , label : String
    , count : Int
    , docs : List doc
    }


{-| One section per scope member that has docs (in registry order) plus
a trailing unassigned section; empties dropped. With a sub-group scope,
each section's docs are further split the same way. Mirrors
grouped\_sections/4 + subsections/3 + split\_by\_scope/3.
-}
groupedSections :
    List String
    -> String
    -> Maybe String
    -> (doc -> List String)
    -> List doc
    -> List (Section doc)
groupedSections workspaceTags scope subScope docTags items =
    splitByScope workspaceTags scope docTags items
        |> List.map
            (\( key, docs ) ->
                { key = key
                , label = sectionLabel scope key
                , count = List.length docs
                , docs = docs
                , subs =
                    subScope
                        |> Maybe.map
                            (\sub ->
                                splitByScope workspaceTags sub docTags docs
                                    |> List.map
                                        (\( k, ds ) ->
                                            { key = k
                                            , label = sectionLabel sub k
                                            , count = List.length ds
                                            , docs = ds
                                            }
                                        )
                            )
                }
            )


sectionLabel : String -> Maybe String -> String
sectionLabel scope key =
    case key of
        Just k ->
            valueOf k

        Nothing ->
            "no " ++ scope


{-| (member-or-nothing, docs) in member order then unassigned, empties
dropped. A doc lands under the FIRST scope member (registry order) it
carries. Mirrors split\_by\_scope/3.
-}
splitByScope :
    List String
    -> String
    -> (doc -> List String)
    -> List doc
    -> List ( Maybe String, List doc )
splitByScope workspaceTags scope docTags items =
    let
        members =
            scopeMembers workspaceTags scope

        keyOf doc =
            members
                |> List.filter (\m -> List.member m (docTags doc))
                |> List.head

        bucketFor key =
            ( key, List.filter (\doc -> keyOf doc == key) items )
    in
    (List.map (Just >> bucketFor) members ++ [ bucketFor Nothing ])
        |> List.filter (\( _, docs ) -> docs /= [])



-- ===== Edited-within grammar =====


{-| Normalizes a relative-window token like "7d" or "24h" to its
canonical string, or Nothing. Windows cap at 365 days. Mirrors
Docs.normalize\_within.
-}
normalizeWithin : Maybe String -> Maybe String
normalizeWithin maybeToken =
    maybeToken
        |> Maybe.andThen
            (\raw ->
                let
                    token =
                        String.trim raw

                    digits =
                        String.dropRight 1 token

                    unit =
                        String.right 1 token
                in
                if (unit == "h" || unit == "d") && digits /= "" && String.length digits <= 4 && String.all Char.isDigit digits then
                    String.toInt digits
                        |> Maybe.andThen
                            (\n ->
                                let
                                    hours =
                                        if unit == "d" then
                                            n * 24

                                        else
                                            n
                                in
                                if hours >= 1 && hours <= 365 * 24 then
                                    Just (String.fromInt n ++ unit)

                                else
                                    Nothing
                            )

                else
                    Nothing
            )



-- ===== Sort =====


parseSort : Maybe String -> Sort
parseSort s =
    case s of
        Just "kudos" ->
            Kudos

        Just "views" ->
            Views

        _ ->
            Recent


sortToParam : Sort -> String
sortToParam sort =
    case sort of
        Recent ->
            "recent"

        Kudos ->
            "kudos"

        Views ->
            "views"


sortLabel : Sort -> String
sortLabel sort =
    case sort of
        Recent ->
            "Recent"

        Kudos ->
            "Kudos"

        Views ->
            "Views"



-- ===== Saved-view seeding + modified indicator =====


{-| Pristine view load: seed the knobs from the saved config. Authors
and search always start empty — they are session state, never part of a
view. Mirrors the pristine branch of handle\_params (including the
"sub-group only with a different group" rule).
-}
seedKnobs : List String -> ViewConfig -> Knobs
seedKnobs workspaceTags config =
    let
        groupBy =
            parseGroup workspaceTags config.groupBy

        subGroupBy =
            parseGroup workspaceTags config.subGroupBy
    in
    { tags = config.tags
    , authors = []
    , groupBy = groupBy
    , subGroupBy =
        if groupBy /= Nothing && subGroupBy /= groupBy then
            subGroupBy

        else
            Nothing
    , edited = normalizeWithin config.edited
    , sort = parseSort config.sort
    , search = ""
    }


{-| Whether the current knobs deviate from the saved view's config —
drives the "modified / reset" indicator. Mirrors the modified?
computation in handle\_params.
-}
isModified : List String -> ViewConfig -> Knobs -> Bool
isModified workspaceTags config knobs =
    (List.sort knobs.tags /= List.sort config.tags)
        || (knobs.groupBy /= parseGroup workspaceTags config.groupBy)
        || (knobs.subGroupBy /= parseGroup workspaceTags config.subGroupBy)
        || (knobs.sort /= parseSort config.sort)
        || (knobs.edited /= normalizeWithin config.edited)
        || (knobs.authors /= [])
        || (knobs.search /= "")



-- ===== View switcher sections =====


{-| The switcher's sections: Team, Yours (your personal bucket), then
one group per project bucket (views sorted by name within a group;
groups sorted by bucket name). Mirrors view\_sections/2.
-}
viewSections :
    List ViewDef
    -> { team : List ViewDef, yours : List ViewDef, buckets : List ( Bucket, List ViewDef ) }
viewSections views =
    let
        kindOf v =
            v.bucket |> Maybe.map .kind

        team =
            List.filter (\v -> kindOf v == Just "team") views

        yours =
            List.filter (\v -> kindOf v == Just "personal") views

        project =
            List.filter (\v -> kindOf v /= Just "team" && kindOf v /= Just "personal" && v.bucket /= Nothing) views

        bucketNames =
            project
                |> List.filterMap (.bucket >> Maybe.map .name)
                |> uniq
                |> List.sort

        groupFor name =
            project
                |> List.filter (\v -> (v.bucket |> Maybe.map .name) == Just name)
                |> List.sortBy .name
    in
    { team = team
    , yours = yours
    , buckets =
        bucketNames
            |> List.filterMap
                (\name ->
                    case groupFor name of
                        [] ->
                            Nothing

                        (first :: _) as vs ->
                            first.bucket |> Maybe.map (\b -> ( b, vs ))
                )
    }
