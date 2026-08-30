///|
test "an @server block groups its routes and prefixes their paths" {
  let src =
    #|@server(group: user, prefix: /api/v1)
    #|service greet {
    #|  @handler ping
    #|  get /ping
    #|
    #|  @doc "log a user in"
    #|  @handler login
    #|  post /login (LoginReq) returns (LoginResp)
    #|}
  let spec = parse(src)
  assert_eq(spec.groups.length(), 1)
  assert_eq(spec.groups[0].name, "user")
  assert_eq(spec.groups[0].prefix, "/api/v1")
  assert_eq(spec.routes.length(), 2)
  assert_eq(spec.routes[0].path, "/api/v1/ping")
  assert_eq(spec.routes[1].path, "/api/v1/login")
  match spec.routes[1].group {
    Some(g) => assert_eq(g.name, "user")
    None => fail("the route lost its group")
  }
  let code = generate(spec)
  assert_eq(contains(code, "// @server group: user, prefix: /api/v1"), true)
  assert_eq(contains(code, "app.get(\"/api/v1/ping\", ctx => ping(ctx))"), true)
  assert_eq(contains(code, "/// `post /api/v1/login` of group user."), true)
}

///|
test "a group becomes the OpenAPI tag of its operations" {
  let src =
    #|@server(group: user, prefix: /api/v1)
    #|service greet {
    #|  @handler ping
    #|  get /ping
    #|}
  let doc = openapi_document(parse(src), version=OpenApi31).stringify()
  assert_eq(contains(doc, "\"/api/v1/ping\""), true)
  assert_eq(contains(doc, "\"operationId\":\"ping\",\"tags\":[\"user\"]"), true)
  assert_eq(contains(doc, "\"tags\":[{\"name\":\"user\"}]"), true)
}

///|
test "a multi-line @server block carries every annotation" {
  let src =
    #|@server (
    #|  group:      user
    #|  prefix:     /api/v1
    #|  jwt:        Auth
    #|  middleware: Log,Trace
    #|  maxBytes:   1048576
    #|  timeout:    3s
    #|  signature:  true
    #|  swagger:    "user.json"
    #|)
    #|service greet {
    #|  @handler ping
    #|  get /ping
    #|}
  let spec = parse(src)
  let g = spec.groups[0]
  assert_eq(g.name, "user")
  assert_eq(g.prefix, "/api/v1")
  assert_eq(g.jwt, "Auth")
  assert_eq(g.middleware, ["Log", "Trace"])
  assert_eq(g.max_bytes, 1048576L)
  assert_eq(g.timeout, "3s")
  assert_eq(g.signature, true)
  assert_eq(g.extra.length(), 1)
  assert_eq(g.extra[0].0, "swagger")
  assert_eq(g.extra[0].1, "user.json")
}

///|
test "each service block takes the @server block above it" {
  let src =
    #|@server(group: user, prefix: /api/v1)
    #|service greet {
    #|  @handler login
    #|  post /login
    #|}
    #|
    #|@server(group: admin, prefix: /admin/)
    #|service greet {
    #|  @handler purge
    #|  delete /purge
    #|}
    #|
    #|service greet {
    #|  @handler ping
    #|  get /ping
    #|}
  let spec = parse(src)
  assert_eq(spec.groups.length(), 2)
  assert_eq(spec.routes[0].path, "/api/v1/login")
  assert_eq(spec.routes[1].path, "/admin/purge")
  assert_eq(spec.routes[2].path, "/ping")
  match spec.routes[2].group {
    Some(g) => fail("an ungrouped route picked up group " + g.name)
    None => ()
  }
}

///|
test "a group round-trips through the plugin JSON" {
  let src =
    #|@server(group: user, prefix: /api/v1, middleware: Log,Trace, maxBytes: 233)
    #|service greet {
    #|  @handler ping
    #|  get /ping
    #|}
  let back = spec_from_json(spec_to_json(parse(src)))
  assert_eq(back.groups.length(), 1)
  assert_eq(back.groups[0].middleware, ["Log", "Trace"])
  assert_eq(back.groups[0].max_bytes, 233L)
  assert_eq(back.routes[0].path, "/api/v1/ping")
  match back.routes[0].group {
    Some(g) => assert_eq(g.name, "user")
    None => fail("the route lost its group")
  }
}

