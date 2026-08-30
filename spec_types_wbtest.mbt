///|
test "a bare name inlines the block it names" {
  let src =
    #|type Base {
    #|  id: int64
    #|  ts: int64
    #|}
    #|
    #|type User {
    #|  Base
    #|  name: string
    #|}
  let spec = parse(src)
  let user = spec.types[1]
  assert_eq(user.embeds, ["Base"])
  // the embed is not a field of its own
  assert_eq(user.fields.length(), 1)
  assert_eq(user.fields[0].name, "name")
  // MoonBit has no embedding, so the struct is the embedded fields then its own
  assert_eq(
    contains(
      generate(spec),
      (
        #|pub(all) struct User {
        #|  id : Int64
        #|  ts : Int64
        #|  name : String
        #|}
      ),
    ),
    true,
  )
}

///|
test "an embed of a block the spec never declared contributes nothing" {
  let spec = parse("type User {\n  Missing\n  name: string\n}")
  assert_eq(spec.types[0].embeds, ["Missing"])
  assert_eq(
    contains(generate(spec), "pub(all) struct User {\n  name : String\n}"),
    true,
  )
}

///|
test "an embed leading back to a block already folded in stops there" {
  let src =
    #|type A {
    #|  B
    #|  a: int
    #|}
    #|
    #|type B {
    #|  A
    #|  b: int
    #|}
  let code = generate(parse(src))
  assert_eq(
    contains(code, "pub(all) struct A {\n  b : Int\n  a : Int\n}"),
    true,
  )
  assert_eq(
    contains(code, "pub(all) struct B {\n  a : Int\n  b : Int\n}"),
    true,
  )
}

///|
test "an anonymous nested block becomes a type of its own" {
  let src =
    #|type Outer {
    #|  head: string
    #|  Inner `json:"inner"` {
    #|    a: int
    #|    b: string
    #|  }
    #|  tail: string
    #|}
    #|
    #|service greet {
    #|  @handler ping
    #|  get /ping
    #|}
  let spec = parse(src)
  assert_eq(type_names(spec), ["Outer", "OuterInner"])
  // the block keeps every field it declared — the nested one closes itself, not its
  // parent, so what follows it is still the parent's
  assert_eq(spec.types[0].fields.length(), 3)
  assert_eq(spec.types[0].fields[0].name, "head")
  assert_eq(spec.types[0].fields[1].name, "Inner")
  assert_eq(spec.types[0].fields[1].type_, "OuterInner")
  assert_eq(spec.types[0].fields[1].json_name(), "inner")
  assert_eq(spec.types[0].fields[2].name, "tail")
  assert_eq(spec.types[1].fields.length(), 2)
  assert_eq(spec.types[1].fields[0].name, "a")
  // and the service that follows is still read as one
  assert_eq(spec.routes.length(), 1)
  let code = generate(spec)
  assert_eq(
    contains(
      code,
      (
        #|pub(all) struct Outer {
        #|  head : String
        #|  inner : OuterInner
        #|  tail : String
        #|}
      ),
    ),
    true,
  )
  assert_eq(contains(code, "pub(all) struct OuterInner {\n  a : Int\n"), true)
}

///|
test "a nested block left open is reported against the block that opened it" {
  inspect(
    complaint(
      (
        #|type Outer {
        #|  Inner {
        #|    a: int
        #|}
      ),
    ),
    content="line 1: type Outer is missing its closing `}`",
  )
  inspect(
    complaint(
      (
        #|type Outer {
        #|  Inner {
        #|    a: int
        #|  }
      ),
    ),
    content="line 1: type Outer is missing its closing `}`",
  )
}

///|
test "the grouped type form takes an embed and a nested block too" {
  let src =
    #|type (
    #|  Base {
    #|    id: int64
    #|  }
    #|
    #|  User {
    #|    Base
    #|    name: string
    #|  }
    #|)
  let spec = parse(src)
  assert_eq(type_names(spec), ["Base", "User"])
  assert_eq(spec.types[1].embeds, ["Base"])
  assert_eq(
    contains(
      generate(spec),
      "pub(all) struct User {\n  id : Int64\n  name : String\n}",
    ),
    true,
  )
}
