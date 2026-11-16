let
    cell = (v) => if v = null then "~" else Text.From(v),
    line = (r as list) => Text.Combine(List.Transform(r, cell), ","),
    exp = (name as text, f as function) => let r = try f() in if r[HasError] then {{name, "ERR " & r[Error][Message]}} else {{name, "n=" & Text.From(Table.RowCount(r[Value])) & " cols=" & Text.Combine(Table.ColumnNames(r[Value]), "|")}} & List.Transform(Table.ToRows(r[Value]), each {name, line(_)}),
    S = #table({"Reg","V"}, {{"N",1},{"S",2},{"N",3},{"E",4},{"S",5},{null,6},{null,7}}),
    C = #table({"ID","Name"}, {{1,"An"},{2,"Bi"}}),
    O = #table({"OID","Cust"}, {{10,1}}),
    rows = List.Combine({
        exp("grpGlobal", () => Table.Group(S, {"Reg"}, {{"Sum", each List.Sum([V]), type nullable number}, {"N", each Table.RowCount(_), Int64.Type}})),
        exp("grpLocal", () => Table.Group(S, {"Reg"}, {{"N", each Table.RowCount(_), Int64.Type}}, GroupKind.Local)),
        exp("caseJoin", () => Table.Join(#table({"K"}, {{"a"},{"A"}}), "K", #table({"K2","V"}, {{"a",1},{"A",2}}), "K2")),
        exp("typeJoin", () => Table.Join(#table({"K"}, {{1}}), "K", #table({"K2"}, {{"1"}}), "K2")),
        exp("dupCols", () => Table.Join(C, "ID", C, "ID")),
        exp("nestedDef", () => Table.ExpandTableColumn(Table.NestedJoin(C, "ID", O, "Cust", "N"), "N", {"OID"})),
        exp("combine", () => Table.Combine({#table({"A","B"}, {{1,"x"}}), #table({"B","C"}, {{"y",true}})})),
        exp("combMixed", () => Table.Combine({#table({"A"}, {{1}}), #table({"A"}, {{"x"}})})),
        exp("expandDup", () => Table.ExpandTableColumn(Table.NestedJoin(C, "ID", O, "Cust", "N"), "N", {"OID"}, {"ID"}))
    }),
    out = #table({"Exp","Row"}, rows)
in
    out
