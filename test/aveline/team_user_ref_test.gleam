import aveline/team/user_ref.{UserId, Username, parse}

pub fn valid_uuid_is_a_user_id_test() {
  assert parse("0b8228b5-72f4-4d47-9d23-0e94c9a4d63a")
    == UserId("0b8228b5-72f4-4d47-9d23-0e94c9a4d63a")
}

pub fn uppercase_uuid_is_downcased_like_ecto_cast_test() {
  assert parse("0B8228B5-72F4-4D47-9D23-0E94C9A4D63A")
    == UserId("0b8228b5-72f4-4d47-9d23-0e94c9a4d63a")
}

pub fn plain_name_is_a_username_test() {
  assert parse("arie") == Username("arie")
}

pub fn hyphenated_name_is_a_username_test() {
  assert parse("not-a-uuid") == Username("not-a-uuid")
}

pub fn non_hex_uuid_shape_is_a_username_test() {
  assert parse("0b8228b5-72f4-4d47-9d23-0e94c9a4d63z")
    == Username("0b8228b5-72f4-4d47-9d23-0e94c9a4d63z")
}

pub fn wrong_segment_lengths_are_a_username_test() {
  assert parse("0b8228b5-72f4-4d47-9d23-0e94c9a4d63")
    == Username("0b8228b5-72f4-4d47-9d23-0e94c9a4d63")
}
