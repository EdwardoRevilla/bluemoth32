"""Export BlueMoth32's real Preview text as SVG, optionally PNG with Pillow.

This is a rendered interface preview, not a desktop screenshot. Preview never
loads the native helper or queries/modifies devices, certificates or boot policy.
"""
import argparse
import html
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
COLORS = {'green': '#00ff00', 'muted': '#008000', 'text': '#c0c0c0'}


def color_for(line):
    text = line.strip()
    if text.startswith(('---', 'USB [', 'RETIRAR LA PRUEBA')):
        return COLORS['muted']
    if text.startswith(('[1]', '[2]', '[3]', '[5]', '[0]', 'VISTA PREVIA', 'Un puente')):
        return COLORS['text']
    return COLORS['green']


def draw_svg(path, lines, title, width, top=58, step=21):
    height = top + len(lines) * step + 24
    elements = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        f'<title>{html.escape(title)}</title>',
        '<desc>BlueMoth32: radio-antenna moth with an ESP32 chip body. ASCII interface preview.</desc>',
        f'<rect width="{width}" height="{height}" rx="9" fill="#0c0e0c"/>',
        f'<path d="M9 0H{width-9}Q{width} 0 {width} 9V36H0V9Q0 0 9 0" fill="#202420"/>',
        f'<text x="24" y="23" fill="#c0c0c0" font-family="Consolas, monospace" font-size="13">{html.escape(title)}</text>',
        '<g font-family="Consolas, Cascadia Mono, monospace" font-size="16" xml:space="preserve">',
    ]
    for index, line in enumerate(lines):
        elements.append(f'<text x="24" y="{top + index*step}" fill="{color_for(line)}">{html.escape(line)}</text>')
    elements.extend(['</g>', '</svg>'])
    path.write_text('\n'.join(elements) + '\n', encoding='utf-8')
    return height


def draw_png(path, lines, title, width, height, top=58, step=21):
    from PIL import Image, ImageDraw, ImageFont
    font_path = Path('C:/Windows/Fonts/consola.ttf')
    font = ImageFont.truetype(str(font_path), 16)
    label_font = ImageFont.truetype(str(font_path), 13)
    image = Image.new('RGB', (width, height), '#0c0e0c')
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, width, 35), fill='#202420')
    draw.text((24, 18), title, font=label_font, fill='#c0c0c0', anchor='lm')
    for index, line in enumerate(lines):
        draw.text((24, top + index*step), line, font=font, fill=color_for(line), anchor='ls')
    image.save(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--png', action='store_true')
    args = parser.parse_args()
    result = subprocess.run([
        'powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
        str(ROOT/'windows-driver/installer/Setup.ps1'), '-Action', 'Preview',
    ], check=True, capture_output=True, text=True, encoding='utf-8')
    lines = result.stdout.strip('\r\n').splitlines()
    if not lines or max(map(len, lines)) > 80:
        raise ValueError('Preview must fit an 80-column terminal')
    destination = ROOT/'assets/brand'
    destination.mkdir(parents=True, exist_ok=True)
    title = 'BlueMoth32 / vista previa de terminal'
    width = 816
    height = draw_svg(destination/'terminal-preview.svg', lines, title, width)
    if args.png:
        draw_png(destination/'terminal-preview.png', lines, title, width, height)
    theme = (ROOT/'windows-driver/installer/Terminal.psm1').read_text(encoding='utf-8')
    logo = re.search(r"return @'\n(.*?)\n'@", theme, re.DOTALL)
    if not logo:
        raise ValueError('ASCII mascot was not found in the source theme')
    logo_lines = logo.group(1).splitlines()
    inset = ' ' * ((77-max(map(len, logo_lines)))//2)
    brand_lines = [inset + line for line in logo_lines] + ['',
        'B L U E M O T H 3 2'.center(77),
        'ESP32 Bluetooth HCI bridge for Windows'.center(77)]
    draw_svg(destination/'bluemoth32.svg', brand_lines, 'BlueMoth32', width)
    print(f'Preview exported: {destination}')


if __name__ == '__main__':
    main()
