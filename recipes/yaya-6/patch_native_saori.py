"""Apply the Utatane SAORI bridge to a disposable YAYA 6 build tree."""

from pathlib import Path


def replace_once(data: bytes, old: bytes, new: bytes) -> bytes:
    if data.count(old) != 1:
        raise ValueError(f"YAYA 6 SAORI patch anchor changed: {old!r}")
    return data.replace(old, new)


def patch(tree: Path) -> None:
    header = tree / "Vendor/lib.h"
    data = header.read_bytes()
    data = replace_once(data, b"\tstd::string filename;", b"\tstd::string filename;\n\tbool nativeSaori;")
    data = replace_once(data, b"\t\tisAlreadyLoaded = false;", b"\t\tisAlreadyLoaded = false;\n#if defined(POSIX)\n\t\tnativeSaori = false;\n#endif")
    header.write_bytes(data)

    source = tree / "Vendor/lib1.cpp"
    data = source.read_bytes().replace(b"\r\n", b"\n")
    data = replace_once(data, b'#include "globaldef.h"', b'''#include "globaldef.h"
extern "C" int utatane_yaya_native_saori_load(const char *path);
extern "C" int utatane_yaya_native_saori_unload(const char *path);
extern "C" char *utatane_yaya_native_saori_request(const char *path, char *request, long *length);''')
    data = replace_once(data, b"    fix_filepath(libfile);", b'''    fix_filepath(libfile);
    if (utatane_yaya_native_saori_load(libfile.c_str())) {
        nativeSaori = true;
        hDLL = reinterpret_cast<void *>(1);
        return 1;
    }''')

    start = data.index(b"#elif defined(POSIX)\nint CLib1::Load(void)")
    end = data.index(b"#endif", start)
    section = data[start:end]
    anchor = b"    if (!LoadLib()) {\n\t\treturn 0;\n    }"
    section = replace_once(section, anchor, anchor + b"\n    if (nativeSaori) return 1;")
    data = data[:start] + section + data[end:]

    start = data.index(b"#elif defined(POSIX)\nint CLib1::Unload(void)")
    end = data.index(b"#endif", start)
    section = data[start:end]
    anchor = b"\treturn 2;\n    }"
    section = replace_once(section, anchor, anchor + b'''
    if (nativeSaori) {
        const std::string path = narrow(name);
        const int result = utatane_yaya_native_saori_unload(path.c_str());
        nativeSaori = false;
        hDLL = NULL;
        return result;
    }''')
    data = data[:start] + section + data[end:]

    start = data.index(b"#elif defined(POSIX)\nint CLib1::Request(")
    end = data.index(b"#endif", start)
    section = data[start:end]
    anchor = b"    if (hDLL == NULL) {\n\treturn 0;\n    }"
    section = replace_once(section, anchor, anchor + b'''
    if (nativeSaori) {
        char *input = Ccct::Ucs2ToMbcs(istr, charset);
        if (!input) return 0;
        long length = static_cast<long>(strlen(input));
        const std::string path = narrow(name);
        char *output = utatane_yaya_native_saori_request(path.c_str(), input, &length);
        free(input);
        if (!output) return 0;
        const std::string response(output, length);
        free(output);
        wchar_t *wide = Ccct::MbcsToUcs2(response, charset);
        if (!wide) return 0;
        ostr = wide;
        free(wide);
        return 1;
    }''')
    data = data[:start] + section + data[end:]
    source.write_bytes(data)
