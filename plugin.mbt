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
/// Serialise a `Spec` into the plugin request JSON. The shape mirrors the `Spec`
/// itself — `service`, `routes` (`verb`/`path`/`handler`/`summary`), and `types`
/// (`name` plus `fields` of `name`/`type`) — so a plugin in any language parses it
/// with an ordinary JSON reader. `type_` is written as `type`, the name a caller
/// expects.
pub fn spec_to_json(spec : Spec) -> Json {
  let routes : Array[Json] = []
  for r in spec.routes {
    let m : Map[String, Json] = Map([
      ("verb", r.verb.to_json()),
      ("path", r.path.to_json()),
      ("handler", r.handler.to_json()),
      ("summary", r.summary.to_json()),
    ])
    routes.push(m.to_json())
  }
  let types : Array[Json] = []
  for t in spec.types {
    let fields : Array[Json] = []
    for f in t.fields {
      let fm : Map[String, Json] = Map([
        ("name", f.name.to_json()),
        ("type", f.type_.to_json()),
      ])
      fields.push(fm.to_json())
    }
    let tm : Map[String, Json] = Map([
      ("name", t.name.to_json()),
      ("fields", fields.to_json()),
    ])
    types.push(tm.to_json())
  }
  let doc : Map[String, Json] = Map([
    ("service", spec.service.to_json()),
    ("routes", routes.to_json()),
    ("types", types.to_json()),
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
  match j {
    Object(m) => {
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
                          })
                        _ => ()
                      }
                    }
                  _ => ()
                }
                types.push({ name: json_str(tm, "name"), fields })
              }
              _ => ()
            }
          }
        _ => ()
      }
    }
    _ => ()
  }
  { service, routes, types }
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
          out.push({ path, content })
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
