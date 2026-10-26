"""Create a source-only browser upload archive from Git's non-ignored files."""
import hashlib
from pathlib import Path
import subprocess
import zipfile

root = Path(__file__).resolve().parents[1]
paths = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=root)
names = sorted(set(item.decode('utf-8') for item in paths.split(b'\0') if item))
output = root/'.tooling/github-upload/.source-upload.zip'
output.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
    for name in names:
        if name.startswith('.github/'):
            continue  # The import workflow is uploaded separately, never replaced by the archive.
        if Path(name).suffix.lower() in {'.pfx', '.p12', '.pem', '.key', '.cer'}:
            raise ValueError(f'Refusing a certificate/key in the source archive: {name}')
        archive.write(root/name, name)
digest = hashlib.sha256(output.read_bytes()).hexdigest()
print(f'Source archive: {output}')
print(f'SHA256: {digest}')
with zipfile.ZipFile(output) as archive:
    print(f'Files: {len(archive.infolist())}')
