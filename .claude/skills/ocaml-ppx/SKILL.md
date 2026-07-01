---
name: "ocaml-ppx"
description: "Writing or reviewing OCaml code that uses PPX syntax extensions or `[@@deriving ...]` attributes: sexp, compare, equal, hash, bin_io, fields, variants, enumerate, stable_witness, jsonaf."
---

## PPX
- Prefer PPX derives when they express the code you want and match the conventions of
  the codebase you are working in, instead of hand-writing boilerplate.
- Avoid writing custom `compare` / `equal` functions whenever possible: it is easy to
  accidentally violate ordering/equality laws (or make `compare` and `equal` inconsistent),
  which can break invariants in sets/maps/hashtables and lead to subtle bugs.
  Prefer `[@@deriving compare, equal]`.
- Read a ppx's documentation before use (its opam package docs or README).
- Common deriving PPXs worth checking for first in Core-based OCaml codebases:
    - `sexp`, `of_sexp`, `sexp_of`: S-expression serializers
    - `compare`, `equal`, `hash`: comparison and hashing helpers
    - `string`: derives string conversion helpers, with capitalization options
    - `enumerate`: produces `all : t list` for enumerable types such as variants
    - `fields`, `typed_fields`: helpers for record types
    - `variants`: helpers for working with variant constructors
    - `bin_io`: binary serialization when the surrounding project uses it
    - `stable_witness`: stable-type metadata, often alongside `bin_io`
    - `jsonaf`: JSON serialization
    - `sexp_grammar`: grammar metadata for sexp-shaped types
- Which derives are appropriate depends on the surrounding code. For example, `bin_io`
  is common, but it is not the right default if the project uses a different
  serialization format.

eg
```ocaml
(* GOOD *)
type t =
    { foo: int
    ; bar : string
    } [@@deriving sexp_of, compare]

(* BAD *)
type t =
    { foo: int
    ; bar : string
    }

let sexp_of_t t = ...

let compare t1 t2 = ...
```
