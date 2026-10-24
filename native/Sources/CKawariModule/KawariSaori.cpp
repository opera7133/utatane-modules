// macOS SAORI selection: an installed native library takes precedence over
// upstream's DirectSSTP compatibility-name fallback. Keep vendor sources intact.
#include "saori/saori_dsstp.h"
#include "misc/charset.h"
#include <algorithm>
#include <cstdlib>
#include <sys/stat.h>

namespace saori {
namespace {
bool hasNativeSaori(const std::wstring &path) {
    std::string native = WtoUTF8(path);
    std::replace(native.begin(), native.end(), '\\', '/');
    const auto slash = native.find_last_of('/');
    auto name = native.substr(slash == std::string::npos ? 0 : slash + 1);
    std::transform(name.begin(), name.end(), name.begin(), [](unsigned char c) {
        return c >= 'A' && c <= 'Z' ? static_cast<char>(c + 'a' - 'A') : static_cast<char>(c);
    });
    if (name.size() <= 4 || name.substr(name.size() - 4) != ".dll") return false;
    name.resize(name.size() - 4);
    if (name.compare(0, 9, "internal_") == 0) return false;
    if (!std::all_of(name.begin(), name.end(), [](unsigned char c) {
        return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '-';
    })) return false;
    std::vector<std::string> directories = {slash == std::string::npos ? "." : native.substr(0, slash)};
    const char *root = std::getenv("UTATANE_SAORI_ROOT");
    if (!root) root = std::getenv("KAWARI_SAORI_ROOT");
    if (root) {
        auto identifier = name;
        std::replace(identifier.begin(), identifier.end(), '_', '-');
        directories.push_back(std::string(root) + "/" + identifier + "/lib");
        directories.push_back(std::string(root) + "/" + name + "/lib");
        directories.push_back(root);
    }
    for (const auto &directory : directories) {
        for (const auto &filename : {name + ".dylib", "lib" + name + ".dylib"}) {
            struct stat info;
            if (stat((directory + "/" + filename).c_str(), &info) == 0 && S_ISREG(info.st_mode)) return true;
        }
    }
    return false;
}
}
class NativeAwareDirectSSTPFactory : public TModuleFactoryDirectSSTP {
public:
    using TModuleFactoryDirectSSTP::TModuleFactoryDirectSSTP;
    TModule *CreateModule(const std::wstring &path) override {
        return hasNativeSaori(path) ? nullptr : TModuleFactoryDirectSSTP::CreateModule(path);
    }
};
}
// Substitute only the factory constructed by the upstream factory master.
#define TModuleFactoryDirectSSTP NativeAwareDirectSSTPFactory
#include "Vendor/KAWARI/build/src/saori/saori_module.cpp"
#undef TModuleFactoryDirectSSTP
