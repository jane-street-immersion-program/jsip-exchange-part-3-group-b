open! Core
open! Async
open Jsip_types
open Bonsai_term
module Scroller = Bonsai_term_scroller

(* Actions injected into the controller's state machine. [Feed_event] comes
   from the audit-log pipe we drain on activation; [Handle_key] comes from
   the keyboard handler. *)
module Action = struct
  type t =
    | Feed_event of Exchange_event.t
    | Handle_key of Event.Key.t
  [@@deriving sexp_of]
end

let color_to_attr (color : Event_log.Color.t) : Attr.t =
  let c =
    match color with
    | Default -> Attr.Color.Expert.default
    | Red -> Attr.Color.Expert.lightred
    | Green -> Attr.Color.Expert.lightgreen
    | Yellow -> Attr.Color.Expert.lightyellow
    | Blue -> Attr.Color.Expert.lightblue
    | Magenta -> Attr.Color.Expert.lightmagenta
    | Cyan -> Attr.Color.Expert.lightcyan
  in
  Attr.fg c
;;

let dim_grey = Attr.fg Attr.Color.Expert.lightblack
let title_attr = Attr.many [ Attr.bold; Attr.fg Attr.Color.Expert.white ]
let enabled_chip_attr = Attr.fg Attr.Color.Expert.lightcyan
let disabled_chip_attr = dim_grey

let edit_caret_attr =
  Attr.many [ Attr.bold; Attr.fg Attr.Color.Expert.lightyellow ]
;;

let render_chip (chip : Controller.Chip.t) =
  let attr =
    if chip.enabled then enabled_chip_attr else disabled_chip_attr
  in
  let opener, closer = if chip.enabled then "[", "]" else "(", ")" in
  let hotkey = String.of_char chip.hotkey in
  View.text
    ~attrs:[ attr ]
    [%string "%{opener}%{hotkey} %{chip.label}%{closer}"]
;;

let render_chips_row label chips =
  let label_view =
    View.text ~attrs:[ dim_grey ] (String.pad_right label ~len:12)
  in
  let chip_views = List.map chips ~f:render_chip in
  (* Separate chips with two-space gaps. *)
  let sep = View.text "  " in
  let chip_row = List.intersperse chip_views ~sep |> View.hcat in
  View.hcat [ label_view; chip_row ]
;;

let render_substring_row (field : Controller.Display.substring_field) =
  let label =
    View.text ~attrs:[ dim_grey ] (String.pad_right "Substring:" ~len:12)
  in
  let value_attr = Attr.fg Attr.Color.Expert.lightyellow in
  let body =
    if field.editing
    then
      View.hcat
        [ View.text ~attrs:[ value_attr ] field.value
        ; View.text ~attrs:[ edit_caret_attr ] "_"
        ; View.text ~attrs:[ dim_grey ] "  (editing)"
        ]
    else if String.is_empty field.value
    then View.text ~attrs:[ dim_grey ] "(empty)"
    else View.text ~attrs:[ value_attr ] field.value
  in
  View.hcat [ label; body ]
;;

let render_event_line (color, line) =
  View.text ~attrs:[ color_to_attr color ] line
;;

(* Width of the horizontal rules that delimit the event list from the chrome
   rows. Chosen to be wider than the longest chrome row but narrow enough to
   fit a standard 80-column terminal. *)
let separator_width = 70

let separator () =
  (* [separator_width] copies of the unicode "BOX DRAWINGS LIGHT HORIZONTAL" character. *)
  let line =
    String.concat ~sep:"" (List.init separator_width ~f:(fun _ -> "─"))
  in
  View.text ~attrs:[ dim_grey ] line
;;

(* The view splits into three vertical bands. The scrolling layer wraps the
   middle band ([render_event_list]) at a fixed height derived from the
   terminal dimensions, while the chrome rows stay pinned. *)

let scroll_indicator_view ~stuck_to_bottom =
  if stuck_to_bottom
  then
    View.text ~attrs:[ Attr.fg Attr.Color.Expert.lightgreen ] "auto-scroll ↓"
  else
    View.text
      ~attrs:[ Attr.fg Attr.Color.Expert.lightyellow; Attr.bold ]
      "paused — press a to resume"
;;

let bbo_value_attr = Attr.fg Attr.Color.Expert.lightcyan

let render_bbo_row (symbol, bbo) =
  let bbo_str = Bbo.to_string bbo in
  View.hcat
    [ View.text ~attrs:[ title_attr ] [%string "%{symbol#Symbol}: "]
    ; View.text ~attrs:[ bbo_value_attr ] bbo_str
    ]
;;

