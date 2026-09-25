#include <stdint.h>
#include <stdlib.h>
#include <string.h>

int32_t loadu(void *path, int32_t length) {
    free(path);
    return length > 0;
}

int32_t unload(void) { return 1; }

void *request(void *input, int32_t *length) {
    const char *response = "SAORI/1.0 200 OK\r\nCharset: UTF-8\r\nResult: value\r\nValue0: extra\r\n\r\n";
    if (!input || !length || *length <= 0) { free(input); return NULL; }
    const char *wire = input;
    int valid = memmem(wire, (size_t)*length, "Argument0: sample", strlen("Argument0: sample")) != NULL;
    free(input);
    *length = 0;
    if (!valid) return NULL;
    size_t size = strlen(response);
    char *output = malloc(size);
    if (!output) return NULL;
    memcpy(output, response, size);
    *length = (int32_t)size;
    return output;
}
