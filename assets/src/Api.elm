module Api exposing
    ( Error(..)
    , delete
    , errorMessage
    , get
    , patch
    , post
    , put
    )

{-| HTTP core for the /papi endpoints (session-cookie auth + CSRF header).
Every response uses the envelope: {ok: true, ...payload} on success,
{ok: false, error: {code, message}} on failure — including non-2xx
statuses, which is why we parse bodies ourselves instead of relying on
Http.BadStatus.

STABLE shared surface — page agents must not edit this file.
-}

import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Session exposing (Session)


type Error
    = ApiError { code : String, message : String }
    | NetworkError
    | DecodeError String


errorMessage : Error -> String
errorMessage err =
    case err of
        ApiError e ->
            e.message

        NetworkError ->
            "Network error — check your connection and retry."

        DecodeError _ ->
            "Unexpected response from the server."


get : Session -> String -> Decoder a -> (Result Error a -> msg) -> Cmd msg
get session path decoder toMsg =
    request session "GET" path Nothing decoder toMsg


post : Session -> String -> Encode.Value -> Decoder a -> (Result Error a -> msg) -> Cmd msg
post session path body decoder toMsg =
    request session "POST" path (Just body) decoder toMsg


patch : Session -> String -> Encode.Value -> Decoder a -> (Result Error a -> msg) -> Cmd msg
patch session path body decoder toMsg =
    request session "PATCH" path (Just body) decoder toMsg


put : Session -> String -> Encode.Value -> Decoder a -> (Result Error a -> msg) -> Cmd msg
put session path body decoder toMsg =
    request session "PUT" path (Just body) decoder toMsg


delete : Session -> String -> Decoder a -> (Result Error a -> msg) -> Cmd msg
delete session path decoder toMsg =
    request session "DELETE" path Nothing decoder toMsg


request : Session -> String -> String -> Maybe Encode.Value -> Decoder a -> (Result Error a -> msg) -> Cmd msg
request session method path maybeBody decoder toMsg =
    Http.request
        { method = method
        , headers = [ Http.header "x-csrf-token" session.csrf ]
        , url = path
        , body =
            case maybeBody of
                Just value ->
                    Http.jsonBody value

                Nothing ->
                    Http.emptyBody
        , expect = expectEnvelope decoder toMsg
        , timeout = Just 30000
        , tracker = Nothing
        }


expectEnvelope : Decoder a -> (Result Error a -> msg) -> Http.Expect msg
expectEnvelope decoder toMsg =
    Http.expectStringResponse toMsg <|
        \response ->
            case response of
                Http.GoodStatus_ _ body ->
                    parseBody decoder body

                Http.BadStatus_ _ body ->
                    parseBody decoder body

                Http.NetworkError_ ->
                    Err NetworkError

                Http.Timeout_ ->
                    Err NetworkError

                Http.BadUrl_ url ->
                    Err (DecodeError ("bad url: " ++ url))


parseBody : Decoder a -> String -> Result Error a
parseBody decoder body =
    case Decode.decodeString (Decode.field "ok" Decode.bool) body of
        Ok True ->
            Decode.decodeString decoder body
                |> Result.mapError (Decode.errorToString >> DecodeError)

        Ok False ->
            case Decode.decodeString envelopeErrorDecoder body of
                Ok e ->
                    Err (ApiError e)

                Err _ ->
                    Err (DecodeError "malformed error envelope")

        Err e ->
            Err (DecodeError (Decode.errorToString e))


envelopeErrorDecoder : Decoder { code : String, message : String }
envelopeErrorDecoder =
    Decode.field "error"
        (Decode.map2 (\c m -> { code = c, message = m })
            (Decode.field "code" Decode.string)
            (Decode.field "message" Decode.string)
        )
