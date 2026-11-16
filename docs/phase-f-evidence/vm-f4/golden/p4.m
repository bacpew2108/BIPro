let
    cell = (v) => if v = null then "~" else Text.From(v),
    line = (r as list) => Text.Combine(List.Transform(r, cell), ","),
    exp = (name as text, f as function) => let r = try f() in if r[HasError] then {{name, "ERR " & r[Error][Message]}} else {{name, "n=" & Text.From(Table.RowCount(r[Value])) & " cols=" & Text.Combine(Table.ColumnNames(r[Value]), "|")}} & List.Transform(Table.ToRows(r[Value]), each {name, line(_)}),
    L = #table({"K","L"}, {{3,"l3"},{1,"l1"},{2,"l2"},{1,"l1b"},{5,"l5"}}),
    R = #table({"K2","R"}, {{2,"r2"},{1,"r1"},{3,"r3"},{3,"r3b"},{9,"r9"}}),
    P1 = #table({"K","P","V"}, {{"z","a",1},{"x","a",2},{"y","a",3},{"x","b",4}}),
    P2 = #table({"K","P","V"}, {{10,"a",1},{9,"a",2},{2,"a",3},{null,"a",4}}),
    rows = List.Combine({
        exp("inner", () => Table.Join(L, "K", R, "K2", JoinKind.Inner)),
        exp("left", () => Table.Join(L, "K", R, "K2", JoinKind.LeftOuter)),
        exp("right", () => Table.Join(L, "K", R, "K2", JoinKind.RightOuter)),
        exp("full", () => Table.Join(L, "K", R, "K2", JoinKind.FullOuter)),
        exp("pivText", () => Table.Pivot(P1, {"a","b"}, "P", "V", List.Sum)),
        exp("pivNum", () => Table.Pivot(P2, {"a"}, "P", "V", List.Sum))
    }),
    out = #table({"Exp","Row"}, rows)
in
    out
