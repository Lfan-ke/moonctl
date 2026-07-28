///|
test "generate moonorm model + table" {
  let src =
    #|type User {
    #|  id:    int64
    #|  name:  string
    #|  admin: bool
    #|}
    #|
    #|service greet {
    #|  get /users/:id get_user
    #|}
  let code = generate_model(parse(src))
  assert_eq(contains(code, "DO NOT EDIT"), true)
  assert_eq(contains(code, "pub(all) struct User {"), true)
  assert_eq(contains(code, "  id : Int64"), true)
  assert_eq(contains(code, "  admin : Bool"), true)
  assert_eq(contains(code, "pub let user_table : @moonorm.Table = {"), true)
  assert_eq(contains(code, "name: \"user\","), true)
  assert_eq(contains(code, "columns: [\"id\", \"name\", \"admin\"],"), true)
  // every column is a mappable storage class -> a from_row decoder is emitted
  assert_eq(
    contains(code, "pub fn User::from_row(row : @moonorm.Row) -> User {"),
    true,
  )
  assert_eq(
    contains(code, "id: (match row.int64(0) { Some(v) => v; None => 0L }),"),
    true,
  )
  assert_eq(
    contains(code, "name: (match row.text(1) { Some(v) => v; None => \"\" }),"),
    true,
  )
  assert_eq(
    contains(
      code, "admin: (match row.int(2) { Some(v) => v != 0; None => false }),",
    ),
    true,
  )
}

///|
test "table name and columns are snake-cased" {
  let src =
    #|type BlogPost {
    #|  postID:    int64
    #|  authorName: string
    #|}
  let code = generate_model(parse(src))
  assert_eq(contains(code, "pub let blog_post_table : @moonorm.Table"), true)
  assert_eq(contains(code, "name: \"blog_post\","), true)
  assert_eq(contains(code, "columns: [\"post_id\", \"author_name\"],"), true)
}

///|
test "non-mappable field omits from_row but keeps struct + table" {
  let src =
    #|type Doc {
    #|  id:   int64
    #|  tags: []string
    #|}
  let code = generate_model(parse(src))
  assert_eq(contains(code, "pub(all) struct Doc {"), true)
  assert_eq(contains(code, "  tags : Array[String]"), true)
  assert_eq(contains(code, "pub let doc_table : @moonorm.Table"), true)
  // Array[String] has no single Row accessor -> no from_row generated
  assert_eq(contains(code, "Doc::from_row"), false)
}
