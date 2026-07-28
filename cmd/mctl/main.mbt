///|
/// Derive the output path for a generated scaffold: a `.api` input yields the
/// same stem with a `.mbt` extension; any other input just gains `.mbt`.
fn out_path(input : String) -> String {
  let n = input.length()
  if n >= 4 && input[n - 4:].to_owned() == ".api" {
    input[0:n - 4].to_owned() + ".mbt"
  } else {
    input + ".mbt"
  }
}

///|
/// Read a `.api` spec, run parse+generate, and write the scaffold to `<out>.mbt`.
/// All IO failures are caught and reported so `main` never propagates an error.
async fn gen_api(input : String) -> Unit {
  let out = out_path(input)
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
fn usage() -> Unit {
  println("mctl — a spec-driven code generator for MoonBit (← goctl)")
  println("")
  println("usage:")
  println("  mctl gen api <file.api>   parse a .api spec and emit <file>.mbt")
  println("  mctl help                 show this message")
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
  if args.length() >= 3 && args[0] == "gen" && args[1] == "api" {
    gen_api(args[2])
  } else {
    usage()
  }
}
