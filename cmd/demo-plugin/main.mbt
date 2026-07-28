// Reads the ApiSpec JSON mctl writes to stdin, and prints a {"files":[...]} reply
// on stdout: a Markdown route listing plus a route count. It exercises the whole
// plugin contract end to end using only mctl's own (de)serialisers.

///|
async fn main {
  try {
    let spec = @moonctl.spec_from_json(@stdio.stdin.read_all().json())
    let mut md = "# " + spec.service + " routes\n\n"
    for r in spec.routes {
      md = md + "- " + r.verb + " " + r.path + " -> " + r.handler
      if r.summary != "" {
        md = md + "  (" + r.summary + ")"
      }
      md = md + "\n"
    }
    let files : Array[@moonctl.GenFile] = [
      { path: spec.service + "_routes.md", content: md },
      {
        path: spec.service + "_count.txt",
        content: spec.routes.length().to_string() + "\n",
      },
    ]
    @stdio.stdout.write(@moonctl.gen_files_to_json(files).stringify())
  } catch {
    e => @stdio.stderr.write("demo-plugin: " + e.to_string())
  }
}
