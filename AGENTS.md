`moonctl` reads a goctl-style `.api` spec and generates MoonBit code from it — routes, types, OpenAPI, protobuf, DDL, GraphQL, and project scaffolds. `mctl` is the CLI.

# Working here

- `moon fmt` before anything else. CI runs `moon fmt && git diff --exit-code`, so an unformatted file fails the build on its own.
- `moon check --target all --deny-warn` is the gate. Warnings are errors, and all four backends (wasm, wasm-gc, js, native) must pass.
- `moon test --target all` runs the suite everywhere. Native has one extra test — a SQLite round-trip that only exists there.
- `moon info` regenerates `pkg.generated.mbti`. If that file does not change, your edit is not visible to anyone depending on this package, which usually means the refactor was safe. If it does change, read the diff before committing — that is the public interface moving.
- CI installs the latest moon on every run, so a toolchain that is behind will disagree with it. Upgrade locally rather than pinning.

# Layout

Generators live at the root, one file per output: `spec.mbt` parses `.api`, then `template.mbt`, `proto.mbt`, `ddl.mbt`, `doc.mbt`, `gql.mbt`, `model.mbt`, `datasource.mbt`, and `scaffold.mbt` each turn a `Spec` into something. `plugin.mbt` is the extension seam. Tests sit beside their subject as `*_wbtest.mbt`. `cmd/mctl` is the binary; `examples/NN-topic/` are runnable one-file demos.

# Things worth knowing

- `spec.mbt` is a hand-written line parser, not a grammar. A route is only recognised when its first token is an HTTP verb; everything after the path is matched against the four shapes goctl allows — bare, `(Req)`, `returns (Resp)`, or both — plus the legacy `verb /path handler "summary"`. Adding a form means extending that match, and `spec_routes_wbtest.mbt` should grow a case for it.
- The parser reports. `read` scans to the end collecting `(line, message)` complaints; `parse` raises the earliest one as a `SpecError`, `parse_lenient` drops them. A new construct that can be misspelt should push a complaint rather than `continue` past it — a skipped line is a silently truncated program, which is what `parse_lenient` is for. `spec_server_wbtest.mbt` holds the diagnostics and the `@server` group cases.
- An `@server( … )` block sets the current `Group` and a service block's `}` clears it, so the annotations reach every route between them. A route's path already has the group's `prefix` folded in; `Group.prefix` is kept for a generator that needs to strip or regroup it.
- Type blocks come in two forms: `type Name {` on its own, and the grouped `type ( … )` whose members are bare `Name {` lines. Both end up in `Spec.types`.
- Generated output is compared verbatim in tests. Changing whitespace or field order in a generator will fail them; that is deliberate, since the output is what users read.
- `docs/index.html` is built by `scripts/gen_docs.py` from `///` comments. A new top-level file needs an entry in its `SECTIONS` list or it will not appear.
