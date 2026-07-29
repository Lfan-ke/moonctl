///|
/// Convert an identifier to `snake_case` (← protobuf's PascalCase RPC/service
/// names, which must become MoonBit value names). An uppercase letter starts a
/// new word when it follows a lowercase letter or digit, or when it is followed
/// by a lowercase letter (so `HTTPServer` → `http_server`, `SayHello` →
/// `say_hello`). Existing underscores are preserved and the result is lowercased.
fn to_snake(s : String) -> String {
  let n = s.length()
  let mut r = ""
  for i = 0; i < n; i = i + 1 {
    let c = s[i].to_int()
    let is_upper = c >= 0x41 && c <= 0x5A
    if is_upper && i > 0 {
      let prev = s[i - 1].to_int()
      let prev_lower_or_digit = (prev >= 0x61 && prev <= 0x7A) ||
        (prev >= 0x30 && prev <= 0x39)
      let next_lower = i + 1 < n &&
        ({
          let nx = s[i + 1].to_int()
          nx >= 0x61 && nx <= 0x7A
        })
      if prev_lower_or_digit || next_lower {
        r = r + "_"
      }
    }
    r = r + s[i:i + 1].to_owned()
  }
  r.to_lower()
}

///|
/// Join `parts` with `", "` — the codegen workhorse for column/argument lists.
fn commas(parts : Array[String]) -> String {
  let mut out = ""
  for i = 0; i < parts.length(); i = i + 1 {
    if i > 0 {
      out = out + ", "
    }
    out = out + parts[i]
  }
  out
}

///|
/// Map a protobuf scalar type onto its MoonBit spelling (proto3 scalar set). An
/// unrecognised name is a message/enum reference and is passed through verbatim.
fn map_proto_type(raw : String) -> String {
  match raw {
    "double" => "Double"
    "float" => "Float"
    "int32" | "sint32" | "sfixed32" => "Int"
    "int64" | "sint64" | "sfixed64" => "Int64"
    "uint32" | "fixed32" => "UInt"
    "uint64" | "fixed64" => "UInt64"
    "bool" => "Bool"
    "string" => "String"
    "bytes" => "Bytes"
    _ => raw
  }
}

///|
/// One field of a protobuf `message`: its name and the (already MoonBit-mapped)
/// type. `repeated` becomes `Array[T]` and `map<K, V>` becomes `Map[K, V]`.
pub(all) struct ProtoField {
  name : String
  type_ : String
}

///|
/// A protobuf `oneof` group: its name and the members (exactly one may be set).
/// Generated into a MoonBit enum — the faithful equivalent of the "exactly one"
/// invariant, which flattening to optional fields would lose.
pub(all) struct ProtoOneof {
  name : String
  variants : Array[ProtoField]
}

///|
/// A protobuf `message` declaration, generated into a MoonBit struct. `oneof`
/// groups are lifted out of `fields` into `oneofs`.
pub(all) struct ProtoMessage {
  name : String
  fields : Array[ProtoField]
  oneofs : Array[ProtoOneof]
}

///|
/// Capitalise the first letter (a protobuf `field_name` becomes a MoonBit enum
/// variant `Field_name`, which must start uppercase).
fn cap_first(s : String) -> String {
  if s.length() == 0 {
    return s
  }
  let c = s[0].to_int()
  if c >= 0x61 && c <= 0x7A {
    (c - 0x20).to_byte().to_char().to_string() + s[1:].to_owned()
  } else {
    s
  }
}

///|
/// One value of a protobuf `enum`: its name and its integer number.
pub(all) struct ProtoEnumValue {
  name : String
  number : Int
}

///|
/// A protobuf `enum` declaration, generated into a MoonBit enum plus an integer
/// mapping (proto3 enums are int-backed, and the value numbered `0` is the
/// default).
pub(all) struct ProtoEnum {
  name : String
  values : Array[ProtoEnumValue]
}

///|
/// One `rpc` method of a service: its name, request and response message names,
/// and whether either side is a `stream` (client/server/bidi streaming).
pub(all) struct Rpc {
  name : String
  request : String
  response : String
  client_streaming : Bool
  server_streaming : Bool
}

///|
/// A protobuf `service` declaration and its RPC methods.
pub(all) struct ProtoService {
  name : String
  rpcs : Array[Rpc]
}

