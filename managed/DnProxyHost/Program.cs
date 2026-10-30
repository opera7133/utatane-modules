using System.Buffers.Binary;
using System.Diagnostics;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Runtime.Loader;
using System.Text;
using System.Xml;
using System.Xml.Linq;
using Ukagaka.NET.Interfaces;

// One process per ghost. No AppDomain, Win32 export rewriting, or remoting.
static class Program {
    const int MaxBytes = 8 * 1024 * 1024;
    static readonly Encoding Utf8 = new UTF8Encoding(false, true);
    static byte[] ReadPacket(Stream stream) {
        byte[] header = new byte[4]; stream.ReadExactly(header);
        int length = BinaryPrimitives.ReadInt32LittleEndian(header);
        if (length < 0 || length > MaxBytes) throw new InvalidDataException("Invalid packet length");
        byte[] data = new byte[length]; stream.ReadExactly(data); return data;
    }
    static void WritePacket(Stream stream, byte[] data) {
        if (data.Length > MaxBytes) throw new InvalidDataException("Response too large");
        byte[] header = new byte[4]; BinaryPrimitives.WriteInt32LittleEndian(header, data.Length);
        stream.Write(header); stream.Write(data); stream.Flush();
    }
    static string FullPath(string root, string relative) => Path.GetFullPath(relative.Replace('\\', Path.DirectorySeparatorChar), root);
    static Dictionary<string, List<string>> ReadIni(string path) {
        var result = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
        string? key = null;
        foreach (string original in File.ReadLines(path, Utf8)) {
            string line = original.Split(new[] { "//" }, 2, StringSplitOptions.None)[0].Trim();
            if (line.Length == 0) continue;
            int colon = line.IndexOf(':');
            if (colon >= 0) { key = line[..colon].Trim(); line = line[(colon + 1)..].Trim(); }
            if (key == null || line.Length == 0) continue;
            if (!result.TryGetValue(key, out var values)) result[key] = values = new();
            values.Add(line);
        }
        return result;
    }
    static string Setting(XDocument config, string name, string fallback) =>
        config.Descendants("setting").FirstOrDefault(x => (string?)x.Attribute("name") == name)?.Element("value")?.Value ?? fallback;
    static string Build(string ghost, Dictionary<string, List<string>> ini, string assemblyName, string interfaces) {
        string Get(string key, string fallback = "") => ini.TryGetValue(key, out var v) ? v.Last() : fallback;
        if (!new[] { "C#", "CSharp", "csharp" }.Contains(Get("Language", "C#"))) throw new NotSupportedException("Only portable C# source is supported");
        var supported = new HashSet<string>(new[] { "Language", "SourceFiles", "MainClass", "OutputAssembly", "ReferencedAssemblies", "GenerateExecutable" }, StringComparer.OrdinalIgnoreCase);
        foreach (string key in ini.Keys)
            if (!supported.Contains(key)) throw new NotSupportedException($"Unsupported dnproxy.ini option: {key}");
        if (Get("GenerateExecutable", "0") != "0") throw new NotSupportedException("Executable output is unsupported");
        var sources = new List<string>();
        foreach (string pattern in ini.GetValueOrDefault("SourceFiles", new()).SelectMany(x => x.Split(','))) {
            string path = FullPath(ghost, pattern.Trim());
            string directory = Path.GetDirectoryName(path)!;
            var found = Directory.GetFiles(directory, Path.GetFileName(path)).Order().ToArray();
            if (found.Length == 0) throw new FileNotFoundException($"Source not found: {pattern}");
            sources.AddRange(found);
        }
        if (sources.Count == 0) throw new InvalidDataException("No SourceFiles in dnproxy.ini");
        string scratch = Path.Combine(Path.GetTempPath(), "utatane-dnproxy-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(scratch);
        try {
            var items = new XElement("ItemGroup", sources.Distinct().Select(path => new XElement("Compile", new XAttribute("Include", path))));
            items.Add(new XElement("Reference", new XAttribute("Include", "Ukagaka.NET.Interfaces"), new XElement("HintPath", interfaces)));
            foreach (string name in ini.GetValueOrDefault("ReferencedAssemblies", new()).SelectMany(x => x.Split(','))) {
                string trimmed = name.Trim();
                if (trimmed.Equals("Ukagaka.NET.Interfaces.dll", StringComparison.OrdinalIgnoreCase)) continue;
                // Standard framework names resolve from the selected .NET SDK.
                if (new[] { "System.dll", "mscorlib.dll", "System.Core.dll" }.Contains(trimmed)) continue;
                string path = FullPath(ghost, trimmed);
                if (!File.Exists(path)) throw new FileNotFoundException($"Reference not found or Windows-only: {trimmed}");
                items.Add(new XElement("Reference", new XAttribute("Include", Path.GetFileNameWithoutExtension(trimmed)), new XElement("HintPath", path)));
            }
            var project = new XDocument(new XElement("Project", new XAttribute("Sdk", "Microsoft.NET.Sdk"),
                new XElement("PropertyGroup", new XElement("TargetFramework", "net10.0"), new XElement("OutputType", "Library"),
                    new XElement("EnableDefaultCompileItems", "false"), new XElement("AssemblyName", Path.GetFileNameWithoutExtension(assemblyName)),
                    new XElement("AllowUnsafeBlocks", "true"), new XElement("LangVersion", "latest")), items));
            string csproj = Path.Combine(scratch, "user.csproj"); project.Save(csproj);
            var start = new ProcessStartInfo(Environment.GetEnvironmentVariable("UTATANE_DOTNET") ?? "dotnet") {
                UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, WorkingDirectory = scratch
            };
            foreach (string arg in new[] { "build", csproj, "-c", "Release", "--nologo", "--ignore-failed-sources" }) start.ArgumentList.Add(arg);
            using var process = Process.Start(start) ?? throw new IOException("Cannot launch dotnet build");
            var stdout = process.StandardOutput.ReadToEndAsync(); var stderr = process.StandardError.ReadToEndAsync();
            if (!process.WaitForExit(120_000)) { process.Kill(true); process.WaitForExit(); throw new TimeoutException("C# compilation timed out"); }
            Task.WaitAll(stdout, stderr);
            if (process.ExitCode != 0) throw new InvalidDataException("C# compilation failed:\n" + stdout.Result + stderr.Result);
            // Use an isolated build directory; do not overwrite the original Windows user.dll.
            string cache = Path.Combine(ghost, "profile", "dnproxy-macos"); Directory.CreateDirectory(cache);
            foreach (string path in Directory.GetFiles(Path.Combine(scratch, "bin", "Release", "net10.0")))
                File.Copy(path, Path.Combine(cache, Path.GetFileName(path)), true);
            return Path.Combine(cache, Path.GetFileNameWithoutExtension(assemblyName) + ".dll");
        } finally { Directory.Delete(scratch, true); }
    }
    static int Main(string[] args) {
        using Stream output = Console.OpenStandardOutput();
        Console.SetOut(Console.Error); // Ghost logging cannot corrupt framed stdout.
        IUnload? unload = null;
        try {
            if (args.Length != 1 || !Path.IsPathFullyQualified(args[0])) throw new ArgumentException("Expected absolute ghost directory");
            string ghost = Path.GetFullPath(args[0]);
            Directory.SetCurrentDirectory(ghost);
            AppContext.SetData("APP_CONTEXT_BASE_DIRECTORY", ghost + Path.DirectorySeparatorChar);
            string configPath = Path.Combine(ghost, "dnproxy.dll.config");
            using var reader = XmlReader.Create(configPath, new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null });
            var config = XDocument.Load(reader);
            if (Setting(config, "Protocol", "") != "SHIORI/3.0") throw new NotSupportedException("Only SHIORI/3.0 is supported");
            string className = Setting(config, "MainClass", "Unknown.User");
            string assemblyName = Setting(config, "AssemblyName", "user.dll");
            string interfaces = typeof(ILoad).Assembly.Location;
            string iniPath = Path.Combine(ghost, "dnproxy.ini");
            string assembly;
            if (File.Exists(iniPath)) {
                var ini = ReadIni(iniPath);
                if (ini.TryGetValue("MainClass", out var names)) className = names.Last();
                if (ini.TryGetValue("OutputAssembly", out var outputs)) assemblyName = outputs.Last();
                assembly = Build(ghost, ini, assemblyName, interfaces);
            } else { assembly = FullPath(ghost, assemblyName); }
            var privatePaths = Setting(config, "PrivateBinPath", "lib;plugin;service").Split(';').Select(x => FullPath(ghost, x)).ToArray();
            AssemblyLoadContext.Default.Resolving += (context, name) => {
                if (name.Name == "Ukagaka.NET.Interfaces") return typeof(ILoad).Assembly;
                foreach (string root in new[] { Path.GetDirectoryName(assembly)!, ghost }.Concat(privatePaths)) {
                    string path = Path.Combine(root, name.Name + ".dll");
                    if (File.Exists(path)) return context.LoadFromAssemblyPath(path);
                }
                return null;
            };
            object instance = Activator.CreateInstance(AssemblyLoadContext.Default.LoadFromAssemblyPath(assembly).GetType(className, true)!)!;
            if (instance is not ILoad load || instance is not IRequest request || instance is not IUnload closer)
                throw new InvalidDataException("MainClass must implement ILoad, IRequest, IUnload");
            byte[] directory = Utf8.GetBytes(ghost + Path.DirectorySeparatorChar);
            IntPtr ptr = Marshal.AllocHGlobal(directory.Length); Marshal.Copy(directory, 0, ptr, directory.Length);
            // The user ILoad consumes and frees this allocation, as in D.N.Proxy.
            if (!load.load(ptr, directory.Length)) throw new InvalidDataException("Ghost load failed");
            unload = closer;
            WritePacket(output, new byte[] { 1 });
            using Stream input = Console.OpenStandardInput();
            while (true) {
                byte[] wire;
                try { wire = ReadPacket(input); } catch (EndOfStreamException) { break; }
                if (wire.Length == 0) break;
                string text = Utf8.GetString(wire);
                if (!text.EndsWith("\r\n\r\n") || text.Contains('\0')) throw new InvalidDataException("Invalid SHIORI request");
                // PtrToStringAnsi is UTF-8 on macOS. Legacy CP932 memory contracts are outside this mode.
                if (text.Split("\r\n").Any(x => x.StartsWith("Charset:", StringComparison.OrdinalIgnoreCase) && !x[8..].Trim().Equals("UTF-8", StringComparison.OrdinalIgnoreCase)))
                    throw new NotSupportedException("Portable D.N.Proxy requires Charset: UTF-8");
                ptr = Marshal.AllocHGlobal(wire.Length); Marshal.Copy(wire, 0, ptr, wire.Length);
                int length = wire.Length;
                IntPtr response = request.request(ptr, ref length);
                try {
                    if (response == IntPtr.Zero || length < 0 || length > MaxBytes) throw new InvalidDataException("Invalid ghost response");
                    byte[] data = new byte[length]; Marshal.Copy(response, data, 0, length); _ = Utf8.GetString(data); WritePacket(output, data);
                } finally { if (response != IntPtr.Zero) Marshal.FreeHGlobal(response); }
            }
            bool result = unload.unload(); unload = null; WritePacket(output, new byte[] { result ? (byte)1 : (byte)0 });
            return result ? 0 : 1;
        } catch (Exception error) {
            Console.Error.WriteLine("DNProxy: " + (error is TargetInvocationException ? error.InnerException?.Message : error.Message));
            return 1;
        } finally { try { unload?.unload(); } catch { } }
    }
}
