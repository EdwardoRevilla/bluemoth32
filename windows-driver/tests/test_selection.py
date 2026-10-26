import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from serial_device import kernel_path, choose, COM_GUID
from prepare_package import render_inf

PATH = '\\\\?\\usb#vid_10c4&pid_ea60#0001#{' + COM_GUID + '}'
DEVICE = dict(port='COM3', instance_id='USB\\VID_10C4&PID_EA60\\0001',
              interface_path=PATH, description='CP210x (COM3)')


class SelectionTests(unittest.TestCase):
    def test_exact_device(self):
        result = choose([DEVICE], 'com3', DEVICE['instance_id'])
        self.assertEqual(result['kernel_path'], '\\??\\' + PATH[4:])
        self.assertEqual(result['baud'], 115200)

    def test_not_first_port(self):
        other = dict(DEVICE, port='COM1', instance_id='ACPI\\PNP0501\\0')
        self.assertEqual(choose([other, DEVICE], 'COM3')['instance_id'], DEVICE['instance_id'])
        with self.assertRaises(ValueError):
            choose([other, DEVICE], 'COM1')

    def test_absent(self):
        with self.assertRaises(ValueError):
            choose([], 'COM3')

    def test_ambiguous(self):
        with self.assertRaises(ValueError):
            choose([DEVICE, DEVICE], 'COM3')

    def test_port_reassigned(self):
        with self.assertRaises(ValueError):
            choose([dict(DEVICE, instance_id='USB\\VID_10C4&PID_EA60\\0002')],
                   'COM3', DEVICE['instance_id'])

    def test_only_explicit_com_names(self):
        for port in ('COM0', '', 'COM3\n', '\\\\.\\COM3', 'LPT1', 'COM*'):
            with self.subTest(port=port), self.assertRaises(ValueError):
                choose([DEVICE], port)

    def test_reject_other_vid(self):
        with self.assertRaises(ValueError):
            kernel_path(PATH.replace('10c4', '1234'))

    def test_reject_other_interface(self):
        with self.assertRaises(ValueError):
            kernel_path(PATH.replace(COM_GUID, '00000000-0000-0000-0000-000000000000'))

    def test_reject_nt_path_and_com_alias(self):
        for path in ('\\DosDevices\\COM3', '\\Device\\Harddisk0', '\\??\\COM3', None):
            with self.subTest(path=path), self.assertRaises(ValueError):
                kernel_path(path)

    def test_reject_inf_injection(self):
        for suffix in ('"', '\n[Services]', '%DeviceName%', ';comment'):
            with self.subTest(suffix=suffix), self.assertRaises(ValueError):
                kernel_path(PATH.replace('0001#', '0001' + suffix + '#'))

    def test_render_selected_device(self):
        device = choose([DEVICE], 'COM3')
        output = render_inf('SerialDevicePath="@SERIAL_DEVICE_PATH@"', device)
        self.assertIn(device['kernel_path'], output)
        self.assertNotIn('@SERIAL_DEVICE_PATH@', output)

    def test_render_reject_inconsistent_manifest(self):
        device = choose([DEVICE], 'COM3')
        for change in (dict(schema=2), dict(baud=921600), dict(kernel_path='\\??\\COM1')):
            with self.subTest(change=change), self.assertRaises(ValueError):
                render_inf('@SERIAL_DEVICE_PATH@', dict(device, **change))

    def test_render_reject_ambiguous_template(self):
        for template in ('', '@SERIAL_DEVICE_PATH@ @SERIAL_DEVICE_PATH@'):
            with self.subTest(template=template), self.assertRaises(ValueError):
                render_inf(template, choose([DEVICE], 'COM3'))


if __name__ == '__main__':
    unittest.main()
