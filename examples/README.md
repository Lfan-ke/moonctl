# Examples

A runnable tour of the public `@moonctl` codegen API — the same pipeline the
`mctl` binary runs, as a library call.

```bash
moon run examples/00-greet
```

| # | Example | What it shows | Key API |
| --- | --- | --- | --- |
| 00 | [`greet`](00-greet/) | Turn a `.api` spec into a moonapi scaffold and an OpenAPI 3.1 document | `parse`, `generate`, `openapi_document`, `DocVersion::OpenApi31` |

[`00-greet`](00-greet/) inlines the spec in [`greet.api`](00-greet/greet.api) —
the file you would hand to `mctl gen api greet.api` — so it runs without file IO
and on every backend, unlike the native `mctl` binary. `parse` reads the spec,
`generate` emits the compilable `build_app` + handler stubs, and
`openapi_document` emits the matching OpenAPI document for the same routes and
`type` blocks.
