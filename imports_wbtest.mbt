///|
/// The name of every type in `spec`, in order.
fn type_names(spec : Spec) -> Array[String] {
  let out : Array[String] = []
  for t in spec.types {
    out.push(t.name)
  }
  out
}

///|
test "a single import and a grouped one both name their files" {
  let src =
    #|import "user.api"
    #|import (
    #|  "shared/base.api"
    #|  "../common.api"
    #|)
    #|service greet {
    #|  @handler ping
    #|  get /ping
    #|}
  assert_eq(parse(src).imports, ["user.api", "shared/base.api", "../common.api"])
  assert_eq(deps(src, from="spec/greet.api"), [
    "spec/user.api", "spec/shared/base.api", "common.api",
  ])
  // an absolute import points where it says, and `.` folds away
  assert_eq(
    resolve_import("spec/greet.api", "/etc/shared/./base.api"),
    "/etc/shared/base.api",
  )
  // including one off a Windows drive, and a Windows separator on the way in
  assert_eq(
    resolve_import("spec/greet.api", "C:\\specs\\base.api"),
    "C:/specs/base.api",
  )
  assert_eq(resolve_import("spec\\greet.api", "base.api"), "spec/base.api")
}

///|
test "an import on one line closes on that line" {
  let spec = parse("import ( \"a.api\" \"b.api\" )\nservice greet {\n}")
  assert_eq(spec.imports, ["a.api", "b.api"])
}

///|
test "an unreadable import is reported" {
  inspect(
    complaint("import user.api\nservice greet {\n}"),
    content="line 1: import needs a quoted path",
  )
  inspect(
    complaint("import (\n  user.api\n)\nservice greet {\n}"),
    content="line 2: expected a quoted path in the import group, got \"user.api\"",
  )
  inspect(
    complaint("import (\n  \"a.api\"\nservice greet {\n}"),
    content="line 1: import block is missing its closing `)`",
  )
}

///|
test "an import is a statement, not a field of a type block left open" {
  let spec = parse_lenient("type User {\n  id: int64\nimport \"a.api\"\n")
  assert_eq(spec.imports, ["a.api"])
  assert_eq(spec.types[0].fields.length(), 1)
}

///|
test "an importing spec sees the imported types and routes" {
  let files : Map[String, String] = Map([
    (
      "spec/user.api",
      (
        #|type LoginReq {
        #|  name: string
        #|}
        #|@server(group: user, prefix: /api/v1)
        #|service greet {
        #|  @handler login
        #|  post /login (LoginReq)
        #|}
      ),
    ),
  ])
  let main =
    #|import "user.api"
    #|
    #|type PingResp {
    #|  ok: bool
    #|}
    #|
    #|service greet {
    #|  @handler ping
    #|  get /ping returns (PingResp)
    #|}
  let spec = parse_all(main, files, from="spec/greet.api")
  assert_eq(spec.service, "greet")
  // the import is merged in first, then the importing file's own
  assert_eq(type_names(spec), ["LoginReq", "PingResp"])
  assert_eq(spec.routes.length(), 2)
  assert_eq(spec.routes[0].path, "/api/v1/login")
  assert_eq(spec.routes[0].req, "LoginReq")
  assert_eq(spec.routes[1].path, "/ping")
  assert_eq(spec.groups.length(), 1)
  assert_eq(spec.imports, ["spec/user.api"])
  // and the merged spec generates the imported type and route too
  let code = generate(spec)
  assert_eq(contains(code, "pub(all) struct LoginReq {"), true)
  assert_eq(
    contains(code, "app.post(\"/api/v1/login\", ctx => login(ctx))"),
    true,
  )
}

///|
test "an import resolves against the file that wrote it" {
  let files : Map[String, String] = Map([
    ("api/base/types.api", "type Base {\n  id: int64\n}\n"),
    (
      "api/user.api", "import \"base/types.api\"\ntype User {\n  name: string\n}\n",
    ),
  ])
  let spec = parse_all(
    "import \"user.api\"\nservice greet {\n}",
    files,
    from="api/greet.api",
  )
  assert_eq(type_names(spec), ["Base", "User"])
}

///|
test "a file two others import is merged once" {
  let files : Map[String, String] = Map([
    ("base.api", "type Base {\n  id: int64\n}\n"),
    ("left.api", "import \"base.api\"\ntype Left {\n  a: int\n}\n"),
    ("right.api", "import \"base.api\"\ntype Right {\n  b: int\n}\n"),
  ])
  let main =
    #|import (
    #|  "left.api"
    #|  "right.api"
    #|)
    #|service greet {
    #|}
  assert_eq(type_names(parse_all(main, files, from="main.api")), [
    "Base", "Left", "Right",
  ])
}

///|
test "a cycle back to the importing file terminates" {
  let files : Map[String, String] = Map([
    ("base.api", "import \"main.api\"\ntype Base {\n  id: int64\n}\n"),
  ])
  let main = "import \"base.api\"\nservice greet {\n}"
  assert_eq(type_names(parse_all(main, files, from="main.api")), ["Base"])
}

///|
test "an import that is not among the files is named" {
  try
    parse_all(
      "import \"user.api\"\nservice greet {\n}",
      Map([]),
      from="spec/greet.api",
    )
    |> ignore
  catch {
    e => inspect(e, content="spec/greet.api: cannot read import \"user.api\"")
  } noraise {
    _ => fail("a missing import parsed")
  }
}

///|
test "a complaint from an imported file names that file" {
  let files : Map[String, String] = Map([
    ("user.api", "service greet {\n  gett /ping ping\n}"),
  ])
  try
    parse_all("import \"user.api\"\nservice greet {\n}", files) |> ignore
  catch {
    e => inspect(e, content="line 2: user.api: unknown verb \"gett\"")
  } noraise {
    _ => fail("a broken import parsed")
  }
}

///|
test "a service name comes from the import when the importer has none" {
  let files : Map[String, String] = Map([
    ("user.api", "service account {\n  @handler ping\n  get /ping\n}"),
  ])
  assert_eq(parse_all("import \"user.api\"", files).service, "account")
}
