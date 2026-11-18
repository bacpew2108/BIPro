let
    Source = Table.FromRows(Json.Document(Binary.Decompress(Binary.FromText("i45WOtyYr1CSUZqnpKNkaAQkch/unp2pFKsTrRRY+nDX8jyFrNREkKQpEIOF3TMPL6gEcXSUko+uBAv5AmkdJWM9kJojEx/u7geLhhzelalQcXhhcgZQWNccSFQoxcYCAA==", BinaryEncoding.Base64), Compression.Deflate)), let _t = ((type nullable text) meta [Serialized.Text = true]) in type table [#"﻿Tên" = _t, #"Số lượng" = _t, #"Ghi chú" = _t]),
    #"Changed Type" = Table.TransformColumnTypes(Source,{{"﻿Tên", type text}, {"Số lượng", type number}, {"Ghi chú", type text}})
in
    #"Changed Type"