name = "Lfan-ke/moonctl"

version = "0.6.1"

readme = "README.md"

repository = "https://github.com/Lfan-ke/moonctl"

license = "Apache-2.0"

keywords = [
  "goctl",
  "codegen",
  "scaffold",
  "api",
  "moonapi",
  "moonbit",
  "cli",
]

description = "moonctl (mctl) — a spec-driven code generator for MoonBit (← goctl): parse a .api service spec and emit compilable moonapi scaffolding (routes + handler stubs)."

import {
  "moonbitlang/async@0.20.3",
  "Lfan-ke/moondb@0.1.3",
  "Lfan-ke/moon-sqlite@0.1.4",
  "Lfan-ke/moon-postgres@0.1.3",
}
