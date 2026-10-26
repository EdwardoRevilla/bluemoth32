import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from hci import H4Decoder, command, completion, DiagnosticHost


class H4Tests(unittest.TestCase):
    def test_reset_encoding(self):
        self.assertEqual(command(0x0c03), bytes.fromhex('01 03 0c 00'))

    def test_all_fragment_boundaries(self):
        wire = bytes.fromhex('04 0e 04 01 03 0c 00 04 3e 02 02 00')
        for split in range(len(wire) + 1):
            decoder = H4Decoder()
            self.assertEqual(decoder.feed(wire[:split]) + decoder.feed(wire[split:]),
                             [wire[:7], wire[7:]])

    def test_acl_and_sco(self):
        wire = bytes.fromhex('02 01 00 02 00 aa bb 03 01 00 01 cc')
        self.assertEqual(H4Decoder().feed(wire), [wire[:7], wire[7:]])

    def test_invalid_type(self):
        with self.assertRaises(ValueError):
            H4Decoder().feed(b'boot log')

    def test_overlong_acl(self):
        with self.assertRaises(ValueError):
            H4Decoder().feed(bytes.fromhex('02 01 00 ff ff'))

    def test_complete_matching(self):
        event = bytes.fromhex('04 0e 04 01 03 0c 00')
        self.assertEqual(completion(event, 0x0c03), b'\x00')
        self.assertIsNone(completion(event, 0x1001))

    def test_rejection(self):
        with self.assertRaises(RuntimeError):
            completion(bytes.fromhex('04 0e 04 01 03 0c 01'), 0x0c03)
        with self.assertRaises(RuntimeError):
            completion(bytes.fromhex('04 0f 04 01 01 03 0c'), 0x0c03)

    def test_status_success_is_not_completion(self):
        self.assertIsNone(completion(bytes.fromhex('04 0f 04 00 01 03 0c'), 0x0c03))

    def test_truncated_complete(self):
        with self.assertRaises(ValueError):
            completion(bytes.fromhex('04 0e 01 01'), 0x0c03)

    def test_command_length_limit(self):
        with self.assertRaises(ValueError):
            command(1, bytes(256))

    def test_host_timeout(self):
        class Port:
            def write(self, data):
                return len(data)
        with self.assertRaises(TimeoutError):
            DiagnosticHost(Port()).send(0x0c03, timeout=0)


if __name__ == '__main__':
    unittest.main()
