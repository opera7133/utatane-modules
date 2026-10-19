// Normalize absolute paths before calling the pinned upstream overload.
#define CanonicalPath UtataneLegacyCanonicalPath
#include "Vendor/KAWARI/build/src/misc/misc.cpp"
#undef CanonicalPath

std::wstring CanonicalPath(const std::wstring &path) {
    return UtataneLegacyCanonicalPath(path);
}

std::wstring CanonicalPath(const std::wstring &base, const std::wstring &path) {
    return UtataneLegacyCanonicalPath(
        UtataneLegacyCanonicalPath(base), UtataneLegacyCanonicalPath(path));
}
