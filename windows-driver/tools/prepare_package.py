"""Produce an unsigned per-device package; does not install or sign anything."""
import argparse
import json
from pathlib import Path
import shutil
from serial_device import kernel_path, INSTANCE_PREFIX


def render_inf(template, device):
    if device.get('schema') != 1 or device.get('baud') != 115200:
        raise ValueError('Unsupported manifest schema or baud rate')
    if not device.get('instance_id', '').upper().startswith(INSTANCE_PREFIX):
        raise ValueError('Manifest does not select the expected CP210x USB device')
    path = kernel_path(device.get('interface_path'))
    if path != device.get('kernel_path'):
        raise ValueError('Manifest interface path and kernel path disagree')
    if template.count('@SERIAL_DEVICE_PATH@') != 1:
        raise ValueError('INF template must contain one serial path marker')
    return template.replace('@SERIAL_DEVICE_PATH@', path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', type=Path, required=True)
    parser.add_argument('--sys', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if not args.sys.is_file():
        parser.error('Build Esp32HciBus.sys with the WDK first')
    root = Path(__file__).resolve().parents[1]
    rendered = render_inf((root/'src/WDK/Esp32HciBus.inx').read_text(),
                          json.loads(args.device.read_text(encoding='utf-8')))
    args.output.mkdir(parents=True, exist_ok=True)
    inf = args.output/'Esp32HciBus.inf'
    inf.write_text(rendered, encoding='utf-8')
    destination = args.output/'Esp32HciBus.sys'
    if args.sys.resolve() != destination.resolve():
        shutil.copy2(args.sys, destination)
    # A previous catalog would be invalid after editing an INF. Refuse to reuse it.
    catalog = args.output/'Esp32HciBus.cat'
    if catalog.exists():
        catalog.unlink()
    print(f'Unsigned per-device package: {args.output.resolve()}')
    print('Next: InfVerif, Inf2Cat, accepted signing process, test-machine validation.')


if __name__ == '__main__':
    main()
