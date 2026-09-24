/* Synthetic C consumer: compile against the public header, load an actual dylib. */
#include "misaka_host_bridge.h"
#include <assert.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static uint32_t (*version)(void);
static int32_t (*create)(const UMConfig *, const UMHostV1 *, uint64_t *, UMBuffer *);
static int32_t (*request)(uint64_t, const uint8_t *, uint32_t, UMBuffer *);
static int32_t (*destroy)(uint64_t, UMBuffer *);
static int32_t (*discard)(uint64_t);
static void (*release)(UMBuffer *);
static const char boot[] = "GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnBoot\r\n\r\n";
static const char saori[] = "GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnSaori\r\n\r\n";
static UMBytes bytes(const char *s) { return (UMBytes){(const uint8_t *)s, (uint32_t)strlen(s)}; }
typedef struct { uint64_t session; int releases, calls, fail; } Host;

static int32_t service(void *context, uint32_t operation, UMBytes path,
                       const UMBytes *args, uint32_t count, UMBuffer *result) {
    Host *host = context;
    assert(path.length == 8 && memcmp(path.data, "test.dll", 8) == 0);
    if (operation == UM_SAORI_LOAD || operation == UM_SAORI_UNLOAD) {
        assert(count == 0); host->calls++; return UM_OK;
    }
    assert(operation == UM_SAORI_CALL);
    assert(count == 1 && args[0].length == 3 && memcmp(args[0].data, "arg", 3) == 0);
    UMBuffer nested = {0};
    assert(request(host->session, (const uint8_t *)boot, strlen(boot), &nested) == UM_BUSY);
    assert(destroy(host->session, &nested) == UM_BUSY);
    host->calls++;
    result->data = (uint8_t *)strdup(host->fail == 2 ? "\xff" : "host-result");
    result->length = host->fail == 2 ? 1 : 11;
    return host->fail == 1 ? 123 : UM_OK;
}
static void host_release(void *context, UMBuffer *buffer) {
    ((Host *)context)->releases++;
    free(buffer->data);
    *buffer = (UMBuffer){0};
}
static void expect_request(uint64_t id, const char *wire, int32_t status, const char *value) {
    UMBuffer response = {0};
    assert(request(id, (const uint8_t *)wire, strlen(wire), &response) == status);
    if (value) {
        char *string = calloc(response.length + 1, 1);
        memcpy(string, response.data, response.length);
        assert(strstr(string, value));
        free(string);
    }
    release(&response);
    assert(response.data == NULL && response.length == 0);
    release(&response);
}
static uint64_t open_session(UMConfig *config, UMHostV1 *host) {
    UMBuffer error = {0}; uint64_t id = 0;
    assert(create(config, host, &id, &error) == UM_OK && id != 0);
    release(&error); return id;
}
static void close_session(uint64_t id) {
    UMBuffer error = {0}; assert(destroy(id, &error) == UM_OK); release(&error);
    assert(destroy(id, &error) == UM_NOT_FOUND);
}

int main(int argc, char **argv) {
    assert(argc == 7); /* library, master, state1, state2, blocked state, init-SAORI master */
    void *library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!library) { fprintf(stderr, "%s\n", dlerror()); return 1; }
