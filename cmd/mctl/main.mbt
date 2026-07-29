///|
/// Replace a known input extension with `suffix`; if the extension is absent the
/// suffix is simply appended. E.g. `("greet.api", ".mbt")` → `greet.mbt`,
/// `("greet.proto", "_grpc.mbt")` → `greet_grpc.mbt`.
fn replace_ext(input : String, ext : String, suffix : String) -> String {
  let n = input.length()
  let e = ext.length()
  if n >= e && input[n - e:].to_owned() == ext {
    input[0:n - e].to_owned() + suffix
  } else {
    input + suffix
  }
}

///|
/// Read a `.api` spec, run parse+generate, and write the scaffold to `<out>.mbt`.
/// All IO failures are caught and reported so `main` never propagates an error.
async fn gen_api(input : String) -> Unit {
  let out = replace_ext(input, ".api", ".mbt")
  try {
    let source = @fs.read_file(input).text()
    let code = @moonctl.generate(@moonctl.parse(source))
    @fs.write_file(out, code, create_mode=CreateOrTruncate)
    println("mctl: generated " + out + " from " + input)
  } catch {
    e => println("mctl: error generating from " + input + ": " + e.to_string())
  }
}

///|
/// Read a `.proto` file, parse it, and write a moonrpc service stub (message
/// structs + `@moonrpc.Method` descriptors + a `<Service>Server` handler skeleton)
/// to `<stem>_grpc.mbt`.
async fn gen_rpc(input : String) -> Unit {
  let out = replace_ext(input, ".proto", "_grpc.mbt")
  try {
    let source = @fs.read_file(input).text()
    let code = @moonctl.generate_grpc(@moonctl.parse_proto(source))
    @fs.write_file(out, code, create_mode=CreateOrTruncate)
    println("mctl: generated " + out + " from " + input)
  } catch {
    e => println("mctl: error generating from " + input + ": " + e.to_string())
  }
}

///|
/// Read a `.api` spec, parse its `type` blocks, and write moonorm models +
/// `@moonorm.Table` descriptors to `<stem>_model.mbt`.
async fn gen_model(input : String) -> Unit {
  let out = replace_ext(input, ".api", "_model.mbt")
  try {
    let source = @fs.read_file(input).text()
    let code = @moonctl.generate_model(@moonctl.parse(source))
    @fs.write_file(out, code, create_mode=CreateOrTruncate)
    println("mctl: generated " + out + " from " + input)
  } catch {
    e => println("mctl: error generating from " + input + ": " + e.to_string())
  }
}

///|
/// Read a SQL DDL file, parse its `CREATE TABLE` statements, and write a moonorm
/// data-access layer (models + typed CRUD) to `<stem>_model.mbt`.
async fn gen_crud(input : String) -> Unit {
  let out = replace_ext(input, ".sql", "_model.mbt")
  try {
    let source = @fs.read_file(input).text()
    let code = @moonctl.generate_crud_from_ddl(source)
    @fs.write_file(out, code, create_mode=CreateOrTruncate)
    println("mctl: generated " + out + " from " + input)
  } catch {
    e => println("mctl: error generating from " + input + ": " + e.to_string())
  }
}

///|
/// Index of the last `ch` in `s`, or `-1` if absent.
fn last_index_of(s : String, ch : UInt16) -> Int {
  let mut idx = -1
  for i = 0; i < s.length(); i = i + 1 {
    if s[i] == ch {
      idx = i
    }
  }
  idx
}

///|
/// Write one plugin-produced file, creating its parent directory when the path is
/// nested.
async fn write_gen_file(f : @moonctl.GenFile) -> Unit {
  let slash = last_index_of(f.path, '/')
  if slash > 0 {
    let dir = f.path[0:slash].to_owned()
    // `mkdir(recursive=true)` still raises if the leaf already exists, and a scaffold
    // writes several files into the same directory — so create it only once.
    if !@fs.exists(dir) {
      @fs.mkdir(dir, recursive=true)
    }
  }
  @fs.write_file(f.path, f.content, create_mode=CreateOrTruncate)
  println("mctl: wrote " + f.path)
}

