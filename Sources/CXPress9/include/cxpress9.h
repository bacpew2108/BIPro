#ifndef CXPRESS9_H
#define CXPRESS9_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque XPress9 decoder. One decoder carries one history window, so the chunks
/// of a single stream must be decoded in order through the same decoder.
typedef struct cxpress9_decoder cxpress9_decoder;

/// Returns NULL on allocation/initialisation failure.
cxpress9_decoder *cxpress9_decoder_create(void);
void cxpress9_decoder_destroy(cxpress9_decoder *decoder);

/// Decodes one compressed chunk into `output`.
/// Returns the number of bytes written, or -1 on error (message in `error`, if given).
int64_t cxpress9_decode_chunk(cxpress9_decoder *decoder,
                              const uint8_t *input, uint32_t input_size,
                              uint8_t *output, uint32_t output_capacity,
                              char *error, uint32_t error_capacity);

/// Opaque XPress9 encoder, level 9 (MTF 4 entries, lookup depth 9, 4 MiB window).
/// One encoder carries one history window: chunks encoded through the same encoder
/// may refer back to earlier chunks, so they must be decoded in the same order.
typedef struct cxpress9_encoder cxpress9_encoder;

/// Returns NULL on allocation/initialisation failure. Creating an encoder is
/// expensive (about 37 MB of tables), so reuse one per stream where possible.
cxpress9_encoder *cxpress9_encoder_create(void);
void cxpress9_encoder_destroy(cxpress9_encoder *encoder);

/// Encodes one chunk of `input_size` bytes into `output`.
/// Returns the number of compressed bytes, or -1 on error (message in `error`, if given).
/// Fails when the compressed data does not fit into `output_capacity`.
int64_t cxpress9_encode_chunk(cxpress9_encoder *encoder,
                              const uint8_t *input, uint32_t input_size,
                              uint8_t *output, uint32_t output_capacity,
                              char *error, uint32_t error_capacity);

#ifdef __cplusplus
}
#endif

#endif
