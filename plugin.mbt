// The plugin protocol: mctl hands a parsed spec to an external program and writes
// back the files it returns. goctl's `api plugin` does the same — it serialises the
// parsed API to JSON, runs the plugin as a subprocess, and the plugin emits code.
// Here the contract is symmetric and explicit: the request is the `Spec` as JSON on
// the plugin's stdin, the reply is a JSON list of `{path, content}` files on its
// stdout, which mctl writes out. The wire shapes and their (de)serialisers live here,
// in pure all-backend code; only the subprocess spawn (in the `mctl` binary) is
// native.

///|
/// One file a plugin asks mctl to write: a destination `path` (relative to the
/// output directory) and its full `content`.
pub(all) struct GenFile {
  path : String
  content : String
}

///|
/// A `Group` as JSON: the `@server` annotations under goctl's own key names, with
/// the group name under `name`.
fn group_to_json(g : Group) -> Json {
  let extra : Array[Json] = []
  for kv in g.extra {
    let m : Map[String, Json] = Map([
      ("name", kv.0.to_json()),
      ("value", kv.1.to_json()),
    ])
    extra.push(m.to_json())
  }
  let m : Map[String, Json] = Map([
    ("name", g.name.to_json()),
    ("prefix", g.prefix.to_json()),
    ("jwt", g.jwt.to_json()),
    ("middleware", g.middleware.to_json()),
    ("maxBytes", g.max_bytes.to_double().to_json()),
    ("timeout", g.timeout.to_json()),
    ("signature", g.signature.to_json()),
    ("extra", extra.to_json()),
  ])
  m.to_json()
}

///|
/// Serialise a `Spec` into the plugin request JSON. The shape mirrors the `Spec`
/// itself — `service`, `routes` (`verb`/`path`/`handler`/`summary`, plus the
/// `group` the route was declared under), `types` (`name` plus `fields` of
/// `name`/`type`) and `groups` — so a plugin in any language parses it with an
/// ordinary JSON reader. `type_` is written as `type`, the name a caller expects.
pub fn spec_to_json(spec : Spec) -> Json {
  let routes : Array[Json] = []
  for r in spec.routes {
    let m : Map[String, Json] = Map([
      ("verb", r.verb.to_json()),
      ("path", r.path.to_json()),
      ("handler", r.handler.to_json()),
      ("summary", r.summary.to_json()),
      ("req", r.req.to_json()),
      ("resp", r.resp.to_json()),
    ])
    match r.group {
      Some(g) => m["group"] = group_to_json(g)
      None => ()
    }
    routes.push(m.to_json())
  }
  let types : Array[Json] = []
  for t in spec.types {
    let fields : Array[Json] = []
    for f in t.fields {
      let fm : Map[String, Json] = Map([
        ("name", f.name.to_json()),
        ("type", f.type_.to_json()),
        ("tag", f.tag.to_json()),
      ])
      fields.push(fm.to_json())
    }
    let tm : Map[String, Json] = Map([
      ("name", t.name.to_json()),
      ("fields", fields.to_json()),
    ])
    types.push(tm.to_json())
  }
  let info : Array[Json] = []
  for kv in spec.info {
    let m : Map[String, Json] = Map([
      ("name", kv.0.to_json()),
      ("value", kv.1.to_json()),
    ])
    info.push(m.to_json())
  }
  let groups : Array[Json] = []
  for g in spec.groups {
    groups.push(group_to_json(g))
  }
  let doc : Map[String, Json] = Map([
    ("service", spec.service.to_json()),
    ("routes", routes.to_json()),
    ("types", types.to_json()),
    ("info", info.to_json()),
    ("groups", groups.to_json()),
  ])
  doc.to_json()
}

///|
/// The plugin request as a two-space-indented JSON string, ready to write to the
/// plugin's stdin.
pub fn plugin_request(spec : Spec) -> String {
  spec_to_json(spec).stringify(indent=2)
}

///|
/// A `Group` read back from the request JSON, or `None` when the member is absent
/// or is not an object.
fn group_from_json(j : Json?) -> Group? {
  let m = match j {
    Some(Object(m)) => m
    _ => return None
  }
  let middleware : Array[String] = []
  match m.get("middleware") {
    Some(Array(a)) =>
      for it in a {
        match it {
          String(s) => middleware.push(s)
          _ => ()
        }
      }
    _ => ()
  }
  let extra : Array[(String, String)] = []
  match m.get("extra") {
    Some(Array(a)) =>
      for it in a {
        match it {
          Object(em) =>
            extra.push((json_str(em, "name"), json_str(em, "value")))
          _ => ()
        }
      }
    _ => ()
  }
  let max_bytes = match m.get("maxBytes") {
    Some(Number(n, ..)) => n.to_int64()
    Some(String(s)) =>
      match to_i64(s) {
        Some(v) => v
        None => 0L
      }
    _ => 0L
  }
  let signature = match m.get("signature") {
    Some(True) => true
    _ => false
  }
  Some({
    name: json_str(m, "name"),
    prefix: json_str(m, "prefix"),
    jwt: json_str(m, "jwt"),
    middleware,
    max_bytes,
    timeout: json_str(m, "timeout"),
    signature,
    extra,
  })
}