let render_bbo_panel (bbos : (Symbol.t * Bbo.t) list) =
  let label =
    View.text ~attrs:[ dim_grey ] (String.pad_right "BBO:" ~len:12)
  in
  let body =
    if List.is_empty bbos
    then View.text ~attrs:[ dim_grey ] "(no quotes yet)"
    else (
      let rows = List.map bbos ~f:render_bbo_row in
      let sep = View.text "  " in
      List.intersperse rows ~sep |> View.hcat)
  in
  View.hcat [ label; body ]
;;

let render_top_chrome ~stuck_to_bottom (display : Controller.Display.t)
  : View.t
  =
  let header =
    View.hcat
      [ View.text ~attrs:[ title_attr ] display.title
      ; View.text "   "
      ; View.text ~attrs:[ dim_grey ] display.counter
      ; View.text "   "
      ; scroll_indicator_view ~stuck_to_bottom
      ]
  in
  let mode_block =
    if String.is_empty display.mode_indicator
    then []
    else
      [ View.text
          ~attrs:[ Attr.fg Attr.Color.Expert.lightyellow; Attr.bold ]
          display.mode_indicator
      ]
  in
  View.vcat
    ([ header
     ; render_bbo_panel display.bbo_panel
     ; render_chips_row "Categories:" display.category_chips
     ; render_substring_row display.substring_field
     ]
     @ mode_block
     @ [ separator () ])
;;

let render_event_list (display : Controller.Display.t) : View.t =
  if List.is_empty display.visible_events
  then View.text ~attrs:[ dim_grey ] "  (no events visible)"
  else View.vcat (List.map display.visible_events ~f:render_event_line)
;;

