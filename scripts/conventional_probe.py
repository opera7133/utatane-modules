"""Small malloc/free ABI driver shared by the new independent SHIORI probes."""
from contextlib import contextmanager
import ctypes
from pathlib import Path
import tempfile


class Conventional:
    def __init__(self, library):
        self.library = ctypes.CDLL(str(library))
        self.libc = ctypes.CDLL(None)
        self.libc.malloc.argtypes = [ctypes.c_size_t]
        self.libc.malloc.restype = ctypes.c_void_p
        self.libc.free.argtypes = [ctypes.c_void_p]
        for name in ('load', 'loadu'):
            getattr(self.library, name).argtypes = [ctypes.c_void_p, ctypes.c_int32]
            getattr(self.library, name).restype = ctypes.c_int32
        self.library.request.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_int32)]
        self.library.request.restype = ctypes.c_void_p
        self.library.unload.restype = ctypes.c_int32

    def owned(self, data):
        pointer = self.libc.malloc(max(len(data), 1))
        assert pointer
        ctypes.memmove(pointer, data, len(data))
        return pointer

    def load(self, root):
        data = str(root).encode('utf-8')
        return self.library.loadu(self.owned(data), len(data))

    def request(self, event, charset='UTF-8', references=(), method='GET'):
        wire = (f'{method} SHIORI/3.0\r\nCharset: {charset}\r\nID: {event}\r\n'
                + ''.join(f'Reference{i}: {value}\r\n' for i, value in enumerate(references)) + '\r\n')
        data = wire.encode('cp932' if charset == 'Shift_JIS' else 'utf-8')
        length = ctypes.c_int32(len(data))
        result = self.library.request(self.owned(data), ctypes.byref(length))
        if not result:
            assert length.value == 0
            return None
        try:
            assert 0 < length.value <= 8 * 1024 * 1024
            return ctypes.string_at(result, length.value).decode('cp932' if charset == 'Shift_JIS' else 'utf-8')
        finally:
            self.libc.free(result)

    def unload(self):
        return self.library.unload()


@contextmanager
def relocated(identity, path):
    path = Path(path).resolve()
    if path.suffix != '.zip':
        yield path
        return
    from catalog import ROOT, read_json, safe_extract, verify_package
    verify_package(path, read_json(ROOT / f'catalog/modules/{identity}.json'))
    with tempfile.TemporaryDirectory(prefix=f'{identity} ZIP 日本語 ') as temporary:
        root = Path(temporary)
        safe_extract(path, root)
        yield root / identity / f'lib/lib{identity}.dylib'