///|
/// A parsed `.proto` file: its `package` (empty when none) and the services and
/// messages it declares.
pub(all) struct Proto {
  package_ : String
  services : Array[ProtoService]
  messages : Array[ProtoMessage]
  enums : Array[ProtoEnum]
}

///|
/// Tokenise a `.proto` source: whitespace-separated words plus the single-char
/// punctuation `{ } ( ) < > ; = ,` as their own tokens, with `//` line comments
/// and `/* … */` block comments stripped and `"…"` string literals kept whole.
fn proto_tokens(src : String) -> Array[String] {
  let out : Array[String] = []
  let n = src.length()
  let mut i = 0
  while i < n {
    let c = src[i]
    if is_ws(c) {
      i = i + 1
      continue
    }
    if c == '/' && i + 1 < n && src[i + 1] == '/' {
      while i < n && src[i] != '\n' {
        i = i + 1
      }
      continue
    }
    if c == '/' && i + 1 < n && src[i + 1] == '*' {
      i = i + 2
      while i + 1 < n && !(src[i] == '*' && src[i + 1] == '/') {
        i = i + 1
      }
      i = i + 2
      continue
    }
    if c == '"' {
      let start = i
      i = i + 1
      while i < n && src[i] != '"' {
        i = i + 1
      }
      i = i + 1
      out.push(src[start:i].to_owned())
      continue
    }
    if c == '{' ||
      c == '}' ||
      c == '(' ||
      c == ')' ||
      c == '<' ||
      c == '>' ||
      c == ';' ||
      c == '=' ||
      c == ',' {
      out.push(src[i:i + 1].to_owned())
      i = i + 1
      continue
    }
    let start = i
    while i < n {
      let d = src[i]
      if is_ws(d) ||
        d == '{' ||
        d == '}' ||
        d == '(' ||
        d == ')' ||
        d == '<' ||
        d == '>' ||
        d == ';' ||
        d == '=' ||
        d == ',' ||
        d == '"' {
        break
      }
      i = i + 1
    }
    out.push(src[start:i].to_owned())
  }
  out
}

///|
/// Index just past the next `;` at or after `i` (used to skip a statement).
fn skip_to_semi(toks : Array[String], i : Int) -> Int {
  let n = toks.length()
  let mut j = i
  while j < n && toks[j] != ";" {
    j = j + 1
  }
  j + 1
}

///|
/// Given `toks[i] == "{"`, index just past its matching `}` (brace-balanced).
fn skip_braced(toks : Array[String], i : Int) -> Int {
  let n = toks.length()
  let mut depth = 0
  let mut j = i
  while j < n {
    if toks[j] == "{" {
      depth = depth + 1
    } else if toks[j] == "}" {
      depth = depth - 1
      if depth == 0 {
        return j + 1
      }
    }
    j = j + 1
  }
  j
}

///|
/// Parse a `message` block starting at `toks[start] == "message"`. Returns the
/// message and the index just past its closing `}`. Handles scalar/message
/// fields, `repeated`, `map<K, V>`, `optional`/`required`, and `oneof` (its
/// members flattened to fields). Nested `message` / `enum` declarations are
/// hoisted into `out_messages` / `out_enums` (MoonBit has no nested types), by
/// their simple names; `reserved` and `option` lines are skipped.
fn parse_message(
  toks : Array[String],
  start : Int,
  out_messages : Array[ProtoMessage],
  out_enums : Array[ProtoEnum],
) -> (ProtoMessage, Int) {
  let n = toks.length()
  let name = if start + 1 < n { toks[start + 1] } else { "Unnamed" }
  let fields : Array[ProtoField] = []
  let oneofs : Array[ProtoOneof] = []
  let mut i = start + 2
  if i < n && toks[i] == "{" {
    i = i + 1
  }
  while i < n && toks[i] != "}" {
    let t = toks[i]
    if t == "reserved" || t == "option" {
      i = skip_to_semi(toks, i)
      continue
    }
    if t == "message" {
      let (nested, ni) = parse_message(toks, i, out_messages, out_enums)
      out_messages.push(nested)
      i = ni
      continue
    }
    if t == "enum" {
      let (nested, ni) = parse_enum(toks, i)
      out_enums.push(nested)
      i = ni
      continue
    }
    if t == "oneof" {
      let oneof_name = if i + 1 < n { toks[i + 1] } else { "oneof" }
      i = i + 2
      if i < n && toks[i] == "{" {
        i = i + 1
      }
      let variants : Array[ProtoField] = []
      while i < n && toks[i] != "}" {
        let (f, ni) = parse_field(toks, i)
        match f {
          Some(field) => variants.push(field)
          None => ()
        }
        i = ni
      }
      i = i + 1
      oneofs.push({ name: oneof_name, variants })
      continue
    }
    let (f, ni) = parse_field(toks, i)
    match f {
      Some(field) => fields.push(field)
      None => ()
    }
    i = ni
  }
  i = i + 1
  ({ name, fields, oneofs }, i)
}

