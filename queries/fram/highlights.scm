[
  "abstr" "aff" "as" "data" "effect" "else" "end" "extern"
  "finally" "fn" "handle" "handler" "handlerfn" "if" "import" "in"
  "label" "let" "match" "method" "module" "of" "open" "parameter"
  "return" "section" "then" "total" "type" "with" "_"
] @keyword
(pub) @keyword
(rec) @keyword

(uid) @constructor
(uid_path) @type
(lid) @variable
(tlid) @variable
(qlid) @variable.parameter
(attribute (lid) @attribute)
(op) @operator

["(" ")" "[" "]" "{" "}" "@{"] @punctuation.bracket
["," "." ":"] @punctuation.delimiter
["=" "|" "/" "->" "->>" "=>" ">."] @operator

(line_comment) @comment @spell
(line_doc_comment) @comment.documentation @spell
(block_comment) @comment @spell
(block_comment_unfinished) @comment @spell

[(num) (num64)] @number
(chr) @character
(str ["\"" (string_content)] @string)
(escape_sequence) @string.escape
(interpolation ["\\{" "}"] @punctuation.special)

(def_let
  (ex_app . (lid) @function) "=")
(def_let
  (ex_app . (_) (lid) @variable.parameter) "=")
(def_let
  (ex_app (ex_annot (lid) @variable.parameter)) "=")
(def_method
  (lid) @function.method "=")
(def_method
  (ex_app . (lid) @function.method) "=")
(ex_app . (lid) @function)
(method (lid) @function.method)
(ex_method (lid) @function.method)
(ex_method_call (lid) @function.method)
(fld_fn . (lid) @function)
(fld_effect_fn . (lid) @function)
