///|
fn is_ws(c : UInt16) -> Bool {
  c == ' ' || c == '\t' || c == '\r' || c == '\n'
}

///|
fn trim(s : String) -> String {
  let n = s.length()
  let mut a = 0
  let mut b = n
  while a < b && is_ws(s[a]) {
    a = a + 1
  }
  while b > a && is_ws(s[b - 1]) {
    b = b - 1
  }
  s[a:b].to_owned()
}

///|
fn lines(s : String) -> Array[String] {
  let out : Array[String] = []
  let n = s.length()
  let mut start = 0
  for i = 0; i <= n; i = i + 1 {
    if i == n || s[i] == '\n' {
      out.push(s[start:i].to_owned())
      start = i + 1
    }
  }
  out
}

///|
fn starts_with(s : String, prefix : String) -> Bool {
  let pn = prefix.length()
  if s.length() < pn {
    return false
  }
  for i = 0; i < pn; i = i + 1 {
    if s[i] != prefix[i] {
      return false
    }
  }
  true
}

///|
/// Index of the first `ch` in `s` at or after `from`, or `-1` if absent.
fn index_of(s : String, ch : UInt16, from : Int) -> Int {
  let n = s.length()
  for i = from; i < n; i = i + 1 {
    if s[i] == ch {
      return i
    }
  }
  -1
}

///|
/// Map a `.api` field type onto its MoonBit spelling (← goctl's Go type set):
/// scalars (`string`→`String`, `int`→`Int`, `int64`→`Int64`, …), slices
/// (`[]T`→`Array[T]`), and maps (`map[K]V`→`Map[K, V]`). An unrecognised name is
/// passed through verbatim, so a spec may already reference a MoonBit type or one
/// of its own `type` blocks.
fn map_type(raw : String) -> String {
  let t = trim(raw)
  if starts_with(t, "[]") {
    return "Array[" + map_type(t[2:].to_owned()) + "]"
  }
  if starts_with(t, "map[") {
    let close = index_of(t, ']', 4)
    if close > 4 {
      let key = t[4:close].to_owned()
      let value = t[close + 1:].to_owned()
      return "Map[" + map_type(key) + ", " + map_type(value) + "]"
    }
  }
  match t {
    "string" => "String"
    "bool" => "Bool"
    "int" | "int8" | "int16" | "int32" | "rune" => "Int"
    "int64" => "Int64"
    "uint" | "uint8" | "uint16" | "uint32" => "UInt"
    "uint64" => "UInt64"
    "byte" => "Byte"
    "bytes" => "Bytes"
    "float32" => "Float"
    "float" | "float64" | "double" => "Double"
    _ => t
  }
}

///|
/// Whitespace-split a line into tokens, keeping a `"quoted string"` as one token
/// (with the quotes stripped).
fn tokens(s : String) -> Array[String] {
  let out : Array[String] = []
  let n = s.length()
  let mut i = 0
  while i < n {
    while i < n && is_ws(s[i]) {
      i = i + 1
    }
    if i >= n {
      break
    }
    if s[i] == '"' {
      let start = i + 1
      let mut j = start
      while j < n && s[j] != '"' {
        j = j + 1
      }
      out.push(s[start:j].to_owned())
      i = j + 1
    } else {
      let start = i
      while i < n && is_ws(s[i]) == false {
        i = i + 1
      }
      out.push(s[start:i].to_owned())
    }
  }
  out
}

///|
/// One route in a service spec: HTTP verb, path pattern, handler name, and an
/// optional summary.
pub(all) struct Route {
  verb : String
  path : String
  handler : String
  summary : String
}

///|
/// One field of a `type` block: its name and the (already MoonBit-mapped) type.
pub(all) struct Field {
  name : String
  type_ : String
}

///|
/// A named message schema declared by a `type Name { field: Type … }` block,
/// generated into a MoonBit struct (goctl's request/response types).
pub(all) struct TypeDef {
  name : String
  fields : Array[Field]
}

///|
/// A parsed `.api` service specification.
pub(all) struct Spec {
  service : String
  routes : Array[Route]
  types : Array[TypeDef]
}

///|
/// Parse a `.api` service spec. Grammar (one statement per line):
/// ```
/// service greet {
///   get  /ping        ping        "health check"
///   get  /users/:id   get_user
///   post /users        create_user "create a user"
/// }
///
/// type User {
///   id:   int64
///   name: string
/// }
/// ```
/// A `type` block declares a message schema (its fields become a MoonBit struct);
/// field types use goctl's Go spellings (`string`, `int64`, `[]T`, `map[K]V`, …).
/// Blank lines and `//` comments are ignored.
pub fn parse(source : String) -> Spec {
  let mut service = "app"
  let routes : Array[Route] = []
  let types : Array[TypeDef] = []
  let mut current : TypeDef? = None
  for line in lines(source) {
    let s = trim(line)
    if s == "" || starts_with(s, "//") {
      continue
    }
    match current {
      Some(td) => {
        if s == "}" {
          types.push(td)
          current = None
        } else {
          let colon = index_of(s, ':', 0)
          if colon > 0 {
            let name = trim(s[0:colon].to_owned())
            let type_ = map_type(s[colon + 1:].to_owned())
            td.fields.push({ name, type_ })
          }
        }
        continue
      }
      None => ()
    }
    if starts_with(s, "service ") {
      let toks = tokens(s)
      if toks.length() >= 2 {
        service = toks[1]
      }
    } else if starts_with(s, "type ") {
      let toks = tokens(s)
      if toks.length() >= 2 {
        current = Some({ name: toks[1], fields: [] })
      }
    } else if s == "}" {
      continue
    } else {
      let toks = tokens(s)
      if toks.length() >= 3 {
        let summary = if toks.length() >= 4 { toks[3] } else { "" }
        routes.push({ verb: toks[0], path: toks[1], handler: toks[2], summary })
      }
    }
  }
  { service, routes, types }
}

///|
fn quote(s : String) -> String {
  "\"" + s + "\""
}

///|
/// Generate compilable moonapi scaffolding from a spec: a MoonBit struct for
/// every `type` block, a `build_app` that wires every route to its handler, plus
/// a stub for each handler. The routing part depends only on `Lfan-ke/moonapi`
/// and `Lfan-ke/moonasgi`; the emitted schemas are dependency-free.
pub fn generate(spec : Spec) -> String {
  let mut out = "// Code generated by moonctl. DO NOT EDIT.\n\n"
  for t in spec.types {
    out = out +
      "///|\n/// `" +
      t.name +
      "` schema (generated from the `.api` `type` block).\npub(all) struct " +
      t.name +
      " {\n"
    for f in t.fields {
      out = out + "  " + f.name + " : " + f.type_ + "\n"
    }
    out = out + "}\n\n"
  }
  out = out +
    "///|\n/// Build the " +
    spec.service +
    " application with its routes wired to handlers.\n"
  out = out + "pub fn build_app() -> @moonapi.App {\n"
  out = out + "  let app = @moonapi.App::new()\n"
  for r in spec.routes {
    let head = "  app." + r.verb + "(" + quote(r.path) + ", " + r.handler
    out = out +
      (if r.summary != "" {
        head + ", summary=" + quote(r.summary) + ")\n"
      } else {
        head + ")\n"
      })
  }
  out = out + "  app\n}\n\n"
  for r in spec.routes {
    out = out +
      "///|\npub fn " +
      r.handler +
      "(_ctx : @moonapi.Context) -> @moonasgi.Response {\n  @moonapi.text(200, " +
      quote("TODO: " + r.handler) +
      ")\n}\n\n"
  }
  out
}
