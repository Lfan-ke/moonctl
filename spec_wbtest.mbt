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
    contains(code, "app.get(\"/ping\", ping, summary=\"health check\")"),
    true,
  )
  assert_eq(contains(code, "app.post(\"/users\", create_user)"), true)
  assert_eq(
    contains(
      code, "pub fn create_user(_ctx : @moonapi.Context) -> @moonasgi.Response",
    ),
    true,
  )
  assert_eq(contains(code, "pub fn build_app() -> @moonapi.App"), true)
  assert_eq(contains(code, "DO NOT EDIT"), true)
}