///|
/// Parse a single message field statement (`[repeated] Type name = N ;` or
/// `map<K, V> name = N ;`) starting at `i`; returns the field (or `None` if the
/// line is not a field) and the index just past its `;`.
fn parse_field(toks : Array[String], i : Int) -> (ProtoField?, Int) {
  let n = toks.length()
  if i >= n {
    return (None, n)
  }
  if toks[i] == "map" {
    let mut j = i + 1
    if j < n && toks[j] == "<" {
      j = j + 1
    }
    let k = if j < n { toks[j] } else { "string" }
    j = j + 1
    if j < n && toks[j] == "," {
      j = j + 1
    }
    let v = if j < n { toks[j] } else { "string" }
    j = j + 1
    if j < n && toks[j] == ">" {
      j = j + 1
    }
    let fname = if j < n { toks[j] } else { "field" }
    let end = skip_to_semi(toks, j)
    let type_ = "Map[" + map_proto_type(k) + ", " + map_proto_type(v) + "]"
    return (Some({ name: fname, type_ }), end)
  }
  let mut j = i
  let mut repeated = false
  if toks[j] == "repeated" {
    repeated = true
    j = j + 1
  } else if toks[j] == "optional" || toks[j] == "required" {
    j = j + 1
  }
  if j + 1 >= n {
    return (None, skip_to_semi(toks, i))
  }
  let ptype = toks[j]
  let fname = toks[j + 1]
  let end = skip_to_semi(toks, j + 1)
  let mapped = map_proto_type(ptype)
  let type_ = if repeated { "Array[" + mapped + "]" } else { mapped }
  (Some({ name: fname, type_ }), end)
}

///|
/// Parse a `service` block starting at `toks[start] == "service"`. Returns the
/// service and the index just past its closing `}`.
fn parse_service(toks : Array[String], start : Int) -> (ProtoService, Int) {
  let n = toks.length()
  let name = if start + 1 < n { toks[start + 1] } else { "Unnamed" }
  let rpcs : Array[Rpc] = []
  let mut i = start + 2
  if i < n && toks[i] == "{" {
    i = i + 1
  }
  while i < n && toks[i] != "}" {
    if toks[i] == "rpc" {
      let mname = if i + 1 < n { toks[i + 1] } else { "Unnamed" }
      let mut j = i + 2
      if j < n && toks[j] == "(" {
        j = j + 1
      }
      let mut client_streaming = false
      if j < n && toks[j] == "stream" {
        client_streaming = true
        j = j + 1
      }
      let request = if j < n { toks[j] } else { "Unit" }
      j = j + 1
      if j < n && toks[j] == ")" {
        j = j + 1
      }
      if j < n && toks[j] == "returns" {
        j = j + 1
      }
      if j < n && toks[j] == "(" {
        j = j + 1
      }
      let mut server_streaming = false
      if j < n && toks[j] == "stream" {
        server_streaming = true
        j = j + 1
      }
      let response = if j < n { toks[j] } else { "Unit" }
      j = j + 1
      if j < n && toks[j] == ")" {
        j = j + 1
      }
      rpcs.push({
        name: mname,
        request,
        response,
        client_streaming,
        server_streaming,
      })
      i = if j < n && toks[j] == "{" {
        skip_braced(toks, j)
      } else {
        skip_to_semi(toks, j)
      }
    } else if toks[i] == "option" {
      i = skip_to_semi(toks, i)
    } else {
      i = i + 1
    }
  }
  i = i + 1
  ({ name, rpcs }, i)
}