#define LOAD(name, symbol) *(void **)(&name) = dlsym(library, symbol); assert(name)
    LOAD(version, "um_api_version"); LOAD(create, "um_create"); LOAD(request, "um_request");
    LOAD(destroy, "um_destroy"); LOAD(discard, "um_discard"); LOAD(release, "um_release");
    assert(version() == UM_ABI_VERSION);
    UMConfig config = {UM_ABI_VERSION, sizeof(UMConfig), bytes(argv[2]), bytes(argv[3])};
    Host context = {0};
    UMHostV1 host = {UM_ABI_VERSION, sizeof(UMHostV1), &context, service, host_release};
    UMBuffer error = {0}; uint64_t id = 42;
    config.abi_version = 99;
    assert(create(&config, &host, &id, &error) == UM_VERSION && id == 0);
    config.abi_version = 1; config.struct_size = 8;
    assert(create(&config, &host, &id, &error) == UM_VERSION);
    config.struct_size = sizeof(config);
    UMHostV1 invalid_host = host; invalid_host.release = NULL;
    assert(create(&config, &invalid_host, &id, &error) == UM_INVALID);
    UMConfig initializing = config; initializing.master_path = bytes(argv[6]);
    assert(create(&initializing, NULL, &id, &error) == UM_HOST && id == 0); release(&error);
    assert(access(argv[3], F_OK) != 0);
    UMConfig invalid = config; invalid.state_path = config.master_path;
    assert(create(&invalid, &host, &id, &error) == UM_INVALID); release(&error);
    context.session = open_session(&config, &host);
    config.state_path = bytes(argv[4]); uint64_t second = open_session(&config, NULL);
    expect_request(context.session, boot, UM_OK, "Value: 1\r\n");
    expect_request(context.session, boot, UM_OK, "Value: 2\r\n");
    expect_request(second, boot, UM_OK, "Value: 1\r\n");
    expect_request(context.session, saori, UM_OK, "Value: host-result\r\n");
    expect_request(context.session, "GET PLUGIN/2.0\r\nCharset: UTF-8\r\nID: OnEcho\r\nReference0: plugin\r\n\r\n", UM_OK, "PLUGIN/2.0 200 OK\r\n");
    expect_request(context.session, "GET UNKNOWN/1.0\r\nID: OnBoot\r\n\r\n", UM_INVALID, NULL);
    context.fail = 1;
    expect_request(context.session, saori, UM_HOST, "callback failed");
    context.fail = 2;
    expect_request(context.session, saori, UM_HOST, "invalid UTF-8");
    context.fail = 0;
    expect_request(context.session, "GET SHIORI/3.0\r\nID: OnLoad\r\n\r\n", UM_OK, "Value: loaded\r\n");
    expect_request(context.session, "GET SHIORI/3.0\r\nID: OnUnload\r\n\r\n", UM_OK, "Value: unloaded\r\n");
    assert(context.calls == 5 && context.releases == 3);
    expect_request(second, "GET SHIORI/3.0\r\nID: OnEcho\r\nReference0: 日本語\r\n\r\n", UM_OK, "Value: 日本語\r\n");
    expect_request(second, saori, UM_HOST, "unavailable");
    expect_request(second, "invalid", UM_INVALID, NULL);
    expect_request(second, "GET SHIORI/3.0\nID: OnBoot\r\n\r\n", UM_INVALID, NULL);
    expect_request(second, "GET SHIORI/3.0\r\n\r\nID: OnBoot\r\n\r\n", UM_INVALID, NULL);
    expect_request(second, "GET SHIORI/3.0\r\nCharset: Shift_JIS\r\nID: OnBoot\r\n\r\n", UM_INVALID, NULL);
    assert(request(second, NULL, 5, &error) == UM_INVALID);
    assert(request(second, (const uint8_t *)boot, UM_MAX_BYTES + 1, &error) == UM_INVALID);
    close_session(context.session);
    expect_request(context.session, boot, UM_NOT_FOUND, NULL);
    expect_request(second, boot, UM_OK, "Value: 2\r\n");
    close_session(second);
    config.state_path = bytes(argv[3]); id = open_session(&config, NULL);
    expect_request(id, boot, UM_OK, "Value: 3\r\n"); close_session(id);
    config.state_path = bytes(argv[5]); id = open_session(&config, NULL);
    assert(destroy(id, &error) == UM_ENGINE); release(&error);
    /* Remove the regular file blocking the state directory; failed destroy is retryable. */
    char *parent = strdup(argv[5]); *strrchr(parent, '/') = '\0'; assert(unlink(parent) == 0); free(parent);
    expect_request(id, boot, UM_OK, "Value: 1\r\n"); close_session(id);
    id = open_session(&config, NULL);
    expect_request(id, boot, UM_OK, "Value: 2\r\n");
    assert(discard(id) == UM_OK && discard(id) == UM_NOT_FOUND);
    id = open_session(&config, NULL);
    expect_request(id, boot, UM_OK, "Value: 2\r\n"); close_session(id);
    dlclose(library);
    puts("C ABI passed: independent sessions, persistence, host ownership, reentry, errors, retry");
    return 0;
}
