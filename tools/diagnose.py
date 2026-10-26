"""HCI smoke test and optional passive BLE scan over an explicit COM port."""
import argparse
import sys
import time
from hci import DiagnosticHost


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--list', action='store_true')
    parser.add_argument('--port', help='Explicit ESP32 port; never auto-select COM1')
    parser.add_argument('--baud', type=int, default=115200)
    parser.add_argument('--scan-seconds', type=float, default=0)
    args = parser.parse_args()
    import serial
    from serial.tools import list_ports
    if args.list:
        for port in list_ports.comports():
            print(port.device, port.description, port.hwid)
        return
    if not args.port:
        parser.error('--port is required unless --list is used')
    if not 0 <= args.scan_seconds <= 60:
        parser.error('--scan-seconds must be between 0 and 60')
    # Set modem lines BEFORE open to minimize DevKit auto-reset effects.
    # Some USB-UART drivers still pulse them: allow boot to settle, then drain.
    port = serial.Serial(port=None, baudrate=args.baud, timeout=0.1,
                         write_timeout=2, rtscts=False, dsrdtr=False)
    port.dtr = False
    port.rts = False
    port.port = args.port
    with port:
        time.sleep(2)
        port.reset_input_buffer()
        host = DiagnosticHost(port)
        host.send(0x0c03)  # Reset
        version = host.send(0x1001)  # Read Local Version Information
        if len(version) != 9:
            raise ValueError('Unexpected Local Version response length')
        features = host.send(0x2003)  # LE Read Local Supported Features
        if len(features) != 9:
            raise ValueError('Unexpected LE features response length')
        print('PASS: Reset, Local Version, LE Features. This is NOT a Windows radio.')
        if args.scan_seconds:
            host.send(0x0c01, bytes.fromhex('ff ff ff ff ff ff ff 3f'))
            host.send(0x2001, bytes.fromhex('1f 00 00 00 00 00 00 00'))
            host.send(0x200b, bytes.fromhex('00 a0 00 50 00 00 00'))
            reports = 0
            try:
                host.send(0x200c, b'\x01\x01')
                deadline = time.monotonic() + args.scan_seconds
                while time.monotonic() < deadline:
                    for packet in host.receive():
                        if len(packet) >= 5 and packet[:2] == b'\x04\x3e' and packet[3] == 2:
                            reports += 1
            finally:
                host.send(0x200c, b'\x00\x00')
            print(f'BLE advertising report events: {reports}; zero is inconclusive.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, TimeoutError) as exc:
        print(f'FAIL: {exc}', file=sys.stderr)
        sys.exit(1)
