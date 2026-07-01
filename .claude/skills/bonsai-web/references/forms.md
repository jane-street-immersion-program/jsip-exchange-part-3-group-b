# Forms

**Build forms by hand: compose host inputs (`<input>`, `<select>`, `<textarea>`) with
`Bonsai.state` / `Bonsai.state'` / `Bonsai.state_machine` and plain `let%arr`.** This is
simpler and more transparent than a form-combinator library: the state, the parsing, and
the markup all stay visible in one component function.

## The basic shape

A form is three pieces:

1. State, via `Bonsai.state` (or `Bonsai.state_opt` for an initially-empty field).
2. A parsed/validated value, via `let%arr` producing `Or_error.t`.
3. A view that renders the input and surfaces any validation error.

Return `(value, view)` as a pair so the caller can wire the value into submission logic
and the view into its layout.

```ocaml
let name_form (local_ graph) =
  let name, set_name = Bonsai.state "" graph in
  let parsed =
    let%arr name in
    if String.is_empty name
    then Or_error.error_string "Name is required"
    else Ok name
  in
  let view =
    let%arr name and set_name and parsed in
    let error_text =
      match parsed with
      | Ok _ -> Vdom.Node.none
      | Error err -> {%html|<span>#{Error.to_string_hum err}</span>|}
    in
    {%html|
      <label>
        Name
        <input
          type="text"
          placeholder="Your name"
          value=%{name}
          on_input=%{fun new_name -> set_name new_name}
        />
      </label>
      %{error_text}|}
  in
  parsed, view
;;
```

`on_input` hands you the input's current string; write it straight back into state with
the setter. `value=%{...}` keeps the input controlled by Bonsai state.

## Common host inputs

| Input | Markup | State |
|-------|--------|-------|
| Single-line text | `<input type="text" value=%{s} on_input=%{set} />` | `string` |
| Multi-line text | `<textarea on_input=%{set}>#{s}</textarea>` | `string` |
| Checkbox | `<input type="checkbox" checked=%{b} on_click=%{fun _ -> set (not b)} />` | `bool` |
| Dropdown | `<select on_change=%{handle}> <option ...> ... </select>` | `'a` |

For numbers, keep the raw `string` in state and parse it in the `let%arr` (e.g. with
`Float.of_string` inside an `Or_error.try_with`), so the user can type freely and you
report a clear error on bad input.

## Multi-field forms

Give each field its own state, then combine the parsed values in one `let%arr`:

```ocaml
let order_form (local_ graph) =
  let price, set_price = Bonsai.state "" graph in
  let size, set_size = Bonsai.state "" graph in
  let parsed =
    let%arr price and size in
    let open Or_error.Let_syntax in
    let%bind price =
      Or_error.try_with (fun () -> Float.of_string price)
      |> Or_error.tag ~tag:"Price must be a number"
    in
    let%bind size =
      Or_error.try_with (fun () -> Int.of_string size)
      |> Or_error.tag ~tag:"Size must be an integer"
    in
    Ok { Order.price; size }
  in
  let view =
    let%arr price and set_price and size and set_size in
    {%html|
      <>
        <label>Price <input value=%{price} on_input=%{fun s -> set_price s} /></label>
        <label>Size <input value=%{size} on_input=%{fun s -> set_size s} /></label>
      </>|}
  in
  parsed, view
;;
```

For forms where fields interact (one field constrains another), use
`Bonsai.state_machine` so the whole form's state lives in one record and transitions are
explicit.

## Submit button

Disable the button when parsing fails. Fire the submit as a single `Effect.t` that
includes the RPC dispatch and any follow-up (clearing the form, closing a dialog):

```ocaml
let submit_view =
  let%arr parsed and dispatch_save and set_price and set_size in
  let on_click _ =
    match parsed with
    | Error _ -> Effect.Ignore
    | Ok order ->
      let%bind.Effect result = dispatch_save order in
      (match result with
       | Error err -> show_error err
       | Ok () ->
         let%bind.Effect () = set_price "" in
         set_size "")
  in
  let disabled = Or_error.is_error parsed in
  {%html|<button disabled=%{disabled} on_click=%{on_click}>Save</button>|}
;;
```

## Validation pattern

Always produce an `Or_error.t` from the raw inputs in a `let%arr`, surface the error in
the view, and gate the submit button on `Or_error.is_error parsed`. Do **not** raise — in
`js_of_ocaml`, exceptions are extremely slow and break the app. Propagate `Or_error.t` and
render the error case instead.

## Key paths

| Resource | Path |
|----------|------|
| Component / view conventions | the main `bonsai-web` SKILL.md |
| Styling host elements | the "Styling" section of the SKILL.md (`Vdom.Attr.create "style"`) |
| `Vdom.Attr` event/value helpers | the `virtual_dom` `.mli` in your opam switch |
