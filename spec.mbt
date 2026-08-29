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
  if starts_with(t, "*") {
    return map_type(t[1:].to_owned()) + "?"
  }
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
/// optional summary. A modern goctl route (`verb /path (Req) returns (Resp)`)
/// also carries its request/response type names (its `@doc` fills `summary`);
/// both are empty for the legacy inline form (`verb /path handler "summary"`).
pub(all) struct Route {
  verb : String
  path : String
  handler : String
  summary : String
  req : String
  resp : String
}

///|
/// One field of a `type` block: its name, the (already MoonBit-mapped) type, and
/// the raw back-tick struct tag (`json:"…"`/`path`/`form`/`header`, empty when
/// absent) that carries the wire name and binding location.
pub(all) struct Field {
  name : String
  type_ : String
  tag : String
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
  info : Array[(String, String)]
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

///|
/// Index of the first occurrence of `needle` in `hay`, or `-1`.
fn index_of_str(hay : String, needle : String) -> Int {
  let hn = hay.length()
  let nn = needle.length()
  if nn == 0 {
    return 0
  }
  for i = 0; i + nn <= hn; i = i + 1 {
    let mut ok = true
    for j = 0; j < nn; j = j + 1 {
      if hay[i + j] != needle[j] {
        ok = false
        break
      }
    }
    if ok {
      return i
    }
  }
  -1
}

///|
/// The field's serialized name: the `json` struct-tag name (with any
/// `,optional`/`,omitempty` option stripped) when the tag carries one, else the
/// field's own name.
pub fn Field::json_name(self : Field) -> String {
  let key = "json:\""
  let at = index_of_str(self.tag, key)
  if at < 0 {
    return self.name
  }
  let start = at + key.length()
  let end = index_of(self.tag, '"', start)
  if end < 0 {
    return self.name
  }
  let raw = self.tag[start:end].to_owned()
  let comma = index_of(raw, ',', 0)
  if comma >= 0 {
    trim(raw[0:comma].to_owned())
  } else {
    trim(raw)
  }
}

///|
/// Parse one `type`-block field line into a `Field`. Accepts goctl's Go-struct
/// form `Name Type` and moonctl's colon form `name: type`, each with an optional
/// trailing back-tick struct tag. Returns `None` for a line with no `name type`
/// pair (an embedded type or stray token), which the caller skips.
fn parse_type_field(line : String) -> Field? {
  let mut decl = line
  let mut tag = ""
  let bt = index_of(line, '`', 0)
  if bt >= 0 {
    let close = index_of(line, '`', bt + 1)
    if close > bt {
      tag = line[bt + 1:close].to_owned()
      decl = trim(line[0:bt].to_owned())
    }
  }
  let colon = index_of(decl, ':', 0)
  if colon > 0 {
    let name = trim(decl[0:colon].to_owned())
    let type_ = map_type(decl[colon + 1:].to_owned())
    return Some({ name, type_, tag, })
  }
  let toks = tokens(decl)
  if toks.length() >= 2 {
    return Some({ name: toks[0], type_: map_type(toks[1]), tag, })
  }
  None
}

///|
pub fn parse(source : String) -> Spec {
  let mut service = "app"
  let routes : Array[Route] = []
  let types : Array[TypeDef] = []
  let info : Array[(String, String)] = []
  let mut current : TypeDef? = None
  let mut in_info = false
  let mut pending_handler = ""
  let mut pending_doc = ""
  for line in lines(source) {
    let s = trim(line)
    if s == "" || starts_with(s, "//") {
      continue
    }
    // An `info ( key: "value" … )` block (← goctl's `info(...)`): its members feed
    // the OpenAPI `info` object. `syntax = "v1"` is recorded and skipped so it is
    // not mistaken for a route.
    if in_info {
      if starts_with(s, ")") {
        in_info = false
      } else {
        let colon = index_of(s, ':', 0)
        if colon > 0 {
          let key = trim(s[0:colon].to_owned())
          let mut val = trim(s[colon + 1:].to_owned())
          if val.length() >= 2 && val[0] == '"' && val[val.length() - 1] == '"' {
            val = val[1:val.length() - 1].to_owned()
          }
          info.push((key, val))
        }
      }
      continue
    }
    if starts_with(s, "syntax") {
      continue
    }
    if starts_with(s, "info") && index_of(s, '(', 0) >= 0 {
      in_info = true
      continue
    }
    match current {
      Some(td) => {
        if s == "}" {
          types.push(td)
          current = None
        } else {
          match parse_type_field(s) {
            Some(f) => td.fields.push(f)
            None => ()
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
        current = Some({ name: toks[1], fields: [], })
      }
    } else if starts_with(s, "@doc") {
      let dq = index_of(s, '"', 0)
      if dq >= 0 {
        let close = index_of(s, '"', dq + 1)
        if close > dq {
          pending_doc = s[dq + 1:close].to_owned()
        }
      }
    } else if starts_with(s, "@handler") {
      let toks = tokens(s)
      if toks.length() >= 2 {
        pending_handler = toks[1]
      }
    } else if starts_with(s, "@") {
      // Other annotations (`@server(...)` groups, handled by the layered generator)
      // are not routes — skip so they are never mistaken for one.
      continue
    } else if s == "}" {
      continue
    } else {
      // A modern goctl route `verb /path (Req) returns (Resp)` carries typed
      // request/response and takes its handler/doc from the preceding
      // `@handler`/`@doc`; the legacy inline form is `verb /path handler "summary"`.
      let ret = index_of_str(s, "returns")
      let lp = index_of(s, '(', 0)
      if ret >= 0 && lp >= 0 && lp < ret {
        let head = tokens(s[0:lp].to_owned())
        if head.length() >= 2 {
          let rp = index_of(s, ')', lp + 1)
          let req = if rp > lp + 1 { trim(s[lp + 1:rp].to_owned()) } else { "" }
          let lp2 = index_of(s, '(', ret)
          let rp2 = if lp2 >= 0 { index_of(s, ')', lp2 + 1) } else { -1 }
          let resp = if lp2 >= 0 && rp2 > lp2 + 1 {
            trim(s[lp2 + 1:rp2].to_owned())
          } else {
            ""
          }
          let handler = if pending_handler != "" {
            pending_handler
          } else {
            head[0] + "_handler"
          }
          routes.push({
            verb: head[0],
            path: head[1],
            handler,
            summary: pending_doc,
            req,
            resp,
          })
          pending_handler = ""
          pending_doc = ""
        }
      } else {
        let toks = tokens(s)
        if toks.length() >= 3 {
          let summary = if toks.length() >= 4 { toks[3] } else { "" }
          routes.push({
            verb: toks[0],
            path: toks[1],
            handler: toks[2],
            summary,
            req: "",
            resp: "",
          })
        }
      }
    }
  }
  { service, routes, types, info, }
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
///
/// Pass `template` to render the spec through the runtime template engine (see
/// `generate_with`) instead of the built-in generator; omit it for the default
/// scaffold.
pub fn generate(spec : Spec, template? : String) -> String raise TemplateError {
  match template {
    Some(src) => generate_with(spec, src)
    None => generate_builtin(spec)
  }
}

///|
fn generate_builtin(spec : Spec) -> String {
  let mut out = "// Code generated by moonctl. DO NOT EDIT.\n\n"
  for t in spec.types {
    out = out +
      "///|\n/// `" +
      t.name +
      "` schema (generated from the `.api` `type` block).\npub(all) struct " +
      t.name +
      " {\n"
    for f in t.fields {
      out = out + "  " + to_snake(f.name) + " : " + f.type_ + "\n"
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
    // moonapi's `ApiHandler` is a *raising* fn-type, and under moonc 0.10.5 a pure
    // named fn no longer coerces to one. Register each handler through an arrow
    // closure — a closure infers the raise effect, so a stub that never raises and a
    // filled-in handler that raises an `HttpException` are both accepted unchanged.
    let handler = "ctx => " + r.handler + "(ctx)"
    let head = "  app." + r.verb + "(" + quote(r.path) + ", " + handler
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
