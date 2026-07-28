///|
/// A spec exercised by the plugin (de)serialisation round-trips.
let plugin_spec_src : String =
  #|service greet {
  #|  get  /ping       ping        "health check"
  #|  post /users      create_user "create a user"
  #|}
  #|
  #|type User {
  #|  id:   int64
  #|  name: string
  #|}

///|
test "spec_to_json then spec_from_json round-trips the spec" {
  let spec = parse(plugin_spec_src)
  let back = spec_from_json(spec_to_json(spec))
  assert_eq(back.service, "greet")
  assert_eq(back.routes.length(), 2)
  assert_eq(back.routes[0].verb, "get")
  assert_eq(back.routes[0].path, "/ping")
  assert_eq(back.routes[0].handler, "ping")
  assert_eq(back.routes[0].summary, "health check")
  assert_eq(back.routes[1].handler, "create_user")
  assert_eq(back.types.length(), 1)
  assert_eq(back.types[0].name, "User")
  assert_eq(back.types[0].fields.length(), 2)
  assert_eq(back.types[0].fields[0].name, "id")
  // the mapped MoonBit type survives the trip
  assert_eq(back.types[0].fields[0].type_, "Int64")
  assert_eq(back.types[0].fields[1].type_, "String")
}

///|
test "plugin_request emits the type_ member as `type`" {
  let req = plugin_request(parse(plugin_spec_src))
  assert_eq(contains(req, "\"service\": \"greet\""), true)
  assert_eq(contains(req, "\"handler\": \"ping\""), true)
  // fields carry `type`, not `type_`
  assert_eq(contains(req, "\"type\": \"Int64\""), true)
  assert_eq(contains(req, "type_"), false)
}

///|
test "parse_gen_files accepts the {files:[...]} envelope" {
  let j = @json.parse(
    (
      #|{"files": [
      #|  {"path": "a.mbt", "content": "let a = 1"},
      #|  {"path": "b.mbt", "content": "let b = 2"}
      #|]}
    ),
  )
  let files = parse_gen_files(j)
  assert_eq(files.length(), 2)
  assert_eq(files[0].path, "a.mbt")
  assert_eq(files[0].content, "let a = 1")
  assert_eq(files[1].path, "b.mbt")
}

///|
test "parse_gen_files accepts a bare array and skips path-less entries" {
  let j = @json.parse(
    (
      #|[
      #|  {"path": "x.txt", "content": "hi"},
      #|  {"content": "no path here"}
      #|]
    ),
  )
  let files = parse_gen_files(j)
  assert_eq(files.length(), 1)
  assert_eq(files[0].path, "x.txt")
  assert_eq(files[0].content, "hi")
}

///|
test "gen_files_to_json then parse_gen_files round-trips the files" {
  let files : Array[GenFile] = [
    { path: "routes.md", content: "# routes\n- GET /ping" },
    { path: "count.txt", content: "2" },
  ]
  let back = parse_gen_files(gen_files_to_json(files))
  assert_eq(back.length(), 2)
  assert_eq(back[0].path, "routes.md")
  assert_eq(back[0].content, "# routes\n- GET /ping")
  assert_eq(back[1].content, "2")
}
