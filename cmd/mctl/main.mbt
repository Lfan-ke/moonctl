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
    "  mctl gen doc   <file.api>    parse a .api spec  -> <file>_openapi.json + _swagger.html",
  )
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
    "doc" => gen_doc(file)
    _ => usage()
  }
}

///|
/// Entry point for the `mctl` binary. `@env.args()[0]` is the executable path on
/// native, so the sub-command starts at index 1. The verb is `gen` (or its synonym
/// `generate`) followed by a target and an input file.
async fn main {
  let argv = @env.args()
  let args : Array[String] = []
  for i = 1; i < argv.length(); i = i + 1 {
    args.push(argv[i])
  }
  if args.length() >= 3 && (args[0] == "gen" || args[0] == "generate") {
    dispatch(args[1], args[2])
  } else {
    usage()
  }
}
