///|
test "snake_case conversion" {
  assert_eq(to_snake("SayHello"), "say_hello")
  assert_eq(to_snake("SayHelloAgain"), "say_hello_again")
  assert_eq(to_snake("HTTPServer"), "http_server")
  assert_eq(to_snake("Greeter"), "greeter")
  assert_eq(to_snake("already_snake"), "already_snake")
  assert_eq(to_snake("userID"), "user_id")
}

///|
test "parse a minimal .proto" {
  let src =
    #|syntax = "proto3";
    #|package greet;
    #|
    #|// the greeter service
    #|service Greeter {
    #|  rpc SayHello (HelloRequest) returns (HelloReply);
    #|  rpc LotsOfReplies (HelloRequest) returns (stream HelloReply);
    #|}
    #|
    #|message HelloRequest {
    #|  string name = 1;
    #|  int32  age  = 2;
    #|  repeated string tags = 3;
    #|}
    #|
    #|message HelloReply {
    #|  string message = 1;
    #|}
  let proto = parse_proto(src)
  assert_eq(proto.package_, "greet")
  assert_eq(proto.services.length(), 1)
  assert_eq(proto.messages.length(), 2)
  let svc = proto.services[0]
  assert_eq(svc.name, "Greeter")
  assert_eq(svc.rpcs.length(), 2)
  assert_eq(svc.rpcs[0].name, "SayHello")
  assert_eq(svc.rpcs[0].request, "HelloRequest")
  assert_eq(svc.rpcs[0].response, "HelloReply")
  assert_eq(svc.rpcs[0].server_streaming, false)
  assert_eq(svc.rpcs[1].name, "LotsOfReplies")
  assert_eq(svc.rpcs[1].server_streaming, true)
  let req = proto.messages[0]
  assert_eq(req.name, "HelloRequest")
  assert_eq(req.fields.length(), 3)
  assert_eq(req.fields[0].name, "name")
  assert_eq(req.fields[0].type_, "String")
  assert_eq(req.fields[1].type_, "Int")
  assert_eq(req.fields[2].type_, "Array[String]")
}

///|
test "parse proto map fields and client streaming" {
  let src =
    #|service Store {
    #|  rpc Upload (stream Chunk) returns (Ack);
    #|}
    #|message Chunk {
    #|  map<string, int64> meta = 1;
    #|  bytes data = 2;
    #|}
    #|message Ack { bool ok = 1; }
  let proto = parse_proto(src)
  assert_eq(proto.package_, "")
  assert_eq(proto.services[0].rpcs[0].client_streaming, true)
  assert_eq(proto.messages[0].fields[0].type_, "Map[String, Int64]")
  assert_eq(proto.messages[0].fields[1].type_, "Bytes")
  assert_eq(proto.messages[1].fields[0].type_, "Bool")
}

///|
test "generate moonrpc service stub" {
  let src =
    #|package greet;
    #|service Greeter {
    #|  rpc SayHello (HelloRequest) returns (HelloReply);
    #|}
    #|message HelloRequest { string name = 1; }
    #|message HelloReply { string message = 1; }
  let code = generate_grpc(parse_proto(src))
  assert_eq(contains(code, "DO NOT EDIT"), true)
  assert_eq(contains(code, "pub(all) struct HelloRequest {"), true)
  assert_eq(contains(code, "  name : String"), true)
  assert_eq(
    contains(
      code, "pub let greeter_say_hello : @moonrpc.Method = { service: \"greet.Greeter\", name: \"SayHello\" }",
    ),
    true,
  )
  assert_eq(contains(code, "pub(all) struct GreeterServer {"), true)
  assert_eq(
    contains(
      code, "say_hello : (HelloRequest) -> Result[HelloReply, @moonrpc.Status]",
    ),
    true,
  )
  assert_eq(
    contains(code, "pub fn greeter_methods() -> Array[@moonrpc.Method] {"),
    true,
  )
  assert_eq(contains(code, "[greeter_say_hello]"), true)
}

///|
test "parse a proto enum and generate a MoonBit enum with its int mapping" {
  let src =
    #|syntax = "proto3";
    #|package traffic;
    #|
    #|// a signal's phase
    #|enum Light {
    #|  LIGHT_UNKNOWN = 0;
    #|  RED = 1;
    #|  GREEN = 2;
    #|  YELLOW = 3;
    #|}
    #|message Signal { Light light = 1; }
  let proto = parse_proto(src)
  assert_eq(proto.enums.length(), 1)
  let en = proto.enums[0]
  assert_eq(en.name, "Light")
  assert_eq(en.values.length(), 4)
  assert_eq(en.values[0].name, "LIGHT_UNKNOWN")
  assert_eq(en.values[0].number, 0)
  assert_eq(en.values[2].name, "GREEN")
  assert_eq(en.values[2].number, 2)
  // an enum-typed message field passes the enum name through as its type
  assert_eq(proto.messages[0].fields[0].type_, "Light")
  let code = generate_grpc(proto)
  assert_eq(contains(code, "pub enum Light {"), true)
  assert_eq(contains(code, "  RED\n"), true)
  assert_eq(contains(code, "} derive(Eq, Debug)"), true)
  assert_eq(contains(code, "pub fn Light::to_int(self : Light) -> Int {"), true)
  assert_eq(contains(code, "    GREEN => 2"), true)
  assert_eq(contains(code, "pub fn Light::from_int(n : Int) -> Light {"), true)
  assert_eq(contains(code, "    _ => LIGHT_UNKNOWN"), true)
}

///|
test "generate streaming handler signatures" {
  let src =
    #|service Chat {
    #|  rpc Both (stream Msg) returns (stream Msg);
    #|}
    #|message Msg { string body = 1; }
  let code = generate_grpc(parse_proto(src))
  assert_eq(
    contains(code, "both : (Array[Msg]) -> Result[Array[Msg], @moonrpc.Status]"),
    true,
  )
}
