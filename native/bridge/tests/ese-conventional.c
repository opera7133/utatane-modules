#include <assert.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void *owned(const char *bytes, size_t length) {
    void *result = malloc(length ? length : 1);
    assert(result);
    memcpy(result, bytes, length);
    return result;
}

static char *send_request(void *(*request)(void *, int32_t *), const char *wire, int32_t *length) {
    *length = (int32_t)strlen(wire);
    return request(owned(wire, (size_t)*length), length);
}

int main(int argc, char **argv) {
    assert(argc == 3);
    void *library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!library) { fprintf(stderr, "%s\n", dlerror()); return 1; }
    int32_t (*load)(void *, int32_t) = dlsym(library, "loadu");
    int32_t (*unload)(void) = dlsym(library, "unload");
    void *(*request)(void *, int32_t *) = dlsym(library, "request");
    assert(load && unload && request && dlsym(library, "load"));
    assert(load(owned(argv[2], strlen(argv[2])), (int32_t)strlen(argv[2])) == 1);
    assert(load(owned(argv[2], strlen(argv[2])), (int32_t)strlen(argv[2])) == 0);

    const char *boot = "GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnBoot\r\n\r\n";
    int32_t length;
    char *result = send_request(request, boot, &length);
    assert(result && length > 0);
    char *text = calloc((size_t)length + 1, 1);
    assert(text); memcpy(text, result, (size_t)length); free(result);
    assert(strstr(text, "SHIORI/3.0 200 OK\r\n"));
    assert(strstr(text, "Value: \\1\\s[11]起動\\e\r\n")); free(text);

    const char *probe = "GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnProbe\r\n\r\n";
    result = send_request(request, probe, &length);
    assert(result && length > 0);
    text = calloc((size_t)length + 1, 1);
    assert(text); memcpy(text, result, (size_t)length); free(result);
    assert(strstr(text, "Value: done\r\n")); free(text);

    const char *shift_jis = "GET SHIORI/3.0\r\nCharset: Shift_JIS\r\nID: OnBoot\r\n\r\n";
    result = send_request(request, shift_jis, &length);
    assert(result && length > 0);
    text = calloc((size_t)length + 1, 1);
    assert(text); memcpy(text, result, (size_t)length); free(result);
    assert(strstr(text, "Charset: Shift_JIS\r\n"));
    if (!strstr(text, "Value: \\1\\s[11]")) fprintf(stderr, "Unexpected Shift_JIS response\n");
    assert(strstr(text, "Value: \\1\\s[11]")); free(text);

    assert(unload() == 1);
    assert(unload() == 1);
    length = (int32_t)strlen(boot);
    assert(request(owned(boot, (size_t)length), &length) == NULL && length == 0);
    assert(dlclose(library) == 0);
    puts("PASS ese-shiori: conventional ABI, UTF-8/Shift_JIS, state and file writes");
}