///|
/// Reconstruct a `Spec` from the request JSON — the reader a plugin written in
/// MoonBit uses on its stdin. Missing or mistyped members degrade to empty rather
/// than raising, so a partial request still parses.
pub fn spec_from_json(j : Json) -> Spec {
  let service = match j {
    Object(m) =>
      match m.get("service") {
        Some(String(s)) => s
        _ => "app"
      }
    _ => "app"
  }
  let routes : Array[Route] = []
  let types : Array[TypeDef] = []
  let info : Array[(String, String)] = []
  let groups : Array[Group] = []
  match j {
    Object(m) => {
      match m.get("groups") {
        Some(Array(arr)) =>
          for item in arr {
            match group_from_json(Some(item)) {
              Some(g) => groups.push(g)
              None => ()
            }
          }
        _ => ()
      }
      match m.get("routes") {
        Some(Array(arr)) =>
          for item in arr {
            match item {
              Object(rm) =>
                routes.push({
                  verb: json_str(rm, "verb"),
                  path: json_str(rm, "path"),
                  handler: json_str(rm, "handler"),
                  summary: json_str(rm, "summary"),
                  req: json_str(rm, "req"),
                  resp: json_str(rm, "resp"),
                  group: group_from_json(rm.get("group")),
                })
              _ => ()
            }
          }
        _ => ()
      }
      match m.get("types") {
        Some(Array(arr)) =>
          for item in arr {
            match item {
              Object(tm) => {
                let fields : Array[Field] = []
                match tm.get("fields") {
                  Some(Array(fa)) =>
                    for f in fa {
                      match f {
                        Object(fm) =>
                          fields.push({
                            name: json_str(fm, "name"),
                            type_: json_str(fm, "type"),
                            tag: json_str(fm, "tag"),
                          })
                        _ => ()
                      }
                    }
                  _ => ()
                }
                types.push({ name: json_str(tm, "name"), fields, })
              }
              _ => ()
            }
          }
        _ => ()
      }
      match m.get("info") {
        Some(Array(arr)) =>
          for item in arr {
            match item {
              Object(im) =>
                info.push((json_str(im, "name"), json_str(im, "value")))
              _ => ()
            }
          }
        _ => ()
      }
    }
    _ => ()
  }
  // A plugin is handed a spec whose imports have already been merged in, so the
  // request carries no import list to read back.
  { service, routes, types, info, groups, imports: [], }
}

///|
/// Read a string member of a JSON object, or `""` if absent or non-string.
fn json_str(m : Map[String, Json], key : String) -> String {
  match m.get(key) {
    Some(String(s)) => s
    _ => ""
  }
}

///|
/// Parse a plugin's stdout into the files to write. Two shapes are accepted: a bare
/// array `[{path, content}, …]`, or an object `{"files": [ … ]}` (goctl-style
/// envelope). An element missing `path` or `content` is skipped. The list preserves
/// the plugin's order.
pub fn parse_gen_files(j : Json) -> Array[GenFile] {
  let out : Array[GenFile] = []
  let arr = match j {
    Array(a) => a
    Object(m) =>
      match m.get("files") {
        Some(Array(a)) => a
        _ => []
      }
    _ => []
  }
  for item in arr {
    match item {
      Object(fm) => {
        let path = json_str(fm, "path")
        let content = json_str(fm, "content")
        if path != "" {
          out.push({ path, content, })
        }
      }
      _ => ()
    }
  }
  out
}

///|
/// Serialise a list of generated files into the plugin-reply JSON — the writer a
/// MoonBit plugin uses on its stdout. Emits the `{"files": [...]}` envelope.
pub fn gen_files_to_json(files : Array[GenFile]) -> Json {
  let arr : Array[Json] = []
  for f in files {
    let m : Map[String, Json] = Map([
      ("path", f.path.to_json()),
      ("content", f.content.to_json()),
    ])
    arr.push(m.to_json())
  }
  let doc : Map[String, Json] = Map([("files", arr.to_json())])
  doc.to_json()
}
