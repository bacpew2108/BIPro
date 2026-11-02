Vendored from https://github.com/Hugoberry/xpress9-python @ ff81bd9f93601650243a2695d1ad5940c7fbadd0
Original XPress9 sources: Copyright (c) Microsoft Corporation, MIT License (see LICENSE).

Decoder subset (unchanged): Xpress9DecLz77.c, Xpress9DecHuffman.c, Xpress9Misc.c.
Encoder (added for WP1, unchanged from upstream): Xpress9EncLz77.c, Xpress9EncHuffman.c.
Encoder includes (internal/, unchanged): Xpress9Lz77EncInsert.i, Xpress9Lz77EncPass1.i,
Xpress9Lz77EncPass2.i, Xpress9ZobristTable.h. Xpress9Lookup.i2/.i3 are used by the encoder too.
Not vendored: Xpress9Wrapper.c/.h (reference only; cxpress9.c replaces it) and
Xpress9Amd64Insert.i (only included under XPRESS9_USE_SSE2, which is 0 here).
Shim (own code): cxpress9.c, include/cxpress9.h.
