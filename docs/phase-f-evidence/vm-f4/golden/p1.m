let
    C = #table({"ID","Name"}, {{1,"An"},{2,"Bi"},{null,"Zed"}}),
    O = #table({"OID","Cust"}, {{10,1},{11,1},{12,9},{13,null}}),
    cell = (v) => if v = null then "~" else Text.From(v),
    line = (r as list) => Text.Combine(List.Transform(r, cell), ","),
    exp = (name as text, f as function) => let r = try f() in if r[HasError] then {{name, "ERR " & r[Error][Message]}} else {{name, "n=" & Text.From(Table.RowCount(r[Value])) & " cols=" & Text.Combine(Table.ColumnNames(r[Value]), "|")}} & List.Transform(Table.ToRows(r[Value]), each {name, line(_)}),
    rows = List.Combine({
        exp("inner", () => Table.Join(C, "ID", O, "Cust", JoinKind.Inner)),
        exp("left", () => Table.Join(C, "ID", O, "Cust", JoinKind.LeftOuter)),
        exp("right", () => Table.Join(C, "ID", O, "Cust", JoinKind.RightOuter)),
        exp("full", () => Table.Join(C, "ID", O, "Cust", JoinKind.FullOuter)),
        exp("lanti", () => Table.Join(C, "ID", O, "Cust", JoinKind.LeftAnti)),
        exp("ranti", () => Table.Join(C, "ID", O, "Cust", JoinKind.RightAnti)),
        exp("nRight", () => Table.ExpandTableColumn(Table.NestedJoin(C, "ID", O, "Cust", "N", JoinKind.RightOuter), "N", {"OID"})),
        exp("nFull", () => Table.ExpandTableColumn(Table.NestedJoin(C, "ID", O, "Cust", "N", JoinKind.FullOuter), "N", {"OID"}))
    }),
    out = #table({"Exp","Row"}, rows)
in
    out
