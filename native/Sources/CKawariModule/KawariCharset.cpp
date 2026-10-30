// macOS libiconv spells native wchar_t as UTF-32; upstream uses WCHAR_T.
// Keep this adaptation outside the pinned upstream checkout.
#include <iconv.h>
#include <cstring>
#include <cwchar>
static iconv_t utatane_iconv_open(const char *to, const char *from) {
    static_assert(sizeof(wchar_t) == 4, "Expected 32-bit macOS wchar_t");
    const wchar_t one = 1;
    const char *wide = *reinterpret_cast<const unsigned char *>(&one) ? "UTF-32LE" : "UTF-32BE";
    return iconv_open(std::strcmp(to, "WCHAR_T") == 0 ? wide : to,
                      std::strcmp(from, "WCHAR_T") == 0 ? wide : from);
}
#undef iconv_open
#define iconv_open utatane_iconv_open
#include "Vendor/KAWARI/build/src/misc/charset.cpp"
#undef iconv_open
