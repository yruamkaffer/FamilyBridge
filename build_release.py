"""Reproduz RBZ instalável e ZIP de projeto sem credenciais locais."""
from pathlib import Path
import zipfile

BASE = Path(__file__).resolve().parent
VERSION = '0.8.1'


def build(destination):
    destination = Path(destination).resolve()
    destination.mkdir(parents=True, exist_ok=True)
    rbz = BASE / ('FamilyBridge_v' + VERSION + '.rbz')
    with zipfile.ZipFile(rbz, 'w', zipfile.ZIP_DEFLATED) as archive:
        for file in sorted((BASE / 'sketchup').rglob('*')):
            if file.is_file():
                archive.write(file, file.relative_to(BASE / 'sketchup'))
    output = destination / ('FamilyBridge_projeto_v' + VERSION + '.zip')
    # Allowlist keeps local configuration, test caches and job receipts private.
    paths = [BASE / name for name in ('README.md', 'CHANGELOG.md', 'CONTRIBUTING.md',
                                      'SECURITY.md', 'NOTICE.md', '.gitignore',
                                      'build_release.py', rbz.name)]
    for root in ('sketchup', 'tests', 'aps', 'docs'):
        paths += [p for p in (BASE / root).rglob('*') if p.is_file()
                  and p.suffix in ('.py', '.rb', '.html', '.cs', '.csproj', '.addin', '.xml', '.ps1', '.md', '.png', '.js', '.ts', '.txt', '.yml')
                  and not {'bin', 'obj', '__pycache__'}.intersection(p.relative_to(BASE).parts)]
    paths += [BASE / 'sketchup/family_bridge/resources/FamilyBridgeAutomation2024.bundle.zip',
              BASE / 'sketchup/family_bridge/resources/FamilyBridgeStepToSat.bundle.zip']
    paths += [BASE / 'aps/urls.example.json', BASE / 'aps/revit2024/activity.template.json']
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
        for file in sorted(set(paths)):
            archive.write(file, Path('FamilyBridge_v' + VERSION) / file.relative_to(BASE))
    print(output)


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, default=BASE.parent / 'dist')
    build(parser.parse_args().output)
