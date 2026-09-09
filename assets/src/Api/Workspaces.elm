module Api.Workspaces exposing (Workspace, fetch)

{-| GET /papi/workspaces — the viewer's workspaces, for the sidebar
workspace switcher (fe-chrome). Mirrors `Workspaces.list_for_user/1`
as serialized by `WorkspaceController.index`.
-}

import Api
import Json.Decode as Decode exposing (Decoder)
import Session exposing (Session)


type alias Workspace =
    { id : String
    , slug : String
    , name : String
    }


decoder : Decoder (List Workspace)
decoder =
    Decode.field "workspaces"
        (Decode.list
            (Decode.map3 Workspace
                (Decode.field "id" Decode.string)
                (Decode.field "slug" Decode.string)
                (Decode.field "name" Decode.string)
            )
        )


fetch : Session -> (Result Api.Error (List Workspace) -> msg) -> Cmd msg
fetch session toMsg =
    Api.get session "/papi/workspaces" decoder toMsg