(* In browsing mode, append a [a=auto-scroll] hint to whatever the controller
   produced. The controller doesn't know about scrolling, so this lives here. *)
let footer_text (display : Controller.Display.t) =
  if display.substring_field.editing
  then display.footer
  else display.footer ^ "  a=auto-scroll"
;;

let render_bottom_chrome (display : Controller.Display.t) : View.t =
  let label = String.pad_right "Footer:" ~len:12 in
  let body = footer_text display in
  let footer = View.text ~attrs:[ dim_grey ] [%string "%{label} %{body}"] in
  View.vcat [ separator (); footer ]
;;

let render_display ?(stuck_to_bottom = true) (display : Controller.Display.t)
  : View.t
  =
  View.vcat
    [ render_top_chrome ~stuck_to_bottom display
    ; render_event_list display
    ; render_bottom_chrome display
    ]
;;

(* Why we don't use [Scroller.less_keybindings_handler]:

   That handler always issues a [Not_g] inject (to reset its gg-tracker) for
   every non-'g' key, and [Not_g] flows through the state machine as a
   [Captured] action — i.e. the scroller reports every non-'g' keystroke as
   captured, even when it didn't actually do anything visible. The controller
   would never see [q], [r], [1], [/], etc.

   So instead, [Routing.of_event] decides the destination up front, and the
   handler dispatches to [Scroller.inject] only for the keys we actually want
   the scroller to handle. *)

module Routing = struct
  type scroll =
    | Up
    | Down
    | Up_half_screen
    | Down_half_screen
    | Bottom
  [@@deriving sexp_of, compare, equal]

  type t =
    | Exit
    | Scroll of scroll
    | Toggle_scroll_mode
    | To_controller
    | Ignore
  [@@deriving sexp_of, compare, equal]

  let of_event ~editing (event : Event.t) =
    match event with
    | Key_press { key = ASCII ('C' | 'c'); mods = [ Ctrl ] } -> Exit
    | Key_press { key = Uchar uchar; mods = [ Ctrl ] }
      when Uchar.equal (Uchar.of_char 'C') uchar
           || Uchar.equal (Uchar.of_char 'c') uchar ->
      Exit
    (* In edit mode every keystroke (including [j], [k], arrows, ...) is a
       candidate buffer character or a control key for the editor itself. *)
    | _ when editing -> To_controller
    | Key_press { key = ASCII 'a'; mods = [] } -> Toggle_scroll_mode
    | Key_press { key = Arrow `Up; mods = [] }
    | Key_press { key = ASCII 'k'; mods = [] } ->
      Scroll Up
    | Key_press { key = Arrow `Down; mods = [] }
    | Key_press { key = ASCII 'j'; mods = [] } ->
      Scroll Down
    | Key_press { key = Page `Up; mods = [] }
    | Key_press { key = ASCII 'u'; mods = [ Ctrl ] } ->
      Scroll Up_half_screen
    | Key_press { key = Page `Down; mods = [] }
    | Key_press { key = ASCII 'd'; mods = [ Ctrl ] } ->
      Scroll Down_half_screen
    | Key_press { key = ASCII 'G'; mods = [] } -> Scroll Bottom
    | Mouse _ | Paste _ -> Ignore
    | Key_press _ -> To_controller
  ;;
end

let scroll_to_action : Routing.scroll -> Scroller.Action.t = function
  | Up -> Up
  | Down -> Down
  | Up_half_screen -> Up_half_screen
  | Down_half_screen -> Down_half_screen
  | Bottom -> Bottom
;;

let dispatch_to_controller ~controller ~inject ~exit (event : Event.t)
  : unit Effect.t
  =
  match event with
  | Key_press { key; mods = _ } ->
    (* [handle_key] is pure, so we can speculatively apply it to see whether
       this key triggers an exit. The actual model update goes through the
       state machine via [inject (Handle_key key)]. *)
    let next = Controller.handle_key controller key in
    if Controller.should_exit next
    then exit ()
    else inject (Action.Handle_key key)
  | Mouse _ | Paste _ -> Effect.return ()
;;

let drain_events_on_activate events inject =
  Effect.of_thunk (fun () ->
    don't_wait_for
      (Pipe.iter_without_pushback events ~f:(fun event ->
         Effect.Expert.handle
           ~on_exn:(fun exn ->
             Core.eprint_s
               [%message "Term_app: feed_event raised" (exn : Exn.t)])
           (inject (Action.Feed_event event)))))
;;

let app ~events ~exit ~dimensions (local_ graph) =
  let controller, inject =
    Bonsai.state_machine
      ~default_model:(Controller.create ())
      ~apply_action:(fun _ctx model action ->
        match (action : Action.t) with
        | Feed_event event -> Controller.feed_event model event
        | Handle_key key -> Controller.handle_key model key)
      graph
  in
  (* On activation, spawn a background task that drains the audit-log pipe
     directly into the state machine. Putting the drain inside the graph
     means [app]'s caller hands us a pipe and is otherwise oblivious to how
     events make it into the controller. *)
  Bonsai.Edge.lifecycle
    ~on_activate:
      (let%map.Bonsai inject in
       drain_events_on_activate events inject)
    graph;
  let display = Bonsai.map controller ~f:Controller.display in
  let event_list = Bonsai.map display ~f:render_event_list in
  let bottom_chrome = Bonsai.map display ~f:render_bottom_chrome in
  (* We need a provisional scroller-dims to instantiate the scroller, which
     in turn gives us [stuck_to_bottom] to render the chrome's auto-scroll
     indicator. The indicator's text width is fixed (no wrapping), so its
     height contribution is stable regardless of [stuck_to_bottom] — we use a
     placeholder [true] for the dims computation and pass the real value into
     the final [render_top_chrome] below. *)
  let top_chrome_for_dims =
    Bonsai.map display ~f:(render_top_chrome ~stuck_to_bottom:true)
  in
  let scroller_dims =
    let%map.Bonsai (dims : Dimensions.t) = dimensions
    and top = top_chrome_for_dims
    and bot = bottom_chrome in
    let chrome_height = View.height top + View.height bot in
    { Dimensions.width = dims.width
    ; height = Int.max 1 (dims.height - chrome_height)
    }
  in
  let scroller =
    Scroller.component
      ~default_stuck_to_bottom:true
      ~dimensions:scroller_dims
      event_list
      graph
  in
  let top_chrome =
    let%map.Bonsai display and scroller in
    render_top_chrome ~stuck_to_bottom:scroller.stuck_to_bottom display
  in
  let view =
    let%map.Bonsai top = top_chrome
    and scroller
    and bot = bottom_chrome in
    View.vcat [ top; scroller.view; bot ]
  in
  let handler =
    let%map.Bonsai scroller and controller and inject in
    fun (event : Event.t) ->
      let editing = Controller.is_editing_substring controller in
      match Routing.of_event ~editing event with
      | Exit -> exit ()
      | Scroll s -> scroller.inject (scroll_to_action s)
      | Toggle_scroll_mode ->
        (* Currently stuck → unstick by scrolling up half a screen; this
           pauses auto-scroll and exposes some history. Already paused →
           re-stick to bottom. *)
        if scroller.stuck_to_bottom
        then scroller.inject Up_half_screen
        else scroller.inject Stick_to_bottom
      | To_controller ->
        dispatch_to_controller ~controller ~inject ~exit event
      | Ignore -> Effect.return ()
  in
  ~view, ~handler
;;

module For_testing = struct
  let render_display = render_display
end
