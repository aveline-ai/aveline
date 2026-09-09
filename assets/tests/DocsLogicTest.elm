module DocsLogicTest exposing (suite)

{-| Coverage for the pure logic ported from WorkspaceShowLive: tag
scope grammar, grouped sections, edited-within grammar, saved-view
seeding and the modified indicator.
-}

import Expect
import Page.Docs.Logic as Logic exposing (Sort(..))
import Test exposing (Test, describe, test)


registry : List String
registry =
    -- Registry order (sort_key then slug), mixing plain + two scopes.
    [ "priority:high", "priority:low", "runbook", "spec", "status:todo", "status:doing", "status:done" ]


type alias Doc =
    { slug : String, tags : List String }


doc : String -> List String -> Doc
doc slug tags =
    { slug = slug, tags = tags }


baseConfig : { tags : List String, groupBy : Maybe String, subGroupBy : Maybe String, sort : Maybe String, edited : Maybe String }
baseConfig =
    { tags = [ "runbook" ]
    , groupBy = Just "status"
    , subGroupBy = Nothing
    , sort = Just "kudos"
    , edited = Just "7d"
    }


suite : Test
suite =
    describe "Page.Docs.Logic"
        [ describe "scope grammar"
            [ test "scopeOf splits on the first colon" <|
                \_ ->
                    Expect.equal
                        [ Just "status", Nothing, Just "a" ]
                        (List.map Logic.scopeOf [ "status:todo", "plain", "a:b:c" ])
            , test "valueOf keeps everything after the first colon" <|
                \_ ->
                    Expect.equal
                        [ "todo", "plain", "b:c" ]
                        (List.map Logic.valueOf [ "status:todo", "plain", "a:b:c" ])
            , test "workspaceScopes: first-appearance order, deduplicated" <|
                \_ ->
                    Expect.equal [ "priority", "status" ] (Logic.workspaceScopes registry)
            , test "scopeMembers keeps registry order" <|
                \_ ->
                    Expect.equal
                        [ "status:todo", "status:doing", "status:done" ]
                        (Logic.scopeMembers registry "status")
            , test "groupedTags: plain first, scoped sections sorted by scope" <|
                \_ ->
                    Expect.equal
                        ( [ "runbook", "spec" ]
                        , [ ( "priority", [ "priority:high", "priority:low" ] )
                          , ( "status", [ "status:todo", "status:doing", "status:done" ] )
                          ]
                        )
                        (Logic.groupedTags registry)
            , test "parseGroup rejects scopes without members" <|
                \_ ->
                    Expect.equal
                        [ Just "status", Nothing, Nothing ]
                        (List.map (Logic.parseGroup registry)
                            [ Just "status", Just "nope", Nothing ]
                        )
            ]
        , describe "groupedSections"
            [ test "member order, unassigned last, empties dropped" <|
                \_ ->
                    let
                        docs =
                            [ doc "a" [ "status:done" ]
                            , doc "b" [ "runbook" ]
                            , doc "c" [ "status:todo" ]
                            , doc "d" [ "status:todo", "spec" ]
                            ]
                    in
                    Logic.groupedSections registry "status" Nothing .tags docs
                        |> List.map (\s -> ( s.label, List.map .slug s.docs, s.count ))
                        |> Expect.equal
                            [ ( "todo", [ "c", "d" ], 2 )
                            , ( "done", [ "a" ], 1 )
                            , ( "no status", [ "b" ], 1 )
                            ]
            , test "a doc lands under the FIRST scope member it carries" <|
                \_ ->
                    Logic.groupedSections registry "status" Nothing .tags [ doc "x" [ "status:done", "status:todo" ] ]
                        |> List.map .label
                        |> Expect.equal [ "todo" ]
            , test "sub-group splits each section's docs the same way" <|
                \_ ->
                    let
                        docs =
                            [ doc "a" [ "status:todo", "priority:low" ]
                            , doc "b" [ "status:todo", "priority:high" ]
                            , doc "c" [ "status:todo" ]
                            ]
                    in
                    Logic.groupedSections registry "status" (Just "priority") .tags docs
                        |> List.concatMap (\s -> s.subs |> Maybe.withDefault [])
                        |> List.map (\sub -> ( sub.label, List.map .slug sub.docs ))
                        |> Expect.equal
                            [ ( "high", [ "b" ] )
                            , ( "low", [ "a" ] )
                            , ( "no priority", [ "c" ] )
                            ]
            ]
        , describe "normalizeWithin"
            [ test "canonical tokens pass through" <|
                \_ ->
                    Expect.equal
                        [ Just "24h", Just "7d", Just "365d" ]
                        (List.map (Logic.normalizeWithin << Just) [ "24h", " 7d ", "365d" ])
            , test "junk, zero, and over-cap windows normalize to Nothing" <|
                \_ ->
                    Expect.equal
                        [ Nothing, Nothing, Nothing, Nothing, Nothing ]
                        (List.map (Logic.normalizeWithin << Just) [ "soon", "0h", "366d", "12", "d" ])
            ]
        , describe "saved-view seeding + modified"
            [ test "seedKnobs takes tags/group/sort/edited from config, empties session knobs" <|
                \_ ->
                    Expect.equal
                        { tags = [ "runbook" ]
                        , authors = []
                        , groupBy = Just "status"
                        , subGroupBy = Nothing
                        , edited = Just "7d"
                        , sort = Kudos
                        , search = ""
                        }
                        (Logic.seedKnobs registry baseConfig)
            , test "seedKnobs drops an unknown group scope and a sub equal to group" <|
                \_ ->
                    let
                        knobs =
                            Logic.seedKnobs registry
                                { baseConfig | groupBy = Just "nope", subGroupBy = Just "status" }
                    in
                    Expect.equal ( Nothing, Nothing ) ( knobs.groupBy, knobs.subGroupBy )
            , test "pristine seeded knobs are not modified" <|
                \_ ->
                    Logic.isModified registry baseConfig (Logic.seedKnobs registry baseConfig)
                        |> Expect.equal False
            , test "tag order does not matter for modified" <|
                \_ ->
                    let
                        seeded =
                            Logic.seedKnobs registry { baseConfig | tags = [ "spec", "runbook" ] }
                    in
                    Logic.isModified registry
                        { baseConfig | tags = [ "runbook", "spec" ] }
                        seeded
                        |> Expect.equal False
            , test "any deviated knob flips modified" <|
                \_ ->
                    let
                        seeded =
                            Logic.seedKnobs registry baseConfig
                    in
                    [ { seeded | tags = [] }
                    , { seeded | groupBy = Nothing }
                    , { seeded | sort = Recent }
                    , { seeded | edited = Nothing }
                    , { seeded | authors = [ "arie" ] }
                    , { seeded | search = "q" }
                    ]
                        |> List.map (Logic.isModified registry baseConfig)
                        |> Expect.equal [ True, True, True, True, True, True ]
            ]
        , describe "viewSections"
            [ test "team / yours / project buckets, groups + views sorted by name" <|
                \_ ->
                    let
                        v name bucket =
                            { name = name
                            , description = Nothing
                            , config = { tags = [], groupBy = Nothing, subGroupBy = Nothing, sort = Nothing, edited = Nothing }
                            , pinned = False
                            , bucket = bucket
                            }

                        sections =
                            Logic.viewSections
                                [ v "zeta" (Just { name = "proj-b", kind = "project" })
                                , v "mine" (Just { name = "arie", kind = "personal" })
                                , v "roadmap" (Just { name = "team", kind = "team" })
                                , v "alpha" (Just { name = "proj-b", kind = "project" })
                                , v "solo" (Just { name = "proj-a", kind = "project" })
                                ]
                    in
                    Expect.all
                        [ \s -> Expect.equal [ "roadmap" ] (List.map .name s.team)
                        , \s -> Expect.equal [ "mine" ] (List.map .name s.yours)
                        , \s ->
                            Expect.equal
                                [ ( "proj-a", [ "solo" ] ), ( "proj-b", [ "alpha", "zeta" ] ) ]
                                (List.map (\( b, vs ) -> ( b.name, List.map .name vs )) s.buckets)
                        ]
                        sections
            ]
        ]
