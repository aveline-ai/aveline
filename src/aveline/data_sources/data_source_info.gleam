//// The data source fields handlers make decisions on and read surfaces
//// echo (mirrors Aveline.DataSources.safe_map/1). `url` is the TEMPLATE
//// with its literal `<password>` placeholder — never a secret.

pub type Credential {
  /// A live encrypted password exists (write-only, no read path).
  Live
  /// Row was deleted/superseded and its secret destroyed.
  Redacted
  /// The built-in workspace source never had a credential.
  NoCredential
}

pub type DataSourceInfo {
  DataSourceInfo(
    id: String,
    name: String,
    /// "postgres" | "mysql" | "redshift" | "workspace" (built-in catalog).
    adapter: String,
    url: String,
    version_number: Int,
    credential: Credential,
    deleted: Bool,
    created_at: String,
  )
}
