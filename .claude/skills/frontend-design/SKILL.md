---
name: "frontend-design"
description: "Visual/UI design for Bonsai dashboards and forms with a dense, data-first dev-tool aesthetic."
---

You are designing frontend UI for data-dense developer/operator tools — for JSIP, that's the exchange's dashboards and control surfaces. Favor speed, accuracy, scannability, and keyboard/mouse efficiency over novelty.

The target aesthetic is a **premium developer tool**: minimal, dark, dense, precise, instant. The UI should feel like using a desktop application or code editor, not a website. Use Linear, Grafana, and Raycast as references. Focus rings are prominent, keyboard workflows are first-class, and state changes resolve in a single frame.

## Know your users: technical operators at a desk

Assume a technically literate, time-pressed user on a desktop computer:

- **Roles:** people operating or monitoring the exchange — technically literate, time-pressed.
- **OS / browser:** desktop, modern Chrome. Use modern JS, CSS, and HTML freely — grid, flex, custom properties, `lch()`, container queries, `:has()`. No mobile, no polyfills.
- **Fonts:** default to a system sans-serif; don't load web fonts.
- **Window sizes:** a tool may be fullscreen or tiled into a small strip or square, so design for a range of sizes and use a loud visual choice only when something is genuinely important.

Optimize for high-density layouts. Use responsive layouts, but assume keyboard and mouse input even at small sizes. Skip mobile affordances. Don't rely on subtle hue differences alone to carry meaning. Use your judgment when making a UI "loud" — make important things stand out, keep everything else quiet; we don't want everything to be loud all the time.

## Override Claude's default editorial style

Do not default to cream/off-white backgrounds, serif display type, terracotta/amber accents, or italic word-accents. Those read as editorial and are wrong for dashboards, dev tools, and trading surfaces. Use the dark monochromatic palette defined in the Tokens section.

## Start with the product context

Before coding, identify:

- **User and workflow**: Who uses this, what are they trying to decide or do, how often?
- **Information shape**: Table, form, monitoring surface, diff/review flow, investigation tool, or one-off artifact?
- **Risk and urgency**: Which mistakes are costly? What needs confirmation, auditability, or strong visual hierarchy?
- **Known pain points**: Which existing workflows or features have frustrated users? This iteration should address them explicitly.
- **Platform**: a Bonsai (`bonsai_web` + `js_of_ocaml`) app (see Your platform below).

## Inspect the existing app before adding to it

This skill applies whether you're starting fresh or editing an existing tool. When iterating, **read before writing**.

- **Find existing components.** Before adding a new button, modal, side panel, or layout primitive, search the app for one. Reuse it.
- **Detect the local convention.** An app builds up its own patterns for tables, forms, page chrome, spacing, and colors. Match that style even when it differs from this skill's defaults. Local consistency beats global purity for a one-feature change.
- **Match the token system.** If the app defines its own custom properties (`--bg-*`, `--space-*`, etc.), use those. Don't introduce parallel ad-hoc values.
- **Don't fork conventions.** If you'd be introducing a "button-v2" or a second tooltip implementation, stop. Use the existing one, or improve the existing one in place. Two conventions is worse than one slightly imperfect convention.
- **Depart deliberately.** If the existing pattern is actually broken (no focus rings, hard-coded colors, inaccessible), it may be worth fixing — but pick a side: fix it everywhere in the app, or leave it. Don't half-refactor.
- **For Bonsai apps**, read 1–2 nearby files in the same library and grep for similar components elsewhere in the app before defining a new one.

For green-field work — a new app, a new prototype — the design standards below apply directly. For everything else, treat them as defaults that local conventions can override.

## Your platform: a Bonsai app

JSIP UIs are Bonsai (`bonsai_web` + `js_of_ocaml`) apps with a server that can serve data
over RPCs. There is **no Skyline** (the firm component library) here, so build your own
small, consistent set of components:

- Also use the [[bonsai-web]] skill for the Bonsai/ppx_html mechanics.
- Define a small set of components (buttons, fields, cards, modals, side panels) once, in
  modules, and reuse them consistently — don't reinvent a button per screen.
- Use host elements where possible: `<input>`, `<select>`, `<textarea>`, `<dialog>`,
  `<details>`, etc.
- Style with `Vdom.Attr.create "style" "..."` (there's no `ppx_css` here; see the
  bonsai-web "Styling" section), and keep style tokens in one module.
- Apply sane defaults: `scrollbar-width: thin`, `font-variant-numeric: tabular-nums`,
  `color-scheme: dark`.

## Apply these design standards to every layout

