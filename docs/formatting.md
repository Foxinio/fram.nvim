# Fram formatting

The formatter uses Lua and Neovim's installed Fram Tree-sitter parser. Install
the plugin as described in the README, run `:TSInstall fram` (or `:TSUpdate fram`
for an existing parser), and call `require('fram').setup()`.

```lua
require('fram').setup({ format = { line_width = 100 } })
```

Use `:FramFormat`, `:FramFormat 80`, or `require('fram').format()` in a Fram
buffer. `require('fram').format(80)` also overrides the width for one invocation.
Widths are positive integers measured in display columns, including indentation.
The Lua function returns whether it changed the buffer and raises an error on
failure; the command reports errors through `vim.notify`.

Formatting is one undoable edit, preserves the window view, and never saves the
file. An unchanged buffer receives no edit. Missing parsers, syntax errors,
unfinished comments, unknown syntax nodes, and preservation failures leave the
buffer untouched. Range formatting, mappings, and formatting on save are outside
this implementation.

## Preset choices

The implementation plan confirms this preset and a configurable width. The
reference file demonstrates syntax and layout examples; its incidental spacing
is not a separate preference. The alternatives below are documentation, not
additional configuration switches. Two-space indentation, paragraph groups,
leading separators, and preservation of literal/comment examples were originally
inferred from that reference; the supplied plan makes them the initial defaults.

| Choice | Reasonable alternatives | Initial default |
|---|---|---|
| Line width | 80, 100, another positive width | **100**, configurable to 80 |
| Existing expression breaks | Preserve multiline groups; recompute | Recompute according to width |
| Indentation | Two spaces; four spaces; tabs | Two spaces |
| Continuations | Indent; align under a token | Two-space expressions; declaration parameters four spaces beyond the declaration |
| Short constructs | Inline; always expand | Inline when they fit |
| Long declarations | Break parameters; break only body | Break parameters when necessary; body below `=` |
| Long result annotations | Beside final parameter; separate line | Separate continuation when necessary; `:[E]` |
| Records and lists | Compact; spaced interiors | `{ field = value }`, `[ first, second ]`; compact empty forms |
| Argument groups | Compact; spaced | `{A}`, `{~e : T}`, `{?e : T}` |
| Multiline separators | Trailing; leading commas | Leading commas |
| Opening delimiters | Alone; beside first element | Beside first element |
| Closing delimiters | Separate; attached | Separate for broken records/lists; attached for parentheses |
| Applications | One argument per line; pack | Pack arguments that fit |
| Broken operators | Trailing; leading | Leading, including `\|>` and existing string `+` chains |
| Match arrows | Align; single spaces | One space around `=>` |
| Assignment signs | Single spaces; align simple groups | Align adjacent simple one-line bindings if the padded group fits |
| Matches | Always expanded; width-dependent | Compact when they fit; otherwise separate clauses and long bodies |
| Long match scrutinees | Keep header; split | `match`, indented scrutinee, then `with` as necessary |
| Local definitions | Compact; expanded | Compact when possible; expanded definitions, `in`, final expression align |
| Blank lines | Canonical; logical groups | Preserve declaration paragraphs; normalize excess blank lines |
| Ordinary comments | Preserve wrapping; reflow | Reflow prose; preserve paragraphs, inline placement, examples, directives |
| Documentation | Repeated `##`; block | One-line `##` when it fits; otherwise one `{## … ##}` block |
| Long literals | Overflow; concatenate | Preserve contents; wrap existing concatenations only |

Align `=` only in consecutive simple bindings:

```fram
let first      = 1
let longerName = 2
```

Blank lines, comments, other definition kinds, and complex/multiline bindings end
a group. Alignment must not exceed the width. Paragraph boundaries normalize to
one blank line inside blocks and two between top-level sections.

The formatter preserves identifiers, operators, parentheses, literal fragments,
escapes, and interpolation meaning. Expressions inside interpolation are formatted
while the surrounding string bytes stay intact. It reparses the output and
compares the concrete non-comment structure and literal bytes before editing.
It also checks comment text and positions relative to code tokens. Tagged block
comments, fenced examples, URLs, and directives stay intact; indivisible tokens
and protected content may overflow. Documentation blocks choose a closing tag
that cannot occur in their contents.

## Existing `:Format` dispatcher

Add a Fram branch to your own dispatcher's callback:

```lua
if vim.bo.filetype == 'fram' then
  require('fram').format()
  return
end
-- Existing formatting branches follow.
```

The plugin does not create or replace `:Format`.

## Verification

From `fram.nvim`, run the isolated headless checks with Neovim 0.11 or newer:

```sh
/opt/nvim-linux-x86_64/bin/nvim --headless -u NONE -i NONE \
  -l tests/format.lua /path/to/parser/fram.so
```

The fixtures cover both 80 and 100 columns. The checks exercise rendering,
idempotence, literals/interpolation, protected comments, documentation delimiter
collisions, paragraph boundaries, assignment alignment, setup, commands, undo,
unchanged buffers, and rejection paths. `tests/compiler.lua` additionally checks
the compiler's successful examples and the reference with `dbl`.

```sh
/opt/nvim-linux-x86_64/bin/nvim --headless -u NONE -i NONE \
  -l tests/compiler.lua /path/to/parser/fram.so /path/to/compiler/repo \
  /path/to/bundled/apply_patch
```

The compiler harness uses temporary files created and removed by `apply_patch`.
It compares successful runs and program output before and after formatting at
both widths. The reference enables every test tag; the compiler success suite
runs normally because some examples deliberately contain invalid tagged code.
