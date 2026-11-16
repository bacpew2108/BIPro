let
    cell = (v) => if v = null then "~" else Text.From(v),
    line = (r as list) => Text.Combine(List.Transform(r, cell), ","),
    exp = (name as text, f as function) => let r = try f() in if r[HasError] then {{name, "ERR " & r[Error][Message]}} else {{name, "n=" & Text.From(Table.RowCount(r[Value])) & " cols=" & Text.Combine(Table.ColumnNames(r[Value]), "|")}} & List.Transform(Table.ToRows(r[Value]), each {name, line(_)}),
    P = #table({"K","P","V"}, {{2,"a",3},{1,"a",1},{1,"b",2},{1,"b",5}}),
    W = #table({"Id","Q1","Q2"}, {{1,10,20},{2,null,5}}),
    rows = List.Combine({
        exp("pivotSum", () => Table.Pivot(P, {"a","b"}, "P", "V", List.Sum)),
        exp("pivotNoAgg", () => Table.Pivot(P, {"a","b"}, "P", "V")),
        exp("pivotNoAggOk", () => Table.Pivot(Table.FirstN(P, 3), {"a","b"}, "P", "V")),
        exp("unpivotOther", () => Table.UnpivotOtherColumns(W, {"Id"}, "A", "Val")),
        exp("unpivot", () => Table.Unpivot(W, {"Q1","Q2"}, "A", "Val")),
        exp("grpCount", () => Table.Group(W, {"Id"}, {{"Count", each Table.RowCount(_), Int64.Type}})),
        exp("grpMedian", () => Table.Group(P, {"P"}, {{"M", each List.Median([V]), type nullable number}, {"Mx", each List.Max([V]), type nullable number}, {"D", each Table.RowCount(Table.Distinct(_)), Int64.Type}}))
    }),
    out = #table({"Exp","Row"}, rows)
in
    out
