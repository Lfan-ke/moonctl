///|
fn contains(haystack : String, needle : String) -> Bool {
  let hn = haystack.length()
  let nn = needle.length()
  if nn == 0 {
    return true
  }
  for i = 0; i + nn <= hn; i = i + 1 {
    let mut ok = true
    for j = 0; j < nn; j = j + 1 {
      if haystack[i + j] != needle[j] {
        ok = false
        break
      }
    }
    if ok {
      return true
    }
  }
  false
}

///|
test "parse a .api spec" {
  let src =
    #|service greet {
    #|  get /ping ping "health check"
    #|  get /users/:id get_user
    #|  post /users create_user "create a user"
    #|}
    #|
  let spec = parse(src)
  assert_eq(spec.service, "greet")
  assert_eq(spec.routes.length(), 3)
  assert_eq(spec.routes[0].verb, "get")
  assert_eq(spec.routes[0].path, "/ping")
  assert_eq(spec.routes[0].handler, "ping")
  assert_eq(spec.routes[0].summary, "health check")
  assert_eq(spec.routes[1].path, "/users/:id")
  assert_eq(spec.routes[1].summary, "")
  assert_eq(spec.routes[2].verb, "post")
}

///|
test "generate compilable moonapi scaffolding" {
  let src =
    #|service greet {
    #|  get /ping ping "health check"
    #|  post /users create_user
    #|}
  let spec = parse(src)
  let code = generate(spec)
  assert_eq(
    contains(
      code, "app.get(\"/ping\", ctx => ping(ctx), summary=\"health check\")",
    ),
    true,
  )
  assert_eq(
    contains(code, "app.post(\"/users\", ctx => create_user(ctx))"),
    true,
  )
  assert_eq(
    contains(
      code, "pub fn create_user(_ctx : @moonapi.Context) -> @moonasgi.Response",
    ),
    true,
  )
  assert_eq(contains(code, "pub fn build_app() -> @moonapi.App"), true)
  assert_eq(contains(code, "DO NOT EDIT"), true)
}

///|
test "parse type blocks into schemas" {
  let src =
    #|type User {
    #|  id:    int64
    #|  name:  string
    #|  admin: bool
    #|  tags:  []string
    #|  meta:  map[string]int
    #|}
    #|
    #|service greet {
    #|  get /users/:id get_user
    #|}
  let spec = parse(src)
  assert_eq(spec.service, "greet")
  assert_eq(spec.routes.length(), 1)
  assert_eq(spec.types.length(), 1)
  let user = spec.types[0]
  assert_eq(user.name, "User")
  assert_eq(user.fields.length(), 5)
  assert_eq(user.fields[0].name, "id")
  assert_eq(user.fields[0].type_, "Int64")
  assert_eq(user.fields[1].type_, "String")
  assert_eq(user.fields[2].type_, "Bool")
  assert_eq(user.fields[3].type_, "Array[String]")
  assert_eq(user.fields[4].type_, "Map[String, Int]")
}

///|
test "generate structs from type blocks" {
  let src =
    #|type CreateReq {
    #|  name: string
    #|  age:  int
    #|}
    #|
    #|service greet {
    #|  post /users create_user
    #|}
  let code = generate(parse(src))
  assert_eq(contains(code, "pub(all) struct CreateReq {"), true)
  assert_eq(contains(code, "  name : String"), true)
  assert_eq(contains(code, "  age : Int"), true)
  assert_eq(contains(code, "pub fn build_app() -> @moonapi.App"), true)
}

///|
test "parse goctl Go-struct fields with tags and pointers" {
  let src =
    #|type LoginReq {
    #|  UserName string `json:"user_name"`
    #|  Age      int    `json:"age,optional"`
    #|  Cursor   *int64 `json:"cursor"`
    #|  Note     string
    #|}
    #|
    #|service greet {
    #|  post /login do_login
    #|}
  let spec = parse(src)
  assert_eq(spec.types.length(), 1)
  let t = spec.types[0]
  assert_eq(t.fields.length(), 4)
  assert_eq(t.fields[0].name, "UserName")
  assert_eq(t.fields[0].type_, "String")
  assert_eq(t.fields[0].json_name(), "user_name")
  assert_eq(t.fields[1].json_name(), "age")
  assert_eq(t.fields[2].type_, "Int64?")
  assert_eq(t.fields[2].json_name(), "cursor")
  assert_eq(t.fields[3].tag, "")
  assert_eq(t.fields[3].json_name(), "Note")
}

///|
test "generate snake-cases PascalCase struct fields" {
  let src =
    #|type LoginReq {
    #|  UserName string `json:"user_name"`
    #|}
    #|
    #|service greet {
    #|  post /login do_login
    #|}
  let code = generate(parse(src))
  assert_eq(contains(code, "  user_name : String"), true)
}

///|
test "parse modern route grammar with @handler @doc and typed Req/Resp" {
  let src =
    #|type LoginReq {
    #|  UserName string `json:"user_name"`
    #|}
    #|
    #|type LoginResp {
    #|  Token string `json:"token"`
    #|}
    #|
    #|service greet {
    #|  @doc "log a user in"
    #|  @handler login
    #|  post /users/login (LoginReq) returns (LoginResp)
    #|}
  let spec = parse(src)
  assert_eq(spec.routes.length(), 1)
  let r = spec.routes[0]
  assert_eq(r.verb, "post")
  assert_eq(r.path, "/users/login")
  assert_eq(r.handler, "login")
  assert_eq(r.summary, "log a user in")
  assert_eq(r.req, "LoginReq")
  assert_eq(r.resp, "LoginResp")
  let doc = openapi_document(spec, version=OpenApi31).stringify()
  assert_eq(contains(doc, "requestBody"), true)
  assert_eq(contains(doc, "#/components/schemas/LoginReq"), true)
  assert_eq(contains(doc, "#/components/schemas/LoginResp"), true)
}

///|
test "parse skips syntax and captures the info block into the OpenAPI info" {
  let src =
    #|syntax = "v1"
    #|
    #|info (
    #|  title:   "Greet API"
    #|  desc:    "qwq service"
    #|  version: "v2"
    #|)
    #|
    #|service greet {
    #|  get /ping ping "health check"
    #|}
  let spec = parse(src)
  assert_eq(spec.routes.length(), 1)
  assert_eq(spec.routes[0].handler, "ping")
  assert_eq(info_get(spec, "title"), Some("Greet API"))
  assert_eq(info_get(spec, "desc"), Some("qwq service"))
  assert_eq(info_get(spec, "version"), Some("v2"))
  let doc = openapi_document(spec, version=OpenApi31).stringify()
  assert_eq(contains(doc, "Greet API"), true)
  assert_eq(contains(doc, "qwq service"), true)
  assert_eq(contains(doc, "v2"), true)
}

///|
test "openapi property name comes from the json tag" {
  let src =
    #|type LoginReq {
    #|  UserName string `json:"user_name"`
    #|}
    #|
    #|service greet {
    #|  post /login do_login
    #|}
  let doc = openapi_document(parse(src), version=OpenApi31).stringify()
  assert_eq(contains(doc, "user_name"), true)
}
