let
    R = (f as function) =>
        let t = try f()
        in if t[HasError] then "ERR: " & t[Error][Reason] & " / " & t[Error][Message]
           else (try Text.From(t[Value]) otherwise "VAL:" & Text.FromBinary(Json.FromValue(t[Value]))),
    rows = {
        {"1  null < 1", R(() => null < 1)},
        {"1b null >= 1", R(() => null >= 1)},
        {"2  a & null", R(() => "a" & null)},
        {"3  date = datetime", R(() => #date(2026,1,1) = #datetime(2026,1,1,0,0,0))},
        {"3b date < datetime", R(() => #date(2026,1,1) < #datetime(2026,1,2,0,0,0))},
        {"4  B < a", R(() => "B" < "a")},
        {"5  record order", R(() => [a=1,b=2] = [b=2,a=1])},
        {"6  lazy arg", R(() => ((x) => 1)(error "boom"))},
        {"7  schema 1", R(() => Table.Schema(#table({"A"}, {{1}}))[TypeName]{0})},
        {"7b schema mixed", R(() => Table.Schema(#table({"A"}, {{1}, {"x"}}))[TypeName]{0})},
        {"8  1..5", R(() => {1..5})},
        {"8b 5..1", R(() => {5..1})},
        {"9  +1", R(() => +1)},
        {"9b +null", R(() => +null)},
        {"11 1/0", R(() => 1/0)},
        {"11b 0/0", R(() => 0/0)},
        {"12 each [A] on number", R(() => (each [A])(1))},
        {"13 meta", R(() => Value.Metadata(1 meta [a=1])[a])},
        {"14 Text.Upper(null)", R(() => Text.Upper(null))},
        {"15 List.Sum({})", R(() => List.Sum({}))},
        {"16 Number.From(""1,5"")", R(() => Number.From("1,5"))},
        {"17 Text.Length(null)", R(() => Text.Length(null))},
        {"18 {1,2}&{3}", R(() => {1,2} & {3})},
        {"19 1 = 1.0", R(() => 1 = 1.0)},
        {"20 ""a"" = ""A""", R(() => "a" = "A")}
    }
in
    #table({"Test", "Ket qua"}, rows)
