#include <assert.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void *owned(const char *text) {
    size_t n = strlen(text);
    void *p = malloc(n ? n : 1);
    assert(p);
    memcpy(p, text, n);
    return p;
}

int main(int argc, char **argv) {
    assert(argc == 3);
    void *library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!library) { fprintf(stderr, "%s\n", dlerror()); return 1; }
    int32_t (*load)(void *, int32_t) = dlsym(library, "loadu");
    int32_t (*unload)(void) = dlsym(library, "unload");
    void *(*request)(void *, int32_t *) = dlsym(library, "request");
    assert(load && unload && request && dlsym(library, "load"));
    const char *wire = "GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnBoot\r\n\r\n";
    assert(load(owned(argv[2]), (int32_t)strlen(argv[2])) == 1);
    assert(load(owned(argv[2]), (int32_t)strlen(argv[2])) == 0);
    int32_t n = (int32_t)strlen(wire);
    char *result = request(owned(wire), &n);
    assert(result && n > 0);
    char *text = calloc((size_t)n + 1, 1);
    assert(text); memcpy(text, result, (size_t)n); free(result);
    assert(strstr(text, "Value: 1\r\n")); free(text);
    assert(unload() == 1);
    n = (int32_t)strlen(wire);
    assert(request(owned(wire), &n) == NULL && n == 0);
    assert(load(owned(argv[2]), (int32_t)strlen(argv[2])) == 1);
    n = (int32_t)strlen(wire);
    result = request(owned(wire), &n);
    assert(result && n > 0);
    text = calloc((size_t)n + 1, 1);
    assert(text); memcpy(text, result, (size_t)n); free(result);
    assert(strstr(text, "Value: 2\r\n")); free(text);
    assert(unload() == 1);
    assert(unload() == 1);
    assert(load(owned("relative"), 8) == 0);
    assert(dlclose(library) == 0);
    puts("PASS conventional SHIORI: entry points, transferred buffers, duplicate load, save/reload");
}
