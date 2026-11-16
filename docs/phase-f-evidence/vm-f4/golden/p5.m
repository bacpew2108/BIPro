let
    cell = (v) => if v = null then "~" else Text.From(v),
    line = (r as list) => Text.Combine(List.Transform(r, cell), ","),
    exp = (name as text, f as function) => let r = try f() in if r[HasError] then {{name, "ERR " & r[Error][Message]}} else {{name, "n=" & Text.From(Table.RowCount(r[Value])) & " cols=" & Text.Combine(Table.ColumnNames(r[Value]), "|")}} & List.Transform(Table.ToRows(r[Value]), each {name, line(_)}),
    L = #table({"K","L"}, {{3,"l3"},{1,"l1"},{2,"l2"},{1,"l1b"},{5,"l5"}}),
    R = #table({"K2","R"}, {{2,"r2"},{1,"r1"},{3,"r3"},{3,"r3b"},{9,"r9"}}),
    P1 = #table({"K","P","V"}, {{"z","a",1},{"x","a",2},{"y","a",3},{"x","b",4}}),
    P2 = #table({"K","P","V"}, {{10,"a",1},{9,"a",2},{2,"a",3},{null,"a",4}}),
    rows = List.Combine({
        exp("pivNum", () => Table.Pivot(P2, {"a"}, "P", "V", List.Sum)),
        exp("pivMulti", () => Table.Pivot(#table({"K1","K2","P","V"}, {{2,"b","a",1},{2,"a","a",2},{1,"z","a",3},{1,"b","a",4}}), {"a"}, "P", "V", List.Sum)),
        exp("grpDesc", () => Table.Group(#table({"K","V"}, {{10,1},{9,2},{2,3},{9,4}}), {"K"}, {{"S", each List.Sum([V]), type number}}))
    }),
    out = #table({"Exp","Row"}, rows)
in
    out
