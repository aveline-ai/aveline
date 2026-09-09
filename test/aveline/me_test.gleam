import aveline/accounts/user_info.{UserInfo}
import aveline/caps/keys.{KeysCaps} as keys_caps
import aveline/caps/workspaces.{WorkspacesCaps} as workspaces_caps
import aveline/core/ctx.{Ctx}
import aveline/fakes
import aveline/handlers/me.{MeResponse}
import aveline/workspaces/workspace_info.{WorkspaceInfo}
import gleam/option.{Some}

pub fn show_returns_user_and_memberships_test() {
  let user =
    UserInfo(
      id: "user-1",
      username: "arie",
      display_name: Some("Arie"),
      email: Some("arie@example.com"),
    )
  let ws =
    WorkspaceInfo(
      id: "ws-1",
      slug: "acme",
      name: "Acme",
      created_at: "2026-09-01T00:00:00Z",
    )

  let ctx =
    Ctx(
      ..fakes.ctx(),
      keys: KeysCaps(..keys_caps.stub(), get_user: fn(id) {
        assert id == "user-1"
        user
      }),
      workspaces: WorkspacesCaps(
        ..workspaces_caps.stub(),
        list_for_user: fn(id) {
          assert id == "user-1"
          [ws]
        },
      ),
    )

  assert me.show(ctx, fakes.scope().actor)
    == MeResponse(user: user, workspaces: [ws])
}
