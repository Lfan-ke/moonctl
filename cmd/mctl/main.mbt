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
fn usage() -> Unit {
  println("mctl — a spec-driven code generator for MoonBit (← goctl)")
  println("")
  println("usage:")
  println(
    "  mctl gen api   <file.api>    parse a .api spec  -> <file>.mbt (moonapi scaffold)",
  )
  println(
    "  mctl gen rpc   <file.proto>  parse a .proto     -> <file>_grpc.mbt (moonrpc stub)",
  )
  println(
    "  mctl gen model <file.api>    parse .api types   -> <file>_model.mbt (moonorm models)",
  )
  println("  mctl help                    show this message")
}

///|
/// Entry point for the `mctl` binary. `@env.args()[0]` is the executable path on
/// native, so the sub-command starts at index 1.
async fn main {
  let argv = @env.args()
  let args : Array[String] = []
  for i = 1; i < argv.length(); i = i + 1 {
    args.push(argv[i])
  }
  if args.length() >= 3 && args[0] == "gen" {
    match args[1] {
      "api" => gen_api(args[2])
      "rpc" => gen_rpc(args[2])
      "model" => gen_model(args[2])
      _ => usage()
    }
  } else {
    usage()
  }
}
