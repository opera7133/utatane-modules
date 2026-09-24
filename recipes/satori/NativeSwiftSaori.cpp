#include "NativeSwiftSaori.h"
#include "SaoriLibrary.h"
#include <cstdlib>
#include <sstream>

bool NativeSwiftSaori::load(const string&, const string&, const string&, const string &fullpath) {
    if (!fullpath.empty()) path = fullpath;
    return saori::load(path);
}
void NativeSwiftSaori::unload() { saori::unload(path); }
string NativeSwiftSaori::request(const string &input) {
    long length = input.size();
    char *buffer = saori::request(path, input.data(), &length);
    if (!buffer) return "";
    string result(buffer, length); free(buffer); return result;
}
string NativeSwiftSaori::get_version(const string&) { return "SAORI/1.0"; }
int NativeSwiftSaori::request(const std::vector<string>& arguments, bool, string& result, std::vector<string>& values) {
    std::ostringstream wire;
    wire << "EXECUTE SAORI/1.0\r\nCharset: Shift_JIS\r\n";
    for (std::size_t index = 0; index < arguments.size(); ++index)
        wire << "Argument" << index << ": " << arguments[index] << "\r\n";
    wire << "\r\n";
    std::istringstream lines(request(wire.str()));
    string line, protocol; int status = 500;
    if (!std::getline(lines, line)) return status;
    std::istringstream(line) >> protocol >> status;
    while (std::getline(lines, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (line.compare(0, 8, "Result: ") == 0) result = line.substr(8);
        else if (line.compare(0, 5, "Value") == 0) {
            const auto colon = line.find(": ");
            if (colon != string::npos) values.push_back(line.substr(colon + 2));
        }
    }
    return status;
}