///|
/// Parse a leading-digit integer token (an enum value's number), stopping at the
/// first non-digit; `0` when there are no digits. Handles a leading `-`.
fn proto_int(s : String) -> Int {
  let mut acc = 0
  let mut neg = false
  let mut k = 0
  if s.length() > 0 && s[0] == '-' {
    neg = true
    k = 1
  }
  while k < s.length() {
    let c = s[k].to_int()
    if c < 0x30 || c > 0x39 {
      break
    }
    acc = acc * 10 + (c - 0x30)
    k = k + 1
  }
  if neg {
    -acc
  } else {
    acc
  }
}

///|
/// Parse an `enum` block starting at `toks[start] == "enum"`. Returns the enum and
/// the index just past its closing `}`. Each `NAME = NUMBER ;` becomes a value;
/// `option` and `reserved` lines inside the block are skipped.
fn parse_enum(toks : Array[String], start : Int) -> (ProtoEnum, Int) {
  let n = toks.length()
  let name = if start + 1 < n { toks[start + 1] } else { "Unnamed" }
  let values : Array[ProtoEnumValue] = []
  let mut i = start + 2
  if i < n && toks[i] == "{" {
    i = i + 1
  }
  while i < n && toks[i] != "}" {
    let t = toks[i]
    if t == "option" || t == "reserved" {
      i = skip_to_semi(toks, i)
      continue
    }
    let mut j = i + 1
    if j < n && toks[j] == "=" {
      j = j + 1
    }
    let number = if j < n { proto_int(toks[j]) } else { 0 }
    values.push({ name: t, number })
    i = skip_to_semi(toks, i)
  }
  i = i + 1
  ({ name, values }, i)
}

///|
/// Parse a minimal `.proto` (proto3). Recognises the `package` declaration,
/// `service` blocks with their `rpc` methods (including `stream`), `message`
/// blocks with scalar/`repeated`/`map` fields, and top-level `enum` declarations.
/// `syntax`, `import`, and `option` are skipped.
///
/// ```
/// syntax = "proto3";
/// package greet;
/// service Greeter {
///   rpc SayHello (HelloRequest) returns (HelloReply);
/// }
/// message HelloRequest { string name = 1; }
/// message HelloReply   { string message = 1; }
/// ```
pub fn parse_proto(source : String) -> Proto {
  let toks = proto_tokens(source)
  let n = toks.length()
  let mut package_ = ""
  let services : Array[ProtoService] = []
  let messages : Array[ProtoMessage] = []
  let enums : Array[ProtoEnum] = []
  let mut i = 0
  while i < n {
    let t = toks[i]
    if t == "package" {
      let mut name = ""
      i = i + 1
      while i < n && toks[i] != ";" {
        name = name + toks[i]
        i = i + 1
      }
      package_ = name
      i = i + 1
    } else if t == "syntax" || t == "import" || t == "option" {
      i = skip_to_semi(toks, i)
    } else if t == "service" {
      let (svc, ni) = parse_service(toks, i)
      services.push(svc)
      i = ni
    } else if t == "message" {
      let (msg, ni) = parse_message(toks, i, messages, enums)
      messages.push(msg)
      i = ni
    } else if t == "enum" {
      let (en, ni) = parse_enum(toks, i)
      enums.push(en)
      i = ni
    } else {
      i = i + 1
    }
  }
  { package_, services, messages, enums }
}

///|
/// The gRPC handler input type for an RPC (its request, or `Array[Request]` when
/// the client streams).
fn rpc_in(r : Rpc) -> String {
  if r.client_streaming {
    "Array[" + r.request + "]"
  } else {
    r.request
  }
}

///|
/// The gRPC handler output type for an RPC (its reply, or `Array[Reply]` when the
/// server streams).
fn rpc_out(r : Rpc) -> String {
  if r.server_streaming {
    "Array[" + r.response + "]"
  } else {
    r.response
  }
}

