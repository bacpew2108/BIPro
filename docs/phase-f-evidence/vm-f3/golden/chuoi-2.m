let
    Source = Excel.Workbook(File.Contents("C:\Users\Bacpew\f3\sales_2026.xlsx"), null, true),
    Sales_Sheet = Source{[Item="Sales",Kind="Sheet"]}[Data],
    #"Promoted Headers" = Table.PromoteHeaders(Sales_Sheet, [PromoteAllScalars=true]),
    #"Changed Type" = Table.TransformColumnTypes(#"Promoted Headers",{{"OrderID", Int64.Type}, {"OrderDate", type date}, {"Region", type text}, {"CustomerID", Int64.Type}, {"Product", type text}, {"Qty", Int64.Type}, {"Price", type number}, {"Amount", type number}}),
    #"Kept First Rows" = Table.FirstN(#"Changed Type",100),
    #"Removed Columns" = Table.RemoveColumns(#"Kept First Rows",{"Price"}),
    #"Removed Top Rows" = Table.Skip(#"Removed Columns",2),
    #"Changed Type1" = Table.TransformColumnTypes(#"Removed Top Rows",{{"Region", Int64.Type}}),
    #"Replaced Errors" = Table.ReplaceErrorValues(#"Changed Type1", {{"Region", 0}})
in
    #"Replaced Errors"