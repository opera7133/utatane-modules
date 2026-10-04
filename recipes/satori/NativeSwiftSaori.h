#pragma once
#include "Vendor/satori/SaoriClient.h"

class NativeSwiftSaori : public SaoriClient {
public:
    explicit NativeSwiftSaori(const wstring& path) : path(WtoUTF8(path)) {}
    ~NativeSwiftSaori() override { unload(); }
    bool load(const wstring&, const wstring&, const wstring&, const wstring&) override;
    void unload() override;
    wstring request(const wstring&) override;
    wstring get_version(const wstring&) override;
    bool version_reply_has_charset() const override { return hasCharset; }
    int request(const std::vector<wstring>&, bool, wstring&, std::vector<wstring>&) override;
protected:
    std::string path;
    bool hasCharset = true;
};
