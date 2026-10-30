using System;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;
using Ukagaka.NET.Interfaces;
namespace Portable {
    public sealed class Ghost : ILoad, IRequest, IUnload {
        private string directory;
        private int count;
        public bool load(IntPtr h, int len) {
            directory = Marshal.PtrToStringUTF8(h, len);
            Marshal.FreeHGlobal(h);
            if (Path.GetFullPath(AppContext.BaseDirectory) != Path.GetFullPath(directory)) return false;
            string file = Path.Combine(directory, "state.txt");
            count = File.Exists(file) ? int.Parse(File.ReadAllText(file)) : 0;
            Console.WriteLine("ghost log");
            return true;
        }
        public IntPtr request(IntPtr h, ref int len) {
            string text = Marshal.PtrToStringUTF8(h, len); Marshal.FreeHGlobal(h);
            ++count;
            string result = "SHIORI/3.0 200 OK\r\nCharset: UTF-8\r\nValue: 日本語😀 count=" + count + "\r\n\r\n";
            len = Encoding.UTF8.GetByteCount(result);
            return Marshal.StringToHGlobalAnsi(result);
        }
        public bool unload() { File.WriteAllText(Path.Combine(directory, "state.txt"), count.ToString()); return true; }
    }
}
