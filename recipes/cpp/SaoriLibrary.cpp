#include "SaoriLibrary.h"
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <filesystem>
#include <map>
#include <memory>
#include <vector>
#include <algorithm>
#include <chrono>

namespace saori {
namespace {
using InternalCallback = void *(*)(const void *, int32_t, int32_t *);
InternalCallback internalCallback = nullptr;
std::string normalized(std::string path);

std::string internalName(const std::string &path) {
    auto name = std::filesystem::path(normalized(path)).filename().string();
    std::transform(name.begin(), name.end(), name.begin(), [](unsigned char c) { return std::tolower(c); });
    if (name.size() > 4 && name.substr(name.size() - 4) == ".dll") name.resize(name.size() - 4);
    if (name.compare(0, 9, "internal_") != 0 || !std::all_of(name.begin(), name.end(), [](unsigned char c) {
        return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_';
    })) return "";
    return name;
}
constexpr int32_t limit = 8 * 1024 * 1024;
using Clock = std::chrono::steady_clock;
void trace(int32_t phase, int32_t status, Clock::time_point started, uint64_t bytes, const std::string &path) {
    using Reporter = void (*)(int32_t, int32_t, uint64_t, uint64_t, const char *);
    static auto reporter = reinterpret_cast<Reporter>(dlsym(RTLD_DEFAULT, "utatane_host_saori_diagnostic"));
    if (reporter) reporter(phase, status, static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::microseconds>(Clock::now() - started).count()), bytes, path.c_str());
}

struct Library {
    using Load = int32_t (*)(void *, int32_t);
    using Request = void *(*)(void *, int32_t *);
    using Unload = int32_t (*)();
    Request request;
    Unload unload;
    std::string selectedPath;
    ~Library() { if (unload) unload(); }
};
// Swift images must stay mapped after unload; their runtime metadata outlives a session.
std::map<std::string, void *> images;
std::map<std::string, std::unique_ptr<Library>> sessions;
std::string normalized(std::string path) {
    std::replace(path.begin(), path.end(), '\\', '/');
    return std::filesystem::absolute(path).lexically_normal().string();
}
std::vector<std::filesystem::path> candidates(const std::filesystem::path &original) {
    const auto ext = original.extension().string();
    if (ext != ".dll" && ext != ".DLL") return {original};
    auto stem = original.stem().string();
    std::transform(stem.begin(), stem.end(), stem.begin(), [](unsigned char c) { return std::tolower(c); });
    const auto filename = "lib" + stem + ".dylib";
    std::vector<std::filesystem::path> result = {original.parent_path() / (stem + ".dylib"), original.parent_path() / filename};
    auto id = stem == "saori_cpuid" ? "saori-cpuid" : stem;
    if (const char *root = std::getenv("UTATANE_SAORI_ROOT")) {
        if (std::filesystem::path(root).is_absolute()) result.push_back(std::filesystem::path(root) / id / "lib" / filename);
    } else if (const char *home = std::getenv("HOME")) {
        result.push_back(std::filesystem::path(home) / "Library/Application Support/Utatane/NativeSaori" / id / "lib" / filename);
    }
    return result;
}
}
bool load(const std::string &path) {
    if (!internalName(path).empty()) return internalCallback != nullptr;
    const auto started = Clock::now();
    const auto key = normalized(path);
    if (sessions.count(key)) return true;
    for (const auto &candidate : candidates(key)) {
        if (!std::filesystem::is_regular_file(candidate)) continue;
        void *handle = nullptr;
        if (images.count(candidate.string())) handle = images.at(candidate.string());
        else {
            handle = dlopen(candidate.c_str(), RTLD_NOW | RTLD_LOCAL);
            if (!handle) continue;
            images[candidate.string()] = handle;
        }
        auto start = reinterpret_cast<Library::Load>(dlsym(handle, "loadu"));
        if (!start) start = reinterpret_cast<Library::Load>(dlsym(handle, "load"));
        auto request = reinterpret_cast<Library::Request>(dlsym(handle, "request"));
        auto stop = reinterpret_cast<Library::Unload>(dlsym(handle, "unload"));
        if (!start || !request || !stop) continue;
        // Resources belong to the ghost's declared SAORI folder, also for shared binaries.
        const auto directory = std::filesystem::path(key).parent_path().string() + "/";
        char *buffer = static_cast<char *>(malloc(directory.size() + 1));
        if (!buffer) return false;
        memcpy(buffer, directory.c_str(), directory.size() + 1);
        // Initialization failure must not try a different version against the same data.
        if (!start(buffer, static_cast<int32_t>(directory.size()))) { trace(1, 0, started, 0, candidate.string()); return false; }
        sessions[key] = std::unique_ptr<Library>(new Library{request, stop, candidate.string()});
        trace(1, 1, started, 0, candidate.string());
        return true;
    }
    trace(1, 0, started, 0, key);
    return false;
}
bool unload(const std::string &path) {
    if (!internalName(path).empty()) return internalCallback != nullptr;
    const auto started = Clock::now();
    auto found = sessions.find(normalized(path));
    const auto selected = found == sessions.end() ? normalized(path) : found->second->selectedPath;
    const int32_t status = found == sessions.end() ? 0 : found->second->unload();
    if (found != sessions.end()) { found->second->unload = nullptr; sessions.erase(found); }
    trace(3, status, started, 0, selected);
    return status != 0;
}
char *request(const std::string &path, const char *input, long *length) {
    if (!input || !length || *length < 0 || *length > limit) return nullptr;
    const auto module = internalName(path);
    if (!module.empty()) {
        if (!internalCallback) { *length = 0; return nullptr; }
        std::string wire(input, static_cast<size_t>(*length));
        const auto end = wire.find("\r\n");
        if (end == std::string::npos) { *length = 0; return nullptr; }
        wire.insert(end + 2, "Module: " + module + "\r\n");
        if (wire.size() > static_cast<size_t>(limit)) { *length = 0; return nullptr; }
        int32_t size = 0;
        auto *response = static_cast<char *>(internalCallback(wire.data(), static_cast<int32_t>(wire.size()), &size));
        if (!response || size < 0 || size > limit) { free(response); *length = 0; return nullptr; }
        *length = size;
        return response;
    }
    const auto started = Clock::now();
    if (!load(path)) { *length = 0; trace(2, 0, started, 0, normalized(path)); return nullptr; }
    int32_t size = static_cast<int32_t>(*length);
    char *buffer = static_cast<char *>(malloc(static_cast<size_t>(size) + 1));
    if (!buffer) { *length = 0; return nullptr; }
    memcpy(buffer, input, size); buffer[size] = 0;
    auto *output = static_cast<char *>(sessions.at(normalized(path))->request(buffer, &size));
    if (!output || size < 0 || size > limit) { free(output); *length = 0; trace(2, 0, started, 0, sessions.at(normalized(path))->selectedPath); return nullptr; }
    int status = 0;
    if (size >= 13 && memcmp(output, "SAORI/1.0 ", 10) == 0) {
        for (int i = 10; i < 13 && output[i] >= '0' && output[i] <= '9'; ++i) status = status * 10 + output[i] - '0';
    }
    trace(2, status, started, static_cast<uint64_t>(size), sessions.at(normalized(path))->selectedPath);
    *length = size;
    return output;
}
}

extern "C" __attribute__((visibility("default"))) int32_t utatane_internal_saori_set_callback(saori::InternalCallback callback) {
    saori::internalCallback = callback;
    return 1;
}

extern "C" int utatane_yaya_is_internal_saori(const char *path) { return path && !saori::internalName(path).empty(); }
extern "C" int utatane_yaya_native_saori_load(const char *path) { return path && saori::load(path); }
extern "C" int utatane_yaya_native_saori_unload(const char *path) { return path && saori::unload(path); }
extern "C" char *utatane_yaya_native_saori_request(const char *path, char *input, long *length) {
    return path ? saori::request(path, input, length) : nullptr;
}
