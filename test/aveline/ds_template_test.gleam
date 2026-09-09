import aveline/data_sources/template

const placeholder_msg = "template must contain the literal <password> placeholder exactly once (the real password is passed separately and stored encrypted)"

pub fn adapters_derive_from_scheme_test() {
  assert template.validate("postgres://u:<password>@h/db") == Ok("postgres")
  assert template.validate("postgresql://u:<password>@h/db") == Ok("postgres")
  assert template.validate("mysql://u:<password>@h:3306/db") == Ok("mysql")
  assert template.validate(
      "redshift://u:<password>@c.redshift.amazonaws.com:5439/db",
    )
    == Ok("redshift")
}

pub fn scheme_is_case_insensitive_test() {
  assert template.validate("Postgres://u:<password>@h/db") == Ok("postgres")
}

pub fn placeholder_must_appear_exactly_once_test() {
  assert template.validate("postgres://u:realpass@h/db")
    == Error(placeholder_msg)
  assert template.validate("postgres://<password>:<password>@h/db")
    == Error(placeholder_msg)
}

pub fn missing_scheme_test() {
  assert template.validate("<password>example.com/db")
    == Error("template must include a scheme: postgres://... or mysql://...")
}

pub fn missing_host_test() {
  assert template.validate("postgres:<password>@h/db")
    == Error("template must include a host")
  assert template.validate("postgres://u:<password>@/db")
    == Error("template must include a host")
}

pub fn unsupported_scheme_test() {
  assert template.validate("http://u:<password>@h/db")
    == Error(
      "unsupported scheme \"http\"; expected postgres://, mysql://, or redshift://",
    )
  // Quirk preserved from the Elixir clauses: redshift without a host
  // reads as unsupported, not missing-host.
  assert template.validate("redshift://?x=<password>")
    == Error(
      "unsupported scheme \"redshift\"; expected postgres://, mysql://, or redshift://",
    )
}
