///|
/// Struct tags and the serialized wire name. A `type` field carries its raw
/// back-tick tag (`json:"…"`/`path`/`form`/`header`) verbatim in `Field::tag`;
/// `Field::json_name` resolves the name a value serializes under — the `json` tag
/// name with any `,optional`/`,omitempty` option stripped, falling back to the
/// field's own name when there is no `json` tag. That resolved name is exactly the
/// key `openapi_document` gives each schema property, shown here side by side.
///
///     moon run examples/12-tags
#coverage.skip
fn main {
  let source =
    #|type Account {
    #|  id:        int64  `json:"account_id"`
    #|  handle:    string `json:"handle"`
    #|  email:     string `json:"email,omitempty"`
    #|  api_token: string `json:"apiToken,optional"`
    #|  region:    string `path:"region"`
    #|  note:      string
    #|}
    #|
    #|service accounts {
    #|  get /accounts/:id get_account
    #|}
  let spec = @moonctl.parse(source)
  for t in spec.types {
    println("type \{t.name}:")
    for f in t.fields {
      let tag = if f.tag == "" { "(none)" } else { "`" + f.tag + "`" }
      println(
        "  \{f.name} : \{f.type_}  tag=\{tag}  ->  wire name \"\{f.json_name()}\"",
      )
    }
  }
  println(
    "\n==== openapi_document(spec) — schema properties keyed by json_name ====\n",
  )
  println(
    @moonctl.openapi_document(spec, version=@moonctl.OpenApi31).stringify(
      indent=2,
    ),
  )
}
