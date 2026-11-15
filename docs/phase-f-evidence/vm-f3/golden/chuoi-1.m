let
    Source = Excel.Workbook(File.Contents("C:\Users\Bacpew\f3\sales_2026.xlsx"), null, true),
    Sales_Sheet = Source{[Item="Sales",Kind="Sheet"]}[Data],
    #"Promoted Headers" = Table.PromoteHeaders(Sales_Sheet, [PromoteAllScalars=true]),
    #"Changed Type" = Table.TransformColumnTypes(#"Promoted Headers",{{"OrderID", Int64.Type}, {"OrderDate", type date}, {"Region", type text}, {"CustomerID", Int64.Type}, {"Product", type text}, {"Qty", Int64.Type}, {"Price", type number}, {"Amount", type number}}),
    #"Sorted Rows" = Table.Sort(#"Changed Type",{{"OrderDate", Order.Ascending}}),
    #"Removed Columns" = Table.RemoveColumns(#"Sorted Rows",{"Price"}),
    #"Renamed Columns" = Table.RenameColumns(#"Removed Columns",{{"Region", "Vung"}}),
    #"Replaced Value" = Table.ReplaceValue(#"Renamed Columns","North","Bac",Replacer.ReplaceText,{"Vung"}),
    #"Filtered Rows" = Table.SelectRows(#"Replaced Value", each ([Qty] = 1 or [Qty] = 2)),
    #"Added Index" = Table.AddIndexColumn(#"Filtered Rows", "Index", 0, 1, Int64.Type),
    #"Added Custom" = Table.AddColumn(#"Added Index", "Custom", each [Qty] * 2),
    #"Reversed Rows" = Table.ReverseRows(#"Added Custom"),
    #"Filled Down" = Table.FillDown(#"Reversed Rows",{"Vung"}),
    #"Split Column by Delimiter" = Table.SplitColumn(#"Filled Down", "Vung", Splitter.SplitTextByDelimiter(" ", QuoteStyle.Csv), {"Vung.1", "Vung.2"}),
    #"Changed Type1" = Table.TransformColumnTypes(#"Split Column by Delimiter",{{"Vung.1", type text}, {"Vung.2", type text}}),
    #"Uppercased Text" = Table.TransformColumns(#"Changed Type1",{{"Product", Text.Upper, type text}}),
    #"Grouped Rows" = Table.Group(#"Uppercased Text", {"Product"}, {{"Count", each Table.RowCount(_), Int64.Type}}),
    #"Unpivoted Other Columns" = Table.UnpivotOtherColumns(#"Grouped Rows", {"Product"}, "Attribute", "Value"),
    #"Pivoted Column" = Table.Pivot(#"Unpivoted Other Columns", List.Distinct(#"Unpivoted Other Columns"[Attribute]), "Attribute", "Value", List.Sum)
in
    #"Pivoted Column"