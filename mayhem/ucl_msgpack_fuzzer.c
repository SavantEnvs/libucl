#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ucl.h"

/*
 * Mining harness: parse the msgpack input from a private heap buffer without
 * UCL_PARSER_ZEROCOPY, release the parser and the buffer, then read the tree
 * back. The parsed objects must own their strings, so any value still pointing
 * into the released input is a use-after-free when it is emitted.
 */
int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
	if (size < 3) {
		return 0;
	}

	unsigned char *buf = malloc(size);
	if (buf == NULL) {
		return 0;
	}
	memcpy(buf, data, size);

	struct ucl_parser *parser = ucl_parser_new(UCL_PARSER_KEY_LOWERCASE);
	if (parser == NULL) {
		free(buf);
		return 0;
	}

	ucl_object_t *obj = NULL;
	if (ucl_parser_add_chunk_full(parser, buf, size,
			0, UCL_DUPLICATE_APPEND, UCL_PARSE_MSGPACK)) {
		obj = ucl_parser_get_object(parser);
	}

	ucl_parser_free(parser);
	free(buf);

	if (obj != NULL) {
		unsigned char *out = ucl_object_emit(obj, UCL_EMIT_JSON_COMPACT);
		free(out);
		out = ucl_object_emit(obj, UCL_EMIT_MSGPACK);
		free(out);
		ucl_object_unref(obj);
	}

	return 0;
}
