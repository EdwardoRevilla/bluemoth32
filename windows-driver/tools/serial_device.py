"""Resolve a present COM device to its exact Windows device interface.

Read-only: no handles to the serial endpoint, no registry writes or resets.
"""
import argparse
import ctypes
from ctypes import wintypes as w
import json
from pathlib import Path
import re
import sys

COM_GUID = '86e0d1e0-8089-11d0-9ce4-08003e301f73'
INSTANCE_PREFIX = 'USB\\VID_10C4&PID_EA60\\'


def kernel_path(path):
    """Accept only a CP210x COM interface, never a COM alias or arbitrary NT path."""
    pattern = (r'\\\\\?\\USB#VID_10C4&PID_EA60#'
               r'[A-Z0-9_&+.-]+#\{' + COM_GUID + r'\}')
    if not isinstance(path, str) or not re.fullmatch(pattern, path, re.IGNORECASE):
        raise ValueError('Expected an exact CP210x COM device interface path')
    return '\\??\\' + path[4:]


def choose(devices, port, instance=None):
    if not re.fullmatch(r'COM[1-9][0-9]*', port, re.IGNORECASE):
        raise ValueError('Specify an explicit COM port, for example COM3')
    matches = [d for d in devices if d['port'].upper() == port.upper()]
    if len(matches) != 1:
        raise ValueError('The selected port is absent or ambiguous')
    selected = matches[0]
    if not selected['instance_id'].upper().startswith(INSTANCE_PREFIX):
        raise ValueError('The selected device is not USB VID_10C4 PID_EA60')
    if instance and selected['instance_id'].upper() != instance.upper():
        raise ValueError('The selected port now belongs to a different USB instance')
    return dict(selected, kernel_path=kernel_path(selected['interface_path']),
                baud=115200, schema=1)


def enumerate_interfaces():
    if sys.platform != 'win32':
        raise OSError('SetupAPI inventory requires Windows')
    import uuid
    class GUID(ctypes.Structure):
        _fields_ = [('raw', ctypes.c_ubyte * 16)]
    class INTERFACE(ctypes.Structure):
        _fields_ = [('cbSize', w.DWORD), ('guid', GUID), ('flags', w.DWORD),
                    ('reserved', ctypes.c_void_p)]
    class DEVINFO(ctypes.Structure):
        _fields_ = [('cbSize', w.DWORD), ('guid', GUID), ('devinst', w.DWORD),
                    ('reserved', ctypes.c_void_p)]
    api = ctypes.WinDLL('setupapi', use_last_error=True)
    api.SetupDiGetClassDevsW.argtypes = [ctypes.POINTER(GUID), w.LPCWSTR, w.HWND, w.DWORD]
    api.SetupDiGetClassDevsW.restype = w.HANDLE
    api.SetupDiEnumDeviceInterfaces.argtypes = [w.HANDLE, ctypes.c_void_p,
        ctypes.POINTER(GUID), w.DWORD, ctypes.POINTER(INTERFACE)]
    api.SetupDiEnumDeviceInterfaces.restype = w.BOOL
    api.SetupDiGetDeviceInterfaceDetailW.argtypes = [w.HANDLE, ctypes.POINTER(INTERFACE),
        ctypes.c_void_p, w.DWORD, ctypes.POINTER(w.DWORD), ctypes.POINTER(DEVINFO)]
    api.SetupDiGetDeviceInterfaceDetailW.restype = w.BOOL
    api.SetupDiGetDeviceInstanceIdW.argtypes = [w.HANDLE, ctypes.POINTER(DEVINFO),
        w.LPWSTR, w.DWORD, ctypes.POINTER(w.DWORD)]
    api.SetupDiGetDeviceInstanceIdW.restype = w.BOOL
    api.SetupDiGetDeviceRegistryPropertyW.argtypes = [w.HANDLE, ctypes.POINTER(DEVINFO),
        w.DWORD, ctypes.POINTER(w.DWORD), ctypes.c_void_p, w.DWORD, ctypes.POINTER(w.DWORD)]
    api.SetupDiGetDeviceRegistryPropertyW.restype = w.BOOL
    api.SetupDiDestroyDeviceInfoList.argtypes = [w.HANDLE]
    api.SetupDiDestroyDeviceInfoList.restype = w.BOOL
    guid = GUID((ctypes.c_ubyte * 16).from_buffer_copy(uuid.UUID(COM_GUID).bytes_le))
    handle = api.SetupDiGetClassDevsW(ctypes.byref(guid), None, None, 0x12)
    if handle == ctypes.c_void_p(-1).value:
        raise ctypes.WinError(ctypes.get_last_error())
    devices = []
    try:
        index = 0
        while True:
            interface = INTERFACE()
            interface.cbSize = ctypes.sizeof(interface)
            if not api.SetupDiEnumDeviceInterfaces(handle, None, ctypes.byref(guid),
                                                   index, ctypes.byref(interface)):
                if ctypes.get_last_error() == 259:
                    break
                raise ctypes.WinError(ctypes.get_last_error())
            index += 1
            needed = w.DWORD()
            api.SetupDiGetDeviceInterfaceDetailW(handle, ctypes.byref(interface), None,
                                                 0, ctypes.byref(needed), None)
            if ctypes.get_last_error() != 122 or needed.value < 6:
                raise ctypes.WinError(ctypes.get_last_error())
            detail = ctypes.create_string_buffer(needed.value)
            ctypes.cast(detail, ctypes.POINTER(w.DWORD))[0] = 8 if ctypes.sizeof(w.HANDLE) == 8 else 6
            info = DEVINFO()
            info.cbSize = ctypes.sizeof(info)
            if not api.SetupDiGetDeviceInterfaceDetailW(handle, ctypes.byref(interface),
                    detail, needed, ctypes.byref(needed), ctypes.byref(info)):
                raise ctypes.WinError(ctypes.get_last_error())
            # DevicePath starts at offset 4; cbSize includes native struct padding.
            path = ctypes.wstring_at(ctypes.addressof(detail) + 4)
            instance = ctypes.create_unicode_buffer(1024)
            if not api.SetupDiGetDeviceInstanceIdW(handle, ctypes.byref(info), instance,
                                                   len(instance), None):
                raise ctypes.WinError(ctypes.get_last_error())
            friendly = ctypes.create_unicode_buffer(2048)
            if not api.SetupDiGetDeviceRegistryPropertyW(handle, ctypes.byref(info),
                    12, None, friendly, ctypes.sizeof(friendly), None):
                continue  # No friendly name: never guess a port number.
            match = re.search(r'\((COM[1-9][0-9]*)\)$', friendly.value, re.IGNORECASE)
            if match:
                devices.append(dict(port=match[1], instance_id=instance.value,
                                    interface_path=path, description=friendly.value))
    finally:
        api.SetupDiDestroyDeviceInfoList(handle)
    return devices


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port')
    parser.add_argument('--instance', help='Optional expected USB instance ID')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    devices = enumerate_interfaces()
    result = choose(devices, args.port, args.instance) if args.port else devices
    encoded = json.dumps(result, indent=2)
    if args.output:
        if not args.port:
            parser.error('--output requires --port')
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded + '\n', encoding='utf-8')
    print(encoded)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError) as exc:
        raise SystemExit(f'FAIL: {exc}')