///|
/// Generate a moonrpc service stub from a parsed `.proto`: a MoonBit struct per
/// `message`, a `@moonrpc.Method` descriptor per RPC (its gRPC `:path` is
/// `/package.Service/Method`), a `<Service>Server` handler-registration struct
/// (one synchronous-core handler field per RPC, each returning its reply or a
/// gRPC `@moonrpc.Status`), and a `<service>_methods()` listing. The output
/// compiles against `Lfan-ke/moonrpc`.
pub fn generate_grpc(proto : Proto) -> String {
  let mut out = "// Code generated by moonctl. DO NOT EDIT.\n\n"
  for e in proto.enums {
    out = out +
      "///|\n/// `" +
      e.name +
      "` enum (generated from the `.proto` `enum` block).\npub enum " +
      e.name +
      " {\n"
    for v in e.values {
      out = out + "  " + v.name + "\n"
    }
    out = out + "} derive(Eq, Debug)\n\n"
    out = out +
      "///|\n/// The protobuf number for a `" +
      e.name +
      "` value.\npub fn " +
      e.name +
      "::to_int(self : " +
      e.name +
      ") -> Int {\n  match self {\n"
    for v in e.values {
      out = out + "    " + v.name + " => " + v.number.to_string() + "\n"
    }
    out = out + "  }\n}\n\n"
    let default_name = if e.values.length() > 0 {
      e.values[0].name
    } else {
      "Unknown"
    }
    out = out +
      "///|\n/// The `" +
      e.name +
      "` value for a protobuf number, defaulting to the zero value.\npub fn " +
      e.name +
      "::from_int(n : Int) -> " +
      e.name +
      " {\n  match n {\n"
    for v in e.values {
      out = out + "    " + v.number.to_string() + " => " + v.name + "\n"
    }
    out = out + "    _ => " + default_name + "\n  }\n}\n\n"
  }
  for m in proto.messages {
    // A oneof becomes a union enum (exactly one variant set), defined before the
    // struct that carries it.
    for o in m.oneofs {
      let ename = m.name + cap_first(o.name)
      out = out +
        "///|\n/// `" +
        m.name +
        "." +
        o.name +
        "` oneof: exactly one variant is set.\npub enum " +
        ename +
        " {\n"
      for v in o.variants {
        out = out + "  " + cap_first(v.name) + "(" + v.type_ + ")\n"
      }
      out = out + "} derive(Eq, Debug)\n\n"
    }
    out = out +
      "///|\n/// `" +
      m.name +
      "` message (generated from the `.proto` `message` block).\npub(all) struct " +
      m.name +
      " {\n"
    for f in m.fields {
      out = out + "  " + f.name + " : " + f.type_ + "\n"
    }
    for o in m.oneofs {
      out = out + "  " + o.name + " : " + m.name + cap_first(o.name) + "\n"
    }
    out = out + "}\n\n"
  }
  for s in proto.services {
    let full = if proto.package_ == "" {
      s.name
    } else {
      proto.package_ + "." + s.name
    }
    let svc = to_snake(s.name)
    for r in s.rpcs {
      let dname = svc + "_" + to_snake(r.name)
      out = out +
        "///|\n/// gRPC method descriptor for `" +
        full +
        "/" +
        r.name +
        "` (`:path` = " +
        quote("/" + full + "/" + r.name) +
        ").\npub let " +
        dname +
        " : @moonrpc.Method = { service: " +
        quote(full) +
        ", name: " +
        quote(r.name) +
        " }\n\n"
    }
    out = out +
      "///|\n/// The `" +
      full +
      "` service: one handler per RPC (synchronous core). Each handler takes its\n/// request (an `Array` when the client streams) and returns its reply (an\n/// `Array` when the server streams) or a gRPC `@moonrpc.Status` on failure.\npub(all) struct " +
      s.name +
      "Server {\n"
    for r in s.rpcs {
      out = out +
        "  " +
        to_snake(r.name) +
        " : (" +
        rpc_in(r) +
        ") -> Result[" +
        rpc_out(r) +
        ", @moonrpc.Status]\n"
    }
    out = out + "}\n\n"
    let names : Array[String] = []
    for r in s.rpcs {
      names.push(svc + "_" + to_snake(r.name))
    }
    out = out +
      "///|\n/// Every method descriptor in `" +
      full +
      "`, in declaration order.\npub fn " +
      svc +
      "_methods() -> Array[@moonrpc.Method] {\n  [" +
      commas(names) +
      "]\n}\n\n"
  }
  out
}
