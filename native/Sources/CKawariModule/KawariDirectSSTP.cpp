// Utatane's private, owning-session transport for KAWARI baseware calls (MIT).
#include "misc/dsstp.h"
#include "misc/charset.h"
#include <cstdint>
#include <cstdlib>
#include <cwchar>
#include <sstream>

namespace {
using Callback = void *(*)(const void *, int32_t, int32_t *);
Callback callback = nullptr;
constexpr int32_t maximumBytes = 8 * 1024 * 1024;
}

extern "C" __attribute__((visibility("default"))) int32_t utatane_internal_saori_set_callback(Callback value) {
    callback = value;
    return 1;
}

namespace dsstp {
bool TBasewareLink::SetHandleFromReference(const std::wstring &reference) {
    wchar_t *end = nullptr;
    const auto value = std::wcstoul(reference.c_str(), &end, 10);
    if (end == reference.c_str() || value == 0) return false;
    handle = value;
    return true;
}

bool HasForbiddenChar(const std::wstring &text) {
    return text.find_first_of(std::wstring(L"\r\n\0", 3)) != std::wstring::npos;
}

std::string BuildExecuteRequest(const std::wstring &command, const std::vector<std::wstring> &references) {
    if (HasForbiddenChar(command)) return "";
    std::wstring text = L"EXECUTE SSTP/1.1\r\nCharset: UTF-8\r\nSender: kawari\r\nCommand: " + command + L"\r\n";
    for (size_t i = 0; i < references.size(); ++i) {
        if (HasForbiddenChar(references[i])) return "";
        text += L"Reference" + std::to_wstring(i) + L": " + references[i] + L"\r\n";
    }
    return WtoUTF8(text + L"\r\n");
}

int ParseExecuteResponse(const std::string &response, std::vector<std::wstring> &lines) {
    lines.clear();
    std::istringstream stream(response);
    std::string protocol;
    int status = 0;
    if (!(stream >> protocol >> status) || protocol.compare(0, 5, "SSTP/") != 0) return 0;
    const auto body = response.find("\r\n\r\n");
    if (body == std::string::npos) return 0;
    std::istringstream additional(response.substr(body + 4));
    std::string line;
    while (std::getline(additional, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (line.empty()) break;
        lines.push_back(UTF8toW(line));
    }
    return status;
}

bool TBasewareLink::Send(const std::string &request, std::string &response, unsigned int) const {
    response.clear();
    // Generic SSTP is not handled by this private endpoint. Never misroute a
    // SHIORI baseware command into internal SAORI.
    if (!allowed || !callback || request.size() > static_cast<size_t>(maximumBytes) ||
        (request.rfind("EXECUTE SAORI/1.0\r\n", 0) != 0 &&
         request.rfind("GET Version SAORI/1.0\r\n", 0) != 0)) return false;
    int32_t size = 0;
    void *output = callback(request.data(), static_cast<int32_t>(request.size()), &size);
    if (!output || size < 0 || size > maximumBytes) { free(output); return false; }
    response.assign(static_cast<char *>(output), static_cast<size_t>(size));
    free(output);
    return !response.empty();
}
}
