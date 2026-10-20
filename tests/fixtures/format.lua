return {
  {
    name = "argument packing",
    source = "let result = transform firstArgument secondArgument thirdArgument fourthArgument fifthArgument\n",
    [80] = "let result =\n  transform firstArgument secondArgument thirdArgument fourthArgument\n    fifthArgument\n",
    [100] = "let result = transform firstArgument secondArgument thirdArgument fourthArgument fifthArgument\n",
  },
  {
    name = "leading record separators",
    source = "let result = {firstField=firstValue,secondField=secondValue,thirdField=thirdValue,fourthField=fourthValue}\n",
    expected = "let result =\n  { firstField = firstValue\n  , secondField = secondValue\n  , thirdField = thirdValue\n  , fourthField = fourthValue\n  }\n",
  },
  {
    name = "declaration parameters and effect annotation",
    source = "let transform {E} (firstParameter : Int) (secondParameter : Int) (thirdParameter : Int) :[E] Int = firstParameter\n",
    [80] = "let transform\n    {E}\n    (firstParameter : Int)\n    (secondParameter : Int)\n    (thirdParameter : Int)\n    :[E] Int =\n  firstParameter\n",
    [100] = "let transform {E} (firstParameter : Int) (secondParameter : Int) (thirdParameter : Int) :[E] Int =\n  firstParameter\n",
  },
  {
    name = "match clauses",
    source = "let f x = match x with | First first => transform first anotherArgument thirdArgument fourthArgument | Second => fallback end\n",
    expected = "let f x =\n  match x with\n  | First first => transform first anotherArgument thirdArgument fourthArgument\n  | Second => fallback\n  end\n",
  },
  {
    name = "alignment boundaries",
    source = "let a=1\nlet longer=2\n\nlet b=3\n# a comment\nlet c=4\ntype T=Int\nlet d=5\nlet f x=x\nlet e=6\n",
    expected = "let a      = 1\nlet longer = 2\n\n\nlet b = 3\n# a comment\nlet c = 4\ntype T = Int\nlet d = 5\nlet f x = x\nlet e = 6\n",
  },
  {
    name = "compact groups and parentheses",
    source = "let f { A } { ~e : Eff E } { ?fmt : Fmt } (x:Int) : [ E ] Int = foo (bar x)\n",
    expected = "let f {A} {~e : Eff E} {?fmt : Fmt} (x : Int) :[E] Int = foo (bar x)\n",
  },
  {
    name = "interpolation and escapes",
    source = [=[let s="keep  \n \x41 \{foo   (bar x)} tail"]=] .. "\n",
    expected = [=[let s = "keep  \n \x41 \{ foo (bar x) } tail"]=] .. "\n",
  },
  {
    name = "optional match bar",
    source = "let x=match () with _=>() end\n",
    expected = "let x = match () with _ => () end\n",
  },
}
