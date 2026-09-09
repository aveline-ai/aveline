//// The user fields the API echoes (mirrors AvelineWeb.Api.Views.user/1).
//// Email and display name are optional at signup, so they're optional here.

import gleam/option.{type Option}

pub type UserInfo {
  UserInfo(
    id: String,
    username: String,
    display_name: Option(String),
    email: Option(String),
  )
}