///|
test "a verb is lower-cased for the moonapi call it generates" {
  let spec = parse("service greet {\n  GET /ping ping\n}")
  assert_eq(spec.routes[0].verb, "get")
  assert_eq(
    contains(generate(spec), "app.get(\"/ping\", ctx => ping(ctx))"),
    true,
  )
}

///|
test "a trailing comment stays out of a field type and a route summary" {
  let src =
    #|type User {
    #|  id:   int64  // the primary key
    #|  name: string `json:"name"` // display name
    #|  Note  string // the go-struct form too
    #|}
    #|
    #|service greet {
    #|  get /ping ping "health check" // liveness
    #|  get /pong pong // no summary on this one
    #|}
  let spec = parse(src)
  let user = spec.types[0]
  assert_eq(user.fields[0].type_, "Int64")
  assert_eq(user.fields[1].type_, "String")
  assert_eq(user.fields[1].tag, "json:\"name\"")
  assert_eq(user.fields[2].type_, "String")
  assert_eq(spec.routes[0].summary, "health check")
  assert_eq(spec.routes[1].handler, "pong")
  assert_eq(spec.routes[1].summary, "")
}

///|
/// The parser's complaint about `src`, or "" when it reads cleanly.
fn complaint(src : String) -> String {
  try parse(src) |> ignore catch {
    e => Show::to_string(e)
  } noraise {
    _ => ""
  }
}

///|
/// Every complaint the parser has about `src`, one per line, in the order it made
/// them — `complaint` shows only the earliest.
fn complaints(src : String) -> String {
  let mut out = ""
  for it in read(src).1 {
    let one = "line " + it.0.to_string() + ": " + it.1
    out = if out == "" { one } else { out + "\n" + one }
  }
  out
}

///|
test "a misspelt verb is reported with its line" {
  inspect(
    complaint(
      (
        #|service greet {
        #|  get /ping ping
        #|  gett /pong pong
        #|}
      ),
    ),
    content="line 3: unknown verb \"gett\"",
  )
}

///|
test "a misspelt annotation is reported with its line" {
  inspect(
    complaint(
      (
        #|service greet {
        #|  @hadler login
        #|  post /login
        #|}
      ),
    ),
    content="line 2: unknown annotation \"@hadler\"",
  )
}

///|
test "a block left open is reported at the line that opened it" {
  inspect(
    complaint(
      (
        #|type User {
        #|  id: int64
        #|
        #|service greet {
        #|  get /ping ping
        #|}
      ),
    ),
    content="line 1: type User is missing its closing `}`",
  )
  inspect(
    complaint("service greet {\n  get /ping ping\n"),
    content="line 1: service greet is missing its closing `}`",
  )
  inspect(
    complaint("@server (\n  group: user\nservice greet {\n}"),
    content="line 1: @server block is missing its closing `)`",
  )
}

///|
test "a field with no type is reported" {
  inspect(
    complaint("type User {\n  id:\n}"),
    content="line 2: field \"id:\" in type User has no type",
  )
  // a bare name is goctl's inline embed, so only a line that names nothing is one
  inspect(
    complaint("type User {\n  42\n}"),
    content="line 2: field \"42\" in type User has no type",
  )
  inspect(
    complaint("type User {\n  a-b\n}"),
    content="line 2: field \"a-b\" in type User has no type",
  )
}

///|
test "a route with no handler is reported" {
  inspect(
    complaint("service greet {\n  get /ping\n}"),
    content="line 2: route get /ping has no handler; name one with `@handler`",
  )
  inspect(
    complaint("service greet {\n  @handler ping\n}"),
    content="line 3: @handler ping has no route",
  )
}