- **Use the viewport.** Dashboards and control surfaces should scale with the viewport and avoid page scroll when feasible. Reserve max-width layouts for document-like content.
- **Don't nest cards.** No cards inside cards; no page sections styled as floating cards. Reserve cards for individual repeated items, modals, and genuinely framed tools. Page sections should be full-width bands or unframed layouts with constrained inner content.
- **Lock fixed-format UI dimensions.** Toolbars, tiles, icon buttons, counters, and grid cells should have stable sizes so hover labels, loading text, or dynamic content can't reflow the layout.
- **Make data scannable.** Right-align numbers, monospace timestamps, align decimal points, indicate freshness or staleness.
- **Make actions deliberate.** Make primary, secondary, and destructive actions visually distinct, and put them where users need them.
- **Use familiar icons for familiar actions.** Save, undo/redo, bold/italic, zoom should be icon-only buttons, not rounded rectangles with text. Lucide is the canonical icon set. Tooltip any icon a target user wouldn't immediately recognize.
- **Design every state.** Loading, empty, partial, error, permission-denied, stale, success, selected, changed, hover, focus.
- **Convey elevation through fill, border, and shadow together.** Every element sits at some elevation, so design with it in mind — higher elements get lighter fills, lighter borders, and larger shadows; lower elements the inverse. Consider nesting: a button is more elevated than the panel it sits on, which itself may be a modal already lifted above the page. Raise an element one step on hover.
- **Resolve interactions in a single frame.** Hover and focus changes have no transition duration. Prefer opacity and color shifts over movement; keep transforms under 8px when used.
- **Stay monochromatic.** Use the accent color sparingly for interactive highlights and status (error, warning, success). The UI is predominantly grayscale.

## Design loading and empty states deliberately

Internal tools spend more time mid-load than designers usually account for. Treat loading and empty states as first-class UI, not afterthoughts.

- **Skeletons over spinners for first paint.** When a layout's shape is known in advance (a table with N rows, a chart panel, a sidebar), render skeleton placeholders that match the eventual layout. Structure shows immediately and the page doesn't jump on data arrival.
- **Spinners only for short, indeterminate async actions** — a submit, save, or search. Inline next to the trigger, not blocking the page.
- **Progress bars for determinate work** — a known-duration job, a file upload, a multi-step flow.
- **Delay short spinners by ~200ms.** Requests that resolve faster than that shouldn't show a loading state at all; flashing a spinner reads as janky.
- **Don't block the page.** Block only when the user's next action would conflict with the in-flight request. Otherwise let them keep working.
- **Preserve layout across loading → loaded.** The skeleton's bounding box matches the final content's bounding box. No reflow on data arrival.
- **Optimistic updates for high-confidence writes** — a star, a comment, a checkbox. Apply locally first and reconcile on response.
- **Empty states are distinct from loading.** An empty result needs an explanation ("No results for 'XYZ'") and ideally a next action ("Clear filters"). Don't show a blank table.
- **Stale data is different again.** If showing cached data while refreshing, indicate freshness (e.g., "Last updated 3s ago" or a corner pulse).

## Define design tokens once

Keep your design tokens in one place — either named string constants in a `styles.ml`
module, or CSS custom properties on `:root` in your `index.html` referenced with
`var(...)`. `lch()` gives perceptually-uniform tones, which makes contrast easier to reason about than `hsl()` or `rgb()`.

<example>
:root {
  --font-sans: "Inter", sans-serif;
  --font-mono: monospace;

--font-weight-normal: 400;
--font-weight-medium: 500;
--font-weight-semibold: 600;

--font-size-xs: 12px;
--font-size-sm: 13px;
--font-size-md: 15px;
--font-size-lg: 17px;

--space-xs: 4px;
--space-sm: 8px;
--space-md: 12px;
--space-lg: 16px;
--space-xl: 24px;
--space-2xl: 32px;

--radius-sm: 4px;
--radius-md: 6px;
--radius-lg: 8px;
--radius-xl: 12px;
--radius-full: 9999px;

/* Background elevation tiers: 0 = page, 4 = modal */
--color-bg-0: lch(3% 1 260);
--color-bg-1: lch(12% 1.5 280);
--color-bg-2: lch(15% 1.5 280);
--color-bg-3: lch(20% 1.5 280);
--color-bg-4: lch(25% 1.5 280);
--color-bg-translucent: lch(100% 0 0 / 0.05);
--color-backdrop: lch(0% 0 0 / 0.7);

/* Text: off-white, never pure white */
--color-text-primary: lch(97.5% 0.5 240);
--color-text-secondary: lch(86% 4 250);
--color-text-tertiary: lch(61% 4 260);
--color-text-quaternary: lch(44% 3 260);

--color-border-1: lch(16% 2 260);
--color-border-2: lch(23% 1.5 280);
--color-border-3: lch(30% 1.5 280);
--color-border-4: lch(40% 1.5 280);
--color-border-translucent: lch(100% 0 0 / 0.05);

--color-accent: lch(48% 55 280);
--color-accent-hover: lch(62% 50 275);
--color-focus-ring: lch(48% 55 280);
}
</example>

