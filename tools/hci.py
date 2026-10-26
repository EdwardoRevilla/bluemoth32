"""Strict incremental H4 decoder and synchronous diagnostic commands.

No Windows Bluetooth integration is provided by this module.
"""
import struct
import time


class H4Decoder:
    def __init__(self):
        self.buffer = bytearray()

    def feed(self, data):
        self.buffer.extend(data)
        packets = []
        while self.buffer:
            kind = self.buffer[0]
            headers = {1: 3, 2: 4, 3: 3, 4: 2}
            if kind not in headers:
                raise ValueError(f"Invalid H4 type {kind:#x}; reset controller and drain boot output")
            header = headers[kind]
            if len(self.buffer) < 1 + header:
                break
            length = (int.from_bytes(self.buffer[3:5], 'little') if kind == 2
                      else self.buffer[header])
            if kind == 2 and length > 1021:
                raise ValueError("ACL exceeds this ESP32 prototype's 1021-byte limit")
            total = 1 + header + length
            if len(self.buffer) < total:
                break
            packets.append(bytes(self.buffer[:total]))
            del self.buffer[:total]
        return packets


def command(opcode, payload=b''):
    if len(payload) > 255:
        raise ValueError('HCI command parameters exceed 255 bytes')
    return b'\x01' + struct.pack('<HB', opcode, len(payload)) + payload


def completion(packet, opcode):
    """Return Command Complete parameters, or None for unrelated events.

    These diagnostics use only commands that finish with Command Complete.
    Command Status failure is surfaced; success does not mean completion.
    """
    if len(packet) < 3 or packet[0] != 4:
        return None
    if packet[1] == 0x0e:
        if len(packet) < 7:
            raise ValueError('Truncated Command Complete')
        if int.from_bytes(packet[4:6], 'little') == opcode:
            if packet[6]:
                raise RuntimeError(f'HCI {opcode:#06x} failed: status {packet[6]:#04x}')
            return packet[6:]
    if packet[1] == 0x0f:
        if len(packet) != 7:
            raise ValueError('Malformed Command Status')
        if int.from_bytes(packet[5:7], 'little') == opcode and packet[3]:
            raise RuntimeError(f'HCI command rejected: {packet[3]:#04x}')
    return None


class DiagnosticHost:
    def __init__(self, port):
        self.port = port
        self.decoder = H4Decoder()

    def receive(self):
        packets = self.decoder.feed(self.port.read(max(1, self.port.in_waiting)))
        for packet in packets:
            print('RX', packet.hex(' '), flush=True)
        return packets

    def send(self, opcode, payload=b'', timeout=3):
        packet = command(opcode, payload)
        print('TX', packet.hex(' '), flush=True)
        if self.port.write(packet) != len(packet):
            raise IOError('Incomplete serial write')
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            for event in self.receive():
                result = completion(event, opcode)
                if result is not None:
                    return result
        raise TimeoutError(f'No Command Complete for {opcode:#06x}')
