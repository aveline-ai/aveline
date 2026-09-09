module Session exposing (Session, User, decoder)

{-| Server-injected bootstrap state. STABLE shared surface — page agents
must not edit this file; report needs instead.
-}

import Json.Decode as Decode exposing (Decoder)


type alias User =
    { id : String
    , username : String
    }


type alias Session =
    { csrf : String
    , user : Maybe User
    }


decoder : Decoder Session
decoder =
    Decode.map2 Session
        (Decode.field "csrf" Decode.string)
        (Decode.field "user" (Decode.nullable userDecoder))


userDecoder : Decoder User
userDecoder =
    Decode.map2 User
        (Decode.field "id" Decode.string)
        (Decode.field "username" Decode.string)
