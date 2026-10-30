// Independently declared signatures from the public D.N.Proxy interface contract.
using System;
namespace Ukagaka.NET.Interfaces {
    public interface ILoad { bool load(IntPtr h, int len); }
    public interface IUnload { bool unload(); }
    public interface IRequest { IntPtr request(IntPtr h, ref int len); }
    public interface IGetVersion { IntPtr getversion(ref int len); }
    public interface INotify { void notify(IntPtr h, ref int len); }
}
