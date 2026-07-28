///|
/// Look up a string-valued key in a JSON object, or `""` if absent / not a string.
fn jstr(obj : Map[String, Json], key : String) -> String {
  match obj.get(key) {
    Some(String(s)) => s
    _ => ""
  }
}

///|
/// Look up an object-valued key, or an empty map if absent / not an object.
fn jobj(obj : Map[String, Json], key : String) -> Map[String, Json] {
  match obj.get(key) {
    Some(Object(m)) => m
    _ => Map([])
  }
}

///|
test "generated OpenAPI 3.1 parses and carries the expected paths" {
  let src =
    #|service greet {
    #|  get  /ping        ping        "health check"
    #|  get  /users/:id   get_user
    #|  get  /users       list_users
    #|  post /users       create_user "create a user"
    #|}
    #|
    #|type User {
    #|  id:   int64
    #|  name: string
    #|}
  let spec = parse(src)
  let js = generate_doc(spec, version=OpenApi31, api_version="1.2.3")
  let parsed = @json.parse(js)
  let root = match parsed {
    Object(m) => m
    _ => Map([])
  }
  assert_eq(jstr(root, "openapi"), "3.1.0")
  assert_eq(jstr(jobj(root, "info"), "title"), "greet")
  assert_eq(jstr(jobj(root, "info"), "version"), "1.2.3")
  let paths = jobj(root, "paths")
  // `:id` became `{id}`; each verb is present under its path
  assert_eq(paths.contains("/ping"), true)
  assert_eq(paths.contains("/users/{id}"), true)
  assert_eq(paths.contains("/users"), true)
  let users = jobj(paths, "/users")
  assert_eq(users.contains("get"), true)
  assert_eq(users.contains("post"), true)
  // operationId + summary carried through
  assert_eq(jstr(jobj(users, "post"), "operationId"), "create_user")
  assert_eq(jstr(jobj(users, "post"), "summary"), "create a user")
  // path parameter for /users/{id}
  let get_user = jobj(jobj(paths, "/users/{id}"), "get")
  let params = match get_user.get("parameters") {
    Some(Array(a)) => a
    _ => []
  }
  assert_eq(params.length(), 1)
  let p0 = match params[0] {
    Object(m) => m
    _ => Map([])
  }
  assert_eq(jstr(p0, "name"), "id")
  assert_eq(jstr(p0, "in"), "path")
  // OpenAPI 3.x nests the param type under `schema`
  assert_eq(jstr(jobj(p0, "schema"), "type"), "string")
  // the `type` block became a component schema with typed properties
  let schemas = jobj(jobj(root, "components"), "schemas")
  assert_eq(schemas.contains("User"), true)
  let user = jobj(schemas, "User")
  assert_eq(jstr(user, "type"), "object")
  let props = jobj(user, "properties")
  assert_eq(jstr(jobj(props, "id"), "format"), "int64")
  assert_eq(jstr(jobj(props, "name"), "type"), "string")
}

///|
test "Swagger 2.0 uses definitions and inline path-param type" {
  let src =
    #|service s {
    #|  get /items/:id show
    #|}
    #|type Item {
    #|  id: int
    #|}
  let js = generate_doc(parse(src), version=Swagger20)
  let root = match @json.parse(js) {
    Object(m) => m
    _ => Map([])
  }
  assert_eq(jstr(root, "swagger"), "2.0")
  // 2.0 hoists schemas under `definitions`, not `components/schemas`
  assert_eq(root.contains("definitions"), true)
  assert_eq(root.contains("components"), false)
  assert_eq(jobj(root, "definitions").contains("Item"), true)
  // 2.0 puts the path-param type inline (no `schema` wrapper)
  let show = jobj(jobj(jobj(root, "paths"), "/items/{id}"), "get")
  let p0 = match show.get("parameters") {
    Some(Array([Object(m), ..])) => m
    _ => Map([])
  }
  assert_eq(jstr(p0, "type"), "string")
  assert_eq(p0.contains("schema"), false)
}

///|
test "component schema types: array items, map additionalProperties, $ref" {
  let src =
    #|type Bag {
    #|  tags:  []string
    #|  attrs: map[string]int64
    #|  owner: User
    #|}
    #|type User {
    #|  id: int64
    #|}
  let js = generate_doc(parse(src), version=OpenApi30)
  let root = match @json.parse(js) {
    Object(m) => m
    _ => Map([])
  }
  let bag = jobj(jobj(jobj(root, "components"), "schemas"), "Bag")
  let props = jobj(bag, "properties")
  let tags = jobj(props, "tags")
  assert_eq(jstr(tags, "type"), "array")
  assert_eq(jstr(jobj(tags, "items"), "type"), "string")
  let attrs = jobj(props, "attrs")
  assert_eq(jstr(attrs, "type"), "object")
  assert_eq(jstr(jobj(attrs, "additionalProperties"), "format"), "int64")
  // an unknown type name is another `type` block -> a $ref
  assert_eq(jstr(jobj(props, "owner"), "$ref"), "#/components/schemas/User")
}

///|
test "swagger UI stub points at the served spec" {
  let html = swagger_ui_stub(spec_url="/openapi.json", title="greet")
  assert_eq(contains(html, "<title>greet</title>"), true)
  assert_eq(contains(html, "url: \"/openapi.json\""), true)
  assert_eq(contains(html, "SwaggerUIBundle"), true)
}
