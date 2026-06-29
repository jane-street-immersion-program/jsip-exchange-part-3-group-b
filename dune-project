(lang dune 3.0)

(generate_opam_files true)

(maintainers "JSIP Organizers")

(authors "JSIP Organizers")

(homepage "https://github.com/jane-street-immersion-program/jsip-exchange/")

(bug_reports
 "https://github.com/jane-street-immersion-program/jsip-exchange/issues")

(license MIT)

(package
 (name jsip-exchange)
 (synopsis "An project building a financial exchange in OCaml")
 (depends
  (ocaml
   (>= 5.2.0))
  dune
  ocaml-lsp-server
  ocamlformat
  (odoc :with-doc)
  async
  async_log
  async_rpc_kernel
  async_rpc_websocket
  bonsai
  bonsai_term
  bonsai_term_components
  bonsai_web
  virtual_dom
  cohttp-async
  core
  core_unix
  core_bench
  ppx_jane
  ppx_html
  js_of_ocaml-ppx
  (bin_prot :with-test)
  (notty-community :with-test)
  (expect_test_helpers_core :with-test)
  (expect_test_helpers_async :with-test)))