///|
/// Run an external plugin over a `.api` spec: parse the spec, hand it to the plugin
/// as JSON on stdin, and write back the `{path, content}` files the plugin prints as
/// JSON on stdout. This is goctl's `api plugin` — an out-of-tree generator driven off
/// the same parsed spec mctl's built-in generators use.
async fn run_plugin(plugin : String, input : String) -> Unit {
  let req_path = input + ".mctlreq.json"
  try {
    let source = @fs.read_file(input).text()
    let spec = @moonctl.parse(source)
    @fs.write_file(
      req_path,
      @moonctl.plugin_request(spec),
      create_mode=CreateOrTruncate,
    )
    let stdin = @process.redirect_from_file(req_path)
    let (code, out, err) = @process.collect_output(plugin, [], stdin~)
    @fs.remove(req_path)
    if code != 0 {
      println(
        "mctl: plugin " +
        plugin +
        " exited with code " +
        code.to_string() +
        ": " +
        err.text(),
      )
      return
    }
    let files = @moonctl.parse_gen_files(out.json())
    for f in files {
      write_gen_file(f)
    }
    println(
      "mctl: plugin " +
      plugin +
      " produced " +
      files.length().to_string() +
      " file(s)",
    )
  } catch {
    e => println("mctl: plugin error: " + e.to_string())
  }
}

///|
/// Read a `.api` spec and write an OpenAPI 3.1 document (`<stem>_openapi.json`) plus
/// a Swagger UI page (`<stem>_swagger.html`) that renders it.
async fn gen_doc(input : String) -> Unit {
  let spec_out = replace_ext(input, ".api", "_openapi.json")
  let ui_out = replace_ext(input, ".api", "_swagger.html")
  try {
    let source = @fs.read_file(input).text()
    let spec = @moonctl.parse(source)
    let doc = @moonctl.generate_doc(spec)
    @fs.write_file(spec_out, doc, create_mode=CreateOrTruncate)
    @fs.write_file(
      ui_out,
      @moonctl.swagger_ui_stub(spec_url=spec_out),
      create_mode=CreateOrTruncate,
    )
    println("mctl: generated " + spec_out + " and " + ui_out + " from " + input)
  } catch {
    e => println("mctl: error generating from " + input + ": " + e.to_string())
  }
}

///|
/// Reflect a live database's schema and write generated moonorm models + CRUD to
/// `out`. `dsn` selects the backend: `sqlite:…` reads the schema synchronously through
/// the FFI driver, `postgres://…` over the async wire protocol. This is goctl's `model
/// … datasource`.
async fn gen_datasource(dsn : String, out : String) -> Unit {
  try {
    let code = match @moonctl.parse_dsn(dsn) {
      @moonctl.Sqlite(path) => {
        let db = @sqlite.SqliteDriver::open(path)
        @moonctl.generate_crud_from_reflection(@reflect.reflect_sqlite(db))
      }
      @moonctl.Postgres(t) => {
        let conn = @pg.PgConn::connect(
          t.host,
          t.port,
          t.user,
          t.password,
          t.database,
        )
        let cols = @reflect.reflect_postgres(conn)
        conn.close()
        @moonctl.generate_crud_from_reflection(cols)
      }
    }
    @fs.write_file(out, code, create_mode=CreateOrTruncate)
    println("mctl: generated " + out + " from datasource " + dsn)
  } catch {
    e => println("mctl: datasource error: " + e.to_string())
  }
}

///|
/// Write a scaffolded project's files, creating nested directories as needed, and
/// report the tree that was written.
async fn write_scaffold(
  label : String,
  files : Array[@moonctl.GenFile],
) -> Unit {
  try {
    for f in files {
      write_gen_file(f)
    }
    println(
      "mctl: scaffolded " +
      label +
      " (" +
      files.length().to_string() +
      " file(s))",
    )
  } catch {
    e => println("mctl: scaffold error: " + e.to_string())
  }
}