The token names share an elevation index 0–4: `--color-bg-N`, `--color-border-N`, and `--shadow-N` line up at the same N. Reach for all three together at any given tier — they're tuned to read as one elevation level.

Use the typography scale rather than scaling fonts to the viewport. Keep `letter-spacing: 0` (never negative).

| Tier | Use cases                                                                    |
| ---- | ---------------------------------------------------------------------------- |
| 0    | Page background. No border or shadow.                                        |
| 1    | Panels, sections, sticky headers; buttons and chips at rest.                 |
| 2    | Inline chips, pills, nested elements. Also the hover state of tier 1.        |
| 3    | Cards, popovers, dropdowns, toasts. Also the hover state of tier 2.          |
| 4    | Modals, dialogs, command palettes, overlays. Also the hover state of tier 3. |

## Stack shadows in layers, not flat drop shadows

A single drop shadow looks flat. Convincing elevation uses several stacked shadows where each layer roughly doubles the offset and blur of the previous layer, all at low opacity — this approximates natural light falloff. See [Designing Beautiful Shadows in CSS](https://www.joshwcomeau.com/css/designing-shadows/) for the underlying technique.

Define one shadow per tier and reach for the tier that matches how far a surface lifts off the page. Don't stack or invent inline shadows.

<example>
:root {
  --shadow-1:
    0.5px 1px 1px lch(0% 0 0 / 0.35);

--shadow-2:
0.5px 1px 1px lch(0% 0 0 / 0.2),
1px 2px 2px lch(0% 0 0 / 0.2),
2px 4px 4px lch(0% 0 0 / 0.2),
4px 8px 8px lch(0% 0 0 / 0.2);

--shadow-3:
0.5px 1px 1px lch(0% 0 0 / 0.15),
1px 2px 2px lch(0% 0 0 / 0.15),
2px 4px 4px lch(0% 0 0 / 0.15),
4px 8px 8px lch(0% 0 0 / 0.15),
8px 16px 16px lch(0% 0 0 / 0.15),
16px 32px 32px lch(0% 0 0 / 0.15);

--shadow-4:
0.5px 1px 1px lch(0% 0 0 / 0.12),
1px 2px 2px lch(0% 0 0 / 0.12),
2px 4px 4px lch(0% 0 0 / 0.12),
4px 8px 8px lch(0% 0 0 / 0.12),
8px 16px 16px lch(0% 0 0 / 0.12),
16px 32px 32px lch(0% 0 0 / 0.12),
32px 64px 64px lch(0% 0 0 / 0.12),
64px 128px 128px lch(0% 0 0 / 0.12);
}
</example>

See the elevation tier table in the Tokens section for which `--shadow-N` belongs at each tier.

## Meet these contrast and focus targets on dark surfaces

Approximate ratios on the palette above:

- Primary text on `--color-bg-0`: ~18:1 ✓
- Secondary text: ~14:1 ✓
- Tertiary text: ~6:1 ✓
- Interactive accent on dark: ensure ≥4.5:1

Always render a visible focus ring via `--color-focus-ring`. Don't rely on color alone for meaning — reinforce with icons, labels, and position. Maintain keyboard navigation and semantic controls.

## Aim for distinctive, not AI slop

**Distinctive (use this):** dark monochrome canvas, a single saturated accent for interactive state, system sans-serif (Inter) for UI and monospace for numerics, 4–32px t-shirt spacing scale, instant hover/focus state changes, multi-layered shadows on cards, dense tables with right-aligned numeric columns.

**Avoid (AI slop):** purple gradients on white, generic serifs as display type, left-hand accent borders on cards, decorative animations and layout transitions, glassmorphism, glow effects, geometric SVG backgrounds, oversized rounded cards floating on pastel backdrops, novelty fonts.

## Verify your work before declaring done

After implementing, render the result and walk through it yourself. Exercise the golden path and try edge cases: empty states, very long strings, the narrowest and widest viewports you expect, slow network. Build the client (`dune build`), serve it, and click through. Type checks and unit tests verify correctness, not feature behavior — you have to look at the UI.

## Build real UI in the user's stack

Build real working UI in the user's stack. Prefer clean, maintainable code over elaborate effects — a polished internal tool feels distinctive because it is clear, fast, well-structured, and fitted to the workflow.
