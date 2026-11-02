#include "cxpress9.h"
#include "Xpress9Internal.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct cxpress9_decoder {
    XPRESS9_DECODER decoder;
};

static void *cx_alloc(void *context, int size) {
    (void)context;
    return malloc((size_t)size);
}

static void cx_free(void *context, void *address) {
    (void)context;
    free(address);
}

static void cx_set_error(char *error, uint32_t capacity, const char *stage, const XPRESS9_STATUS *status) {
    if (error == NULL || capacity == 0) return;
    snprintf(error, capacity, "%s failed (status %u): %s", stage, (unsigned)status->m_uStatus, status->m_ErrorDescription);
}

cxpress9_decoder *cxpress9_decoder_create(void) {
    XPRESS9_STATUS status;
    memset(&status, 0, sizeof(status));
    cxpress9_decoder *result = (cxpress9_decoder *)malloc(sizeof(cxpress9_decoder));
    if (result == NULL) return NULL;
    result->decoder = Xpress9DecoderCreate(&status, NULL, cx_alloc, XPRESS9_WINDOW_SIZE_LOG2_MAX, 0);
    if (result->decoder == NULL || status.m_uStatus != Xpress9Status_OK) {
        free(result);
        return NULL;
    }
    Xpress9DecoderStartSession(&status, result->decoder, 1);
    if (status.m_uStatus != Xpress9Status_OK) {
        Xpress9DecoderDestroy(&status, result->decoder, NULL, cx_free);
        free(result);
        return NULL;
    }
    return result;
}

void cxpress9_decoder_destroy(cxpress9_decoder *decoder) {
    if (decoder == NULL) return;
    XPRESS9_STATUS status;
    memset(&status, 0, sizeof(status));
    if (decoder->decoder != NULL) {
        Xpress9DecoderDestroy(&status, decoder->decoder, NULL, cx_free);
    }
    free(decoder);
}

int64_t cxpress9_decode_chunk(cxpress9_decoder *decoder,
                              const uint8_t *input, uint32_t input_size,
                              uint8_t *output, uint32_t output_capacity,
                              char *error, uint32_t error_capacity) {
    XPRESS9_STATUS status;
    memset(&status, 0, sizeof(status));
    if (decoder == NULL || decoder->decoder == NULL) {
        if (error && error_capacity) snprintf(error, error_capacity, "decoder is NULL");
        return -1;
    }

    // The decoder API takes non-const pointers but never writes to the input.
    void *in = (void *)input;
    Xpress9DecoderAttach(&status, decoder->decoder, in, input_size);
    if (status.m_uStatus != Xpress9Status_OK) {
        cx_set_error(error, error_capacity, "attach", &status);
        return -1;
    }

    int64_t written_total = 0;
    unsigned remaining;
    do {
        unsigned written = 0;
        unsigned consumed = 0;
        remaining = Xpress9DecoderFetchDecompressedData(&status, decoder->decoder,
                                                        output + written_total,
                                                        output_capacity - (unsigned)written_total,
                                                        &written, &consumed);
        if (status.m_uStatus != Xpress9Status_OK) {
            cx_set_error(error, error_capacity, "fetch", &status);
            written_total = -1;
            break;
        }
        if (written == 0) break;
        written_total += written;
    } while (remaining != 0 && (uint32_t)written_total < output_capacity);

    XPRESS9_STATUS detach_status;
    memset(&detach_status, 0, sizeof(detach_status));
    Xpress9DecoderDetach(&detach_status, decoder->decoder, in, input_size);
    return written_total;
}

// MARK: - Encoder

struct cxpress9_encoder {
    XPRESS9_ENCODER encoder;
};

// Level 9 settings from Xpress9Wrapper.c (Hugoberry/xpress9-python). The window is
// min(16 + (level - 6) * 2, XPRESS9_WINDOW_SIZE_LOG2_MAX) = 22. m_uMaxStreamLength
// is 0 (no limit): the wrapper's 64 KiB value would reject multi-MB streams.
static void cx_fill_encoder_params(XPRESS9_ENCODER_PARAMS *params) {
    memset(params, 0, sizeof(*params));
    params->m_cbSize = sizeof(*params);
    params->m_uMaxStreamLength = 0;
    params->m_uMtfEntryCount = 4;
    params->m_uLookupDepth = 9;
    params->m_uWindowSizeLog2 = XPRESS9_WINDOW_SIZE_LOG2_MAX;
    params->m_uOptimizationLevel = 0;
    params->m_uPtrMinMatchLength = 4;
    params->m_uMtfMinMatchLength = 2;
}