///|
test "the handlers a spec forgot to name still differ from one another" {
  let spec = parse_lenient(
    (
      #|service greet {
      #|  get /ping
      #|  get /users/:id
      #|  post /users
      #|}
    ),
  )
  assert_eq(spec.routes[0].handler, "get_ping_handler")
  assert_eq(spec.routes[1].handler, "get_users_id_handler")
  assert_eq(spec.routes[2].handler, "post_users_handler")
  // three routes, three functions — one name declared twice would not compile
  let code = generate(spec)
  assert_eq(contains(code, "pub fn get_ping_handler("), true)
  assert_eq(contains(code, "pub fn get_users_id_handler("), true)
  assert_eq(contains(code, "pub fn post_users_handler("), true)
}

///|
test "@doc is read in every spelling goctl writes" {
  // the block form, over several lines
  inspect(
    parse(
      (
        #|service greet {
        #|  @doc (
        #|    summary: "log a user in"
        #|  )
        #|  @handler login
        #|  post /login
        #|}
      ),
    ).routes[0].summary,
    content="log a user in",
  )
  // the same block on one line, and `description` standing in for `summary`
  inspect(
    parse(
      "service greet {\n  @doc(summary: \"ping\")\n  @handler a\n  get /a\n}",
    ).routes[0].summary,
    content="ping",
  )
  inspect(
    parse(
      "service greet {\n  @doc(description: \"pong\")\n  @handler b\n  get /b\n}",
    ).routes[0].summary,
    content="pong",
  )
  // and the two quoted forms
  inspect(
    parse("service greet {\n  @doc \"quoted\"\n  @handler c\n  get /c\n}").routes[0].summary,
    content="quoted",
  )
  inspect(
    parse("service greet {\n  @doc(\"parens\")\n  @handler d\n  get /d\n}").routes[0].summary,
    content="parens",
  )
}

///|
test "a misspelt @doc key is named rather than dropped" {
  inspect(
    complaint(
      (
        #|service greet {
        #|  @doc (
        #|    sumary: "log a user in"
        #|  )
        #|  @handler login
        #|  post /login
        #|}
      ),
    ),
    content="line 3: @doc entry \"sumary\" is not summary or description",
  )
  // an unclosed block runs to the end of the file, so the service is left open too
  inspect(
    complaints("service greet {\n  @doc (\n  @handler login\n  post /login\n}"),
    content=(
      #|line 2: @doc block is missing its closing `)`
      #|line 1: service greet is missing its closing `}`
    ),
  )
}

///|
test "an annotation that merely starts with a known one is not that one" {
  inspect(
    complaint("service greet {\n  @docs \"text\"\n  @handler a\n  get /a\n}"),
    content="line 2: unknown annotation \"@docs\"",
  )
}

///|
test "a malformed @server annotation is reported" {
  inspect(
    complaint("@server(group: user, maxBytes: lots)\nservice greet {\n}"),
    content="line 1: maxBytes: expected a number, got \"lots\"",
  )
  inspect(
    complaint("@server(signature: yes)\nservice greet {\n}"),
    content="line 1: signature: expected true or false, got \"yes\"",
  )
}

///|
test "a multi-line @server names the entry's own line, not the block's" {
  inspect(
    complaint(
      (
        #|@server (
        #|  group:    user
        #|
        #|  // the request cap
        #|  maxBytes: lots
        #|)
        #|service greet {
        #|}
      ),
    ),
    content="line 5: maxBytes: expected a number, got \"lots\"",
  )
  inspect(
    complaint("@server (\n  nonsense\n  group: user\n)\nservice greet {\n}"),
    content="line 2: @server entry \"nonsense\" is not `key: value`",
  )
}

///|
test "a quoted annotation value keeps its commas" {
  let spec = parse("@server(swagger: \"a,b\", group: user)\nservice greet {\n}")
  let g = spec.groups[0]
  assert_eq(g.name, "user")
  assert_eq(g.extra[0], ("swagger", "a,b"))
}

///|
test "parse_lenient reads what it can and reports nothing" {
  let spec = parse_lenient(
    (
      #|service greet {
      #|  gett /ping ping
      #|  get /pong pong
      #|}
    ),
  )
  assert_eq(spec.routes.length(), 1)
  assert_eq(spec.routes[0].handler, "pong")
}
