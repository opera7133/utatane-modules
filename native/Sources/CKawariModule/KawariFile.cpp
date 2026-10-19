#include "kis/kis_file.h"

// Keep the pinned source intact, replacing only the POSIX existence check.
// Directory enumeration compares Unicode code units and can reject a path
// which the macOS filesystem resolves (NFC versus decomposed dakuten, case).
class UtataneLegacyKawariIsExist : public KIS_isexist {
public:
    std::wstring Function(const std::vector<std::wstring>& args) override;
};

#define KIS_isexist UtataneLegacyKawariIsExist
#include "Vendor/KAWARI/build/src/kis/kis_file.cpp"
#undef KIS_isexist

std::wstring KIS_isexist::Function(const std::vector<std::wstring>& args) {
    if (!AssertArgument(args, 2, 2)) return L"";
    const std::wstring path = CanonicalPath(Engine->GetDataPath(), args[1]);
    bool directory = false, file = false;
    return PathStat(path, &directory, &file) ? L"1" : L"0";
}
