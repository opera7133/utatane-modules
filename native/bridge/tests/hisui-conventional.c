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

static char *send_request(void *(*request)(void *, int32_t *), const char *wire, size_t size, int32_t *length) {
    *length = (int32_t)size;
    return request(owned(wire, size), length);
}

int main(int argc, char **argv) {
    assert(argc == 3);
    void *library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!library) { fprintf(stderr, "%s\n", dlerror()); return 1; }
    int32_t (*load)(void *, int32_t) = dlsym(library, "loadu");
    int32_t (*unload)(void) = dlsym(library, "unload");
    void *(*request)(void *, int32_t *) = dlsym(library, "request");
    assert(load && unload && request && dlsym(library, "load"));
    const char *boot = "GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnBoot\r\n\r\n";
    const char *click = "GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnMouseDoubleClick\r\n\r\n";
    const char *shift_jis = "GET SHIORI/3.0\r\nCharset: Shift_JIS\r\nID: OnEcho\r\nReference0: \x82\xa0\r\n\r\n";
    assert(load(owned(argv[2], strlen(argv[2])), (int32_t)strlen(argv[2])) == 1);
    assert(load(owned(argv[2], strlen(argv[2])), (int32_t)strlen(argv[2])) == 0);
    int32_t n;
    char *result = send_request(request, boot, strlen(boot), &n);
    assert(result && n > 0);
    char *text = calloc((size_t)n + 1, 1);
    assert(text); memcpy(text, result, (size_t)n); free(result);
    assert(strstr(text, "Value: \\0起動\\e\r\n")); free(text);
    result = send_request(request, shift_jis, strlen(shift_jis), &n);
    assert(result && n > 0);
    text = calloc((size_t)n + 1, 1);
    assert(text); memcpy(text, result, (size_t)n); free(result);
    assert(strstr(text, "Charset: Shift_JIS\r\n"));
    assert(strstr(text, "Value: \x82\xa0\r\n")); free(text);
    assert(unload() == 1);
    n = (int32_t)strlen(boot);
    assert(request(owned(boot, (size_t)n), &n) == NULL && n == 0);
    assert(load(owned(argv[2], strlen(argv[2])), (int32_t)strlen(argv[2])) == 1);
    result = send_request(request, click, strlen(click), &n);
    assert(result && n > 0);
    text = calloc((size_t)n + 1, 1);
    assert(text); memcpy(text, result, (size_t)n); free(result);
    assert(strstr(text, "Value: \\0クリック\\e\r\n")); free(text);
    assert(unload() == 1);
    assert(unload() == 1);
    assert(load(owned("relative", 8), 8) == 0);
    assert(dlclose(library) == 0);
    puts("PASS hisui: conventional ABI, UTF-8/Shift_JIS, persisted state");
}
