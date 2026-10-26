// Windows inbox APIs only. No third-party driver-installation executable required.
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace Esp32HciInstaller {
    public sealed class Device {
        public string InstanceId;
        public string Description;
        public string[] HardwareIds;
        public string InterfacePath;
        public string Service;
        public uint Status;
        public uint Problem;
        public bool Present;
    }

    public static class Native {
        public const string HardwareId = @"ROOT\Esp32HciBus";
        static readonly IntPtr Invalid = new IntPtr(-1);
        [StructLayout(LayoutKind.Sequential)] struct Info {
            public uint Size; public Guid Class; public uint DevInst; public UIntPtr Reserved;
        }
        [StructLayout(LayoutKind.Sequential)] struct Interface {
            public uint Size; public Guid Class; public uint Flags; public UIntPtr Reserved;
        }
        [StructLayout(LayoutKind.Sequential)] struct CodeIntegrity {
            public uint Length; public uint Options;
        }
        [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        static extern IntPtr SetupDiGetClassDevsW(IntPtr guid, string enumerator, IntPtr hwnd, uint flags);
        [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        static extern IntPtr SetupDiGetClassDevsW(ref Guid guid, string enumerator, IntPtr hwnd, uint flags);
        [DllImport("setupapi.dll", SetLastError=true)]
        static extern bool SetupDiEnumDeviceInfo(IntPtr set, uint index, ref Info info);
        [DllImport("setupapi.dll", SetLastError=true)]
        static extern bool SetupDiEnumDeviceInterfaces(IntPtr set, IntPtr info, ref Guid guid, uint index, ref Interface item);
        [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        static extern bool SetupDiGetDeviceInterfaceDetailW(IntPtr set, ref Interface item, IntPtr detail, uint size, out uint needed, ref Info info);
        [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        static extern bool SetupDiGetDeviceRegistryPropertyW(IntPtr set, ref Info info, uint property, out uint type, byte[] data, uint size, out uint needed);
        [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        static extern bool SetupDiGetDeviceInstanceIdW(IntPtr set, ref Info info, StringBuilder id, uint size, out uint needed);
        [DllImport("setupapi.dll", SetLastError=true)]
        static extern bool SetupDiDestroyDeviceInfoList(IntPtr set);
        [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        static extern IntPtr SetupDiCreateDeviceInfoList(ref Guid guid, IntPtr hwnd);
        [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        static extern bool SetupDiCreateDeviceInfoW(IntPtr set, string name, ref Guid guid, string description, IntPtr hwnd, uint flags, ref Info info);
        [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        static extern bool SetupDiSetDeviceRegistryPropertyW(IntPtr set, ref Info info, uint property, byte[] data, uint size);
        [DllImport("setupapi.dll", SetLastError=true)]
        static extern bool SetupDiCallClassInstaller(uint function, IntPtr set, ref Info info);
        [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        static extern bool SetupCopyOEMInfW(string source, string media, uint mediaType, uint style, StringBuilder destination, uint size, out uint needed, IntPtr component);
        [DllImport("cfgmgr32.dll")]
        static extern uint CM_Get_DevNode_Status(out uint status, out uint problem, uint devInst, uint flags);
        [DllImport("ntdll.dll")]
        static extern int NtQuerySystemInformation(uint kind, ref CodeIntegrity info, uint size, out uint returned);

        static Info NewInfo() { Info i = new Info(); i.Size = (uint)Marshal.SizeOf(typeof(Info)); return i; }
        static string Id(IntPtr set, ref Info info) {
            StringBuilder s = new StringBuilder(1024); uint needed;
            if (!SetupDiGetDeviceInstanceIdW(set, ref info, s, (uint)s.Capacity, out needed)) throw new Win32Exception();
            return s.ToString();
        }
        static string Property(IntPtr set, ref Info info, uint key) {
            byte[] b = new byte[16384]; uint kind, needed;
            if (!SetupDiGetDeviceRegistryPropertyW(set, ref info, key, out kind, b, (uint)b.Length, out needed)) {
                int error = Marshal.GetLastWin32Error();
                if (error == 13 || error == 2 || error == 1168) return "";
                throw new Win32Exception(error);
            }
            return Encoding.Unicode.GetString(b, 0, checked((int)needed)).TrimEnd('\0');
        }
        static Device Read(IntPtr set, ref Info info) {
            Device d = new Device();
            d.InstanceId = Id(set, ref info);
            d.Description = Property(set, ref info, 12);
            if (d.Description.Length == 0) d.Description = Property(set, ref info, 0);
            d.HardwareIds = Property(set, ref info, 1).Split(new char[]{'\0'}, StringSplitOptions.RemoveEmptyEntries);
            d.Service = Property(set, ref info, 4);
            d.Present = CM_Get_DevNode_Status(out d.Status, out d.Problem, info.DevInst, 0) == 0;
            return d;
        }
        public static Device[] SerialPorts() {
            Guid guid = new Guid("86e0d1e0-8089-11d0-9ce4-08003e301f73");
            IntPtr set = SetupDiGetClassDevsW(ref guid, null, IntPtr.Zero, 0x12);
            if (set == Invalid) throw new Win32Exception();
            List<Device> devices = new List<Device>();
            try {
                for (uint n = 0; ; n++) {
                    Interface item = new Interface(); item.Size = (uint)Marshal.SizeOf(typeof(Interface));
                    if (!SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref guid, n, ref item)) {
                        int error = Marshal.GetLastWin32Error();
                        if (error == 259) break; throw new Win32Exception(error);
                    }
                    uint needed; Info info = NewInfo();
                    SetupDiGetDeviceInterfaceDetailW(set, ref item, IntPtr.Zero, 0, out needed, ref info);
                    if (Marshal.GetLastWin32Error() != 122 || needed < 6) throw new Win32Exception();
                    IntPtr detail = Marshal.AllocHGlobal(checked((int)needed));
                    try {
                        Marshal.WriteInt32(detail, IntPtr.Size == 8 ? 8 : 6);
                        if (!SetupDiGetDeviceInterfaceDetailW(set, ref item, detail, needed, out needed, ref info)) throw new Win32Exception();
                        Device d = Read(set, ref info);
                        d.InterfacePath = Marshal.PtrToStringUni(IntPtr.Add(detail, 4));
                        if (d.InstanceId.StartsWith(@"USB\VID_10C4&PID_EA60\", StringComparison.OrdinalIgnoreCase)) devices.Add(d);
                    } finally { Marshal.FreeHGlobal(detail); }
                }
            } finally { SetupDiDestroyDeviceInfoList(set); }
            return devices.ToArray();
        }
        // Include non-present nodes so rerunning setup never duplicates a hidden root.
        public static Device[] Roots() {
            IntPtr set = SetupDiGetClassDevsW(IntPtr.Zero, "ROOT", IntPtr.Zero, 4);
            if (set == Invalid) throw new Win32Exception();
            List<Device> devices = new List<Device>();
            try {
                for (uint n = 0; ; n++) {
                    Info info = NewInfo();
                    if (!SetupDiEnumDeviceInfo(set, n, ref info)) {
                        int error = Marshal.GetLastWin32Error();
                        if (error == 259) break; throw new Win32Exception(error);
                    }
                    string[] ids = Property(set, ref info, 1).Split('\0');
                    foreach (string id in ids) if (String.Equals(id, HardwareId, StringComparison.OrdinalIgnoreCase)) {
                        devices.Add(Read(set, ref info)); break;
                    }
                }
            } finally { SetupDiDestroyDeviceInfoList(set); }
            return devices.ToArray();
        }
        public static bool TestSigningActive() {
            CodeIntegrity info = new CodeIntegrity(); info.Length = (uint)Marshal.SizeOf(typeof(CodeIntegrity)); uint returned;
            int status = NtQuerySystemInformation(103, ref info, info.Length, out returned);
            if (status < 0) throw new InvalidOperationException("Cannot read active code-integrity state: " + status);
            return (info.Options & 2) != 0;
        }
        // MUTATING APIs: only called after explicit installation confirmation in Setup.ps1.
        public static string StageInf(string source) {
            StringBuilder destination = new StringBuilder(260); uint needed;
            // Never take ownership of a package previously staged by another installer.
            if (!SetupCopyOEMInfW(Path.GetFullPath(source), null, 1, 8, destination, (uint)destination.Capacity, out needed, IntPtr.Zero)) throw new Win32Exception();
            return Path.GetFileName(destination.ToString());
        }
        public static string CreateRoot() {
            if (Roots().Length != 0) throw new InvalidOperationException("An ESP32 root already exists.");
            Guid guid = new Guid("4d36e97d-e325-11ce-bfc1-08002be10318");
            IntPtr set = SetupDiCreateDeviceInfoList(ref guid, IntPtr.Zero);
            if (set == Invalid) throw new Win32Exception();
            try {
                Info info = NewInfo();
                if (!SetupDiCreateDeviceInfoW(set, "Esp32HciBus", ref guid, "ESP32 HCI experimental bus", IntPtr.Zero, 1, ref info)) throw new Win32Exception();
                byte[] ids = Encoding.Unicode.GetBytes(HardwareId + "\0\0");
                if (!SetupDiSetDeviceRegistryPropertyW(set, ref info, 1, ids, (uint)ids.Length)) throw new Win32Exception();
                string id = Id(set, ref info); // Nothing fallible after successful registration.
                if (!SetupDiCallClassInstaller(0x19, set, ref info)) throw new Win32Exception();
                return id;
            } finally { SetupDiDestroyDeviceInfoList(set); }
        }
    }
}