cxpress9_encoder *cxpress9_encoder_create(void) {
    XPRESS9_STATUS status;
    memset(&status, 0, sizeof(status));
    cxpress9_encoder *result = (cxpress9_encoder *)malloc(sizeof(cxpress9_encoder));
    if (result == NULL) return NULL;
    result->encoder = Xpress9EncoderCreate(&status, NULL, cx_alloc, XPRESS9_WINDOW_SIZE_LOG2_MAX, 0);
    if (result->encoder == NULL || status.m_uStatus != Xpress9Status_OK) {
        free(result);
        return NULL;
    }
    XPRESS9_ENCODER_PARAMS params;
    cx_fill_encoder_params(&params);
    Xpress9EncoderStartSession(&status, result->encoder, &params, 1);
    if (status.m_uStatus != Xpress9Status_OK) {
        Xpress9EncoderDestroy(&status, result->encoder, NULL, cx_free);
        free(result);
        return NULL;
    }
    return result;
}

void cxpress9_encoder_destroy(cxpress9_encoder *encoder) {
    if (encoder == NULL) return;
    XPRESS9_STATUS status;
    memset(&status, 0, sizeof(status));
    if (encoder->encoder != NULL) {
        Xpress9EncoderDestroy(&status, encoder->encoder, NULL, cx_free);
    }
    free(encoder);
}

int64_t cxpress9_encode_chunk(cxpress9_encoder *encoder,
                              const uint8_t *input, uint32_t input_size,
                              uint8_t *output, uint32_t output_capacity,
                              char *error, uint32_t error_capacity) {
    XPRESS9_STATUS status;
    memset(&status, 0, sizeof(status));
    if (encoder == NULL || encoder->encoder == NULL) {
        if (error && error_capacity) snprintf(error, error_capacity, "encoder is NULL");
        return -1;
    }

    // The encoder API takes non-const pointers but never writes to the input.
    const void *in = input;
    Xpress9EncoderAttach(&status, encoder->encoder, in, input_size, 1);
    if (status.m_uStatus != Xpress9Status_OK) {
        cx_set_error(error, error_capacity, "attach", &status);
        return -1;
    }

    int64_t written_total = 0;
    for (;;) {
        unsigned promised = Xpress9EncoderCompress(&status, encoder->encoder, NULL, NULL);
        if (status.m_uStatus != Xpress9Status_OK) {
            cx_set_error(error, error_capacity, "compress", &status);
            written_total = -1;
            break;
        }
        if (promised == 0) break;
        if (written_total + (int64_t)promised > (int64_t)output_capacity) {
            if (error && error_capacity) {
                snprintf(error, error_capacity, "output buffer too small: need more than %u bytes", output_capacity);
            }
            written_total = -1;
            break;
        }
        int64_t batch_start = written_total;
        unsigned remaining;
        do {
            unsigned fetched = 0;
            remaining = Xpress9EncoderFetchCompressedData(&status, encoder->encoder,
                                                          output + written_total,
                                                          output_capacity - (unsigned)written_total,
                                                          &fetched);
            if (status.m_uStatus != Xpress9Status_OK) {
                cx_set_error(error, error_capacity, "fetch", &status);
                written_total = -1;
                break;
            }
            written_total += fetched;
        } while (remaining != 0);
        if (written_total < 0) break;
        if (written_total - batch_start != (int64_t)promised) {
            if (error && error_capacity) {
                snprintf(error, error_capacity, "encoder promised %u bytes, fetched %lld",
                         promised, (long long)(written_total - batch_start));
            }
            written_total = -1;
            break;
        }
    }

    XPRESS9_STATUS detach_status;
    memset(&detach_status, 0, sizeof(detach_status));
    Xpress9EncoderDetach(&detach_status, encoder->encoder, in, input_size);
    return written_total;
}
