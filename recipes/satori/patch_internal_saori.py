"""Enable module-name calls in a disposable POSIX SATORI build tree."""
from pathlib import Path


def patch(tree: Path) -> None:
    header = tree / "Vendor/satori/shiori_plugin.h"
    data = header.read_text()
    old = "#else\n\t\treturn false;\n#endif"
    new = '''#else
        if (!compare_head_nocase(iCallName, L"internal_")) return false;
        wstring name = iCallName;
        for (auto &c : name) {
            if (!((c >= L'A' && c <= L'Z') || (c >= L'a' && c <= L'z') ||
                  (c >= L'0' && c <= L'9') || c == L'_')) return false;
            if (c >= L'A' && c <= L'Z') c += L'a' - L'A';
        }
        return load_a_plugin(iCallName + L",saori/" + name + L".dll") &&
            mCallData.find(iCallName) != mCallData.end();
#endif'''
    if data.count(old) != 1:
        raise ValueError("SATORI internal module patch anchor changed")
    header.write_text(data.replace(old, new))