///|
fn usage() -> Unit {
  println("mctl — a spec-driven code generator for MoonBit (← goctl)")
  println("")
  println("usage:")
  println(
    "  mctl gen api   <file.api>    parse a .api spec  -> <file>.mbt (moonapi scaffold)",
  )
  println(
    "  mctl gen proto <file.proto>  parse a .proto     -> <file>_grpc.mbt (moonrpc stub)",
  )
  println(
    "  mctl gen model <file.api>    parse .api types   -> <file>_model.mbt (moonorm models)",
  )
  println(
    "  mctl gen crud  <file.sql>    parse a SQL DDL    -> <file>_model.mbt (moonorm models + CRUD)",
  )
  println(
    "  mctl gen doc   <file.api>    parse a .api spec  -> <file>_openapi.json + _swagger.html",
  )
  println(
    "  mctl model datasource <dsn>  read a live DB schema -> datasource_model.mbt (moonorm + CRUD)",
  )
  println(
    "                               dsn: sqlite:PATH | postgres://user:pass@host:port/db",
  )
  println(
    "  mctl api  new  <name>        scaffold a moonapi service project under <name>/",
  )
  println(
    "  mctl rpc  new  <name>        scaffold a moonrpc service project under <name>/",
  )
  println(
    "  mctl model new <name>        scaffold a moonorm data-layer project under <name>/",
  )
  println(
    "  mctl docker    <name>        write a Dockerfile + .dockerignore for the service",
  )
  println(
    "  mctl kube      <name>        write deploy/deployment.yaml + deploy/service.yaml",
  )
  println(
    "  mctl plugin    <exe> <file>  run an external plugin over a .api spec (ApiSpec JSON on stdin,",
  )
  println("                               {path,content} files on stdout)")
  println("  mctl help                    show this message")
  println("")
  println(
    "`generate` is accepted as a synonym for `gen`, and `rpc` for `proto`.",
  )
}

///|
/// Dispatch a `gen <what> <file>` sub-command. `rpc` and `proto` are synonyms
/// (proto → moonrpc), so both spellings work.
async fn dispatch(what : String, file : String) -> Unit {
  match what {
    "api" => gen_api(file)
    "proto" | "rpc" => gen_rpc(file)
    "model" => gen_model(file)
    "crud" => gen_crud(file)
    "doc" => gen_doc(file)
    "datasource" => gen_datasource(file, "datasource_model.mbt")
    _ => usage()
  }
}

///|
/// Entry point for the `mctl` binary. `@env.args()[0]` is the executable path on
/// native, so the sub-command starts at index 1. Commands: `gen <what> <file>` (and
/// its `generate` synonym), `model datasource <dsn>`, the `api|rpc|model new <name>`
/// project scaffolds, `docker`/`kube <name>`, and `plugin <exe> <file>`.
async fn main {
  let argv = @env.args()
  let args : Array[String] = []
  for i = 1; i < argv.length(); i = i + 1 {
    args.push(argv[i])
  }
  let n = args.length()
  if n >= 3 && (args[0] == "gen" || args[0] == "generate") {
    dispatch(args[1], args[2])
  } else if n >= 3 && args[0] == "model" && args[1] == "datasource" {
    gen_datasource(args[2], "datasource_model.mbt")
  } else if n >= 3 && args[0] == "api" && args[1] == "new" {
    write_scaffold("api project " + args[2], @moonctl.scaffold_api(args[2]))
  } else if n >= 3 && args[0] == "rpc" && args[1] == "new" {
    write_scaffold("rpc project " + args[2], @moonctl.scaffold_rpc(args[2]))
  } else if n >= 3 && args[0] == "model" && args[1] == "new" {
    write_scaffold("model project " + args[2], @moonctl.scaffold_model(args[2]))
  } else if n >= 2 && args[0] == "docker" {
    write_scaffold("docker files", @moonctl.scaffold_docker(args[1]))
  } else if n >= 2 && args[0] == "kube" {
    write_scaffold("kube manifests", @moonctl.scaffold_kube(args[1]))
  } else if n >= 3 && args[0] == "plugin" {
    run_plugin(args[1], args[2])
  } else {
    usage()
  }
}
