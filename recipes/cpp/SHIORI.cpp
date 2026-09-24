#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <iconv.h>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <vector>

#ifdef YAYA_MODULE
extern "C" long multi_loadu(char *, long);
extern "C" int multi_unload(long);
extern "C" char *multi_request(long, char *, long *);
#else
extern "C" int satori_load(char *, long);
extern "C" int satori_unload(int);
extern "C" char *satori_request(int, char *, long *);
#endif
namespace {
constexpr int32_t limit = 8 * 1024 * 1024;
std::mutex mutex;
long instance = 0;
bool failedUnload = false;
using Buffer = std::unique_ptr<char, decltype(&free)>;
std::string convert(const std::string &input, const char *to, const char *from) {
    iconv_t converter = iconv_open(to, from);
    if (converter == reinterpret_cast<iconv_t>(-1)) throw std::runtime_error("charset");
    std::vector<char> output(input.size() * 4 + 16);
    char *source = const_cast<char *>(input.data()), *destination = output.data();
    size_t remaining = input.size(), available = output.size();
    const auto result = iconv(converter, &source, &remaining, &destination, &available);
    iconv_close(converter);
    if (result == static_cast<size_t>(-1) || remaining) throw std::runtime_error("encoding");
    return std::string(output.data(), destination - output.data());
}
char *copy(const std::string &text) {
    char *result = static_cast<char *>(malloc(text.size() + 1));
    if (!result) throw std::bad_alloc();
    memcpy(result, text.c_str(), text.size() + 1);
    return result;
}
void charset(std::string &wire, const std::string &from, const std::string &to) {
    const auto offset = wire.find("Charset: " + from + "\r\n");
    if (offset != std::string::npos) wire.replace(offset + 9, from.size(), to);
}
}
#define EXPORT extern "C" __attribute__((visibility("default")))
EXPORT int32_t loadu(void *data, int32_t length) {
    Buffer owned(static_cast<char *>(data), free);
    if (!data || length <= 0 || length > limit || memchr(data, 0, length)) return 0;
    std::unique_lock<std::mutex> lock(mutex, std::try_to_lock);
    if (!lock.owns_lock() || instance || failedUnload) return 0;
    try {
        auto path = convert(std::string(owned.get(), length), "UTF-8", "UTF-8");
        if (!std::filesystem::path(path).is_absolute() || !std::filesystem::is_directory(path)) return 0;
        if (path.back() != '/') path += '/';
#ifdef YAYA_MODULE
        instance = multi_loadu(copy(path), path.size());
#else
        instance = satori_load(copy(path), path.size());
#endif
        return instance > 0;
    } catch (...) { return 0; }
}
EXPORT int32_t load(void *data, int32_t length) { return loadu(data, length); }
EXPORT int32_t unload() {
    std::unique_lock<std::mutex> lock(mutex, std::try_to_lock);
    if (!lock.owns_lock()) return 0;
    if (failedUnload) return 0;
    if (!instance) return 1;
    try {
#ifdef YAYA_MODULE
        const auto result = multi_unload(instance);
#else
        const auto result = satori_unload(static_cast<int>(instance));
#endif
        // Both upstream entry points destroy the instance even if saving failed.
        instance = 0;
        failedUnload = result == 0;
        return result != 0;
    } catch (...) { instance = 0; failedUnload = true; return 0; }
}
EXPORT void *request(void *data, int32_t *length) {
    Buffer owned(static_cast<char *>(data), free);
    if (!length) return nullptr;
    const auto count = *length; *length = 0;
    if (!data || count <= 0 || count > limit || memchr(data, 0, count)) return nullptr;
    std::unique_lock<std::mutex> lock(mutex, std::try_to_lock);
    if (!lock.owns_lock() || !instance) return nullptr;
    try {
        auto wire = convert(std::string(owned.get(), count), "UTF-8", "UTF-8");
#ifndef YAYA_MODULE
        charset(wire, "UTF-8", "Shift_JIS");
        wire = convert(wire, "CP932", "UTF-8");
#endif
        long size = wire.size();
#ifdef YAYA_MODULE
        Buffer output(multi_request(instance, copy(wire), &size), free);
#else
        Buffer output(satori_request(static_cast<int>(instance), copy(wire), &size), free);
#endif
        if (!output || size < 0 || size > limit) return nullptr;
        wire.assign(output.get(), size);
#ifndef YAYA_MODULE
        wire = convert(wire, "UTF-8", "CP932");
        charset(wire, "Shift_JIS", "UTF-8");
#endif
        if (wire.size() > limit) return nullptr;
        auto result = copy(wire); *length = static_cast<int32_t>(wire.size()); return result;
    } catch (...) { return nullptr; }
}
