#pragma once
#include <string>
namespace saori {
bool load(const std::string &path);
bool unload(const std::string &path);
char *request(const std::string &path, const char *input, long *length);
}
