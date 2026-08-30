///|
/// The fields of the first `type` block `src` declares.
fn fields_of(src : String) -> Array[Field] raise SpecError {
  parse(src).types[0].fields
}

///|
/// A field's `range=` written back the way the tag spelled it, or "none".
fn range_note(f : Field) -> String {
  match f.range() {
    Some(r) =>
      (if r.lo_inc { "[" } else { "(" }) +
      r.lo +
      ":" +
      r.hi +
      (if r.hi_inc { "]" } else { ")" })
    None => "none"
  }
}

///|
/// Where a field binds from, as a word.
fn bind_note(f : Field) -> String {
  match f.bind() {
    Body => "body"
    Query => "query"
    Path => "path"
    Header => "header"
  }
}

///|
test "a field binds where its tag says it does" {
  let fs = fields_of(
    (
      #|type Filter {
      #|  region: string `path:"region"`
      #|  page:   int    `form:"page"`
      #|  trace:  string `header:"X-Trace"`
      #|  name:   string `json:"name"`
      #|  note:   string
      #|}
    ),
  )
  inspect(bind_note(fs[0]), content="path")
  inspect(bind_note(fs[1]), content="query")
  inspect(bind_note(fs[2]), content="header")
  inspect(bind_note(fs[3]), content="body")
  // an untagged field reads out of the body too
  inspect(bind_note(fs[4]), content="body")
}

///|
test "a tag naming several places binds from the leftmost" {
  let a = fields_of("type Q {\n  page: int `form:\"page\" json:\"page_no\"`\n}")
  inspect(bind_note(a[0]), content="query")
  assert_eq(a[0].json_name(), "page")
  // the other way round the json tag is the leftmost, so it is the one that binds
  let b = fields_of("type Q {\n  page: int `json:\"page_no\" form:\"page\"`\n}")
  inspect(bind_note(b[0]), content="body")
  assert_eq(b[0].json_name(), "page_no")
}

///|
test "a bound field is carried under the name its own tag gives" {
  let fs = fields_of(
    (
      #|type Filter {
      #|  region: string `path:"region"`
      #|  page:   int    `form:"page,optional"`
      #|  trace:  string `header:"X-Trace"`
      #|  note:   string
      #|}
    ),
  )
  assert_eq(fs[0].json_name(), "region")
  assert_eq(fs[1].json_name(), "page")
  assert_eq(fs[2].json_name(), "X-Trace")
  assert_eq(fs[3].json_name(), "note")
}

///|
test "a tag naming no field falls back to the field's own name" {
  let fs = fields_of("type Q {\n  page: int `form:\",optional\"`\n}")
  assert_eq(fs[0].json_name(), "page")
  assert_eq(fs[0].optional(), true)
}

///|
test "the options after the wire name are read" {
  let fs = fields_of(
    (
      #|type Query {
      #|  page:  int    `form:"page,default=1"`
      #|  size:  int    `form:"size,optional"`
      #|  sort:  string `form:"sort,options=asc|desc"`
      #|  email: string `json:"email,omitempty"`
      #|  plain: string `json:"plain"`
      #|}
    ),
  )
  assert_eq(fs[0].default_(), Some("1"))
  assert_eq(fs[0].optional(), false)
  assert_eq(fs[1].optional(), true)
  assert_eq(fs[1].default_(), None)
  assert_eq(fs[2].options(), ["asc", "desc"])
  // Go's own spelling of the same thing
  assert_eq(fs[3].optional(), true)
  assert_eq(fs[4].optional(), false)
  assert_eq(fs[4].options(), [])
}

///|
test "a range keeps its bounds and which end is closed" {
  let fs = fields_of(
    (
      #|type Query {
      #|  age:   int     `form:"age,range=[1:120]"`
      #|  ratio: float64 `form:"ratio,range=(0:1)"`
      #|  from:  int64   `form:"from,range=[10:]"`
      #|  plain: int     `form:"plain"`
      #|}
    ),
  )
  inspect(range_note(fs[0]), content="[1:120]")
  inspect(range_note(fs[1]), content="(0:1)")
  // an open end is empty, not absent
  inspect(range_note(fs[2]), content="[10:]")
  inspect(range_note(fs[3]), content="none")
}

///|
test "an options= list is trimmed, and an empty entry is not one of them" {
  let fs = fields_of("type Q {\n  s: string `form:\"s,options= a | b |\"`\n}")
  assert_eq(fs[0].options(), ["a", "b"])
}

///|
test "a range= with no brackets is not a range" {
  let fs = fields_of("type Q {\n  n: int `form:\"n,range=1:100\"`\n}")
  inspect(range_note(fs[0]), content="none")
  // and neither is one with no colon between the bounds
  let m = fields_of("type Q {\n  n: int `form:\"n,range=[1100]\"`\n}")
  inspect(range_note(m[0]), content="none")
}

///|
test "a tag whose body is never closed binds nothing" {
  let fs = fields_of("type Q {\n  page: int `form:\"page`\n}")
  inspect(bind_note(fs[0]), content="body")
  assert_eq(fs[0].json_name(), "page")
}

///|
test "the MoonBit spelling of a field is snake_case whatever the spec wrote" {
  let fs = fields_of(
    (
      #|type Account {
      #|  UserName string `json:"user_name"`
      #|  postID   int64
      #|}
    ),
  )
  // a MoonBit struct field has to start lower-case, so `UserName` cannot be one
  assert_eq(fs[0].mbt_name(), "user_name")
  assert_eq(fs[0].json_name(), "user_name")
  assert_eq(fs[1].mbt_name(), "post_id")
  // and the wire name is the tag's, which need not agree with either
  assert_eq(fs[1].json_name(), "postID")
}
