#include "NativeSwiftSaori.h"
#include "SaoriLibrary.h"
#include <cstdlib>
#include <memory>

bool NativeSwiftSaori::load(const wstring&, const wstring& charset, const wstring&, const wstring &fullpath) {
    if (!fullpath.empty()) path = WtoUTF8(fullpath);
    set_charset(charset);
    if (!saori::load(path)) return false;
    if (get_version(L"Local") != L"SAORI/1.0") {
        unload();
        return false;
    }
    // Match Mc203-2: legacy SAORI without Charset keep receiving CP932.
    if (!hasCharset) {
        set_charset(L"Shift_JIS");
        wstring ignored;
        std::vector<wstring> values;
        request(std::vector<wstring>(1, L""), true, ignored, values);
    }
    return true;
}
void NativeSwiftSaori::unload() { saori::unload(path); }
wstring NativeSwiftSaori::request(const wstring &input) {
    const auto encoding = CharsetFromName(charset());
    const auto bytes = WtoMB(input, encoding);
    long length = bytes.size();
    std::unique_ptr<char, decltype(&free)> buffer(saori::request(path, bytes.data(), &length), free);
    if (!buffer) return L"";
    const std::string result(buffer.get(), length);
    auto responseEncoding = CharsetFromName(UTF8toW(find_charset_header(result)));
    if (responseEncoding == CS_NULL && encoding == CS_SJIS) responseEncoding = CS_SJIS;
    return MBtoW(result, responseEncoding);
}
wstring NativeSwiftSaori::get_version(const wstring &security) {
    strpairvec headers;
    headers.push_back(strpair(L"Charset", charset()));
    headers.push_back(strpair(L"Sender", L"SATORI"));
    headers.push_back(strpair(L"SecurityLevel", security));
    wstring protocol, version;
    strpairvec reply;
    SakuraClient::request(L"SAORI", L"1.0", L"GET Version", headers, protocol, version, reply);
    hasCharset = false;
    for (const auto &header : reply) {
        if (_wcsicmp(header.first.c_str(), L"Charset") == 0 && !header.second.empty()) hasCharset = true;
    }
    return protocol + L"/" + version;
}
int NativeSwiftSaori::request(const std::vector<wstring>& arguments, bool secure, wstring& result, std::vector<wstring>& values) {
    strpairvec headers;
    headers.push_back(strpair(L"Charset", charset()));
    headers.push_back(strpair(L"Sender", L"SATORI"));
    headers.push_back(strpair(L"SecurityLevel", secure ? L"Local" : L"External"));
    for (std::size_t index = 0; index < arguments.size(); ++index)
        headers.push_back(strpair(wstring(L"Argument") + itos(index), arguments[index]));
    wstring protocol, version;
    strpairvec reply;
    const auto status = SakuraClient::request(L"SAORI", L"1.0", L"EXECUTE", headers, protocol, version, reply);
    int maxValue = -1;
    for (const auto &header : reply) {
        if (header.first == L"Result") result = header.second;
        else if (header.first.size() > 5 && compare_head(header.first, L"Value") && iswdigit(header.first[5])) {
            const auto index = _wtoi(header.first.c_str() + 5);
            if (index < 0 || index > 65536) continue;
            if (values.size() <= static_cast<std::size_t>(index)) values.resize(index + 1);
            values[index] = header.second;
            if (maxValue < index) maxValue = index;
        }
    }
    // Preserve S variables when the SAORI returns no Value headers, like upstream.
    if (maxValue >= 0) values.resize(maxValue + 1);
    return status;
}
