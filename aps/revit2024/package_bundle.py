#!/usr/bin/env python3
"""Monta a estrutura AppBundle de APS a partir de DLLs locais legitimamente obtidas.

Não faz chamadas de rede, não armazena credenciais, nem inclui RevitAPI.dll.
"""
import argparse
import shutil
import tempfile
import zipfile
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description='Empacotar AppBundle FamilyBridge para APS Revit 2024')
    parser.add_argument('--dll', required=True, type=Path, help='FamilyBridge.Automation.dll compilado')
    parser.add_argument('--bridge', required=True, type=Path, help='DesignAutomationBridge.dll da Autodesk obtido legalmente')
    parser.add_argument('--output', type=Path, default=Path('FamilyBridgeAutomation.bundle.zip'))
    args = parser.parse_args()
    for required in (args.dll, args.bridge):
        if not required.is_file():
            parser.error(f'Arquivo não localizado: {required}')
    src = Path(__file__).resolve().parent
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as temp:
        bundle = Path(temp, 'FamilyBridgeAutomation.bundle')
        contents = bundle / 'Contents'
        contents.mkdir(parents=True)
        shutil.copy2(src / 'PackageContents.xml', bundle / 'PackageContents.xml')
        shutil.copy2(src / 'FamilyBridge.addin', contents / 'FamilyBridge.addin')
        shutil.copy2(args.dll, contents / 'FamilyBridge.Automation.dll')
        shutil.copy2(args.bridge, contents / 'DesignAutomationBridge.dll')
        with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
            for file in sorted(bundle.rglob('*')):
                if file.is_file():
                    archive.write(file, file.relative_to(Path(temp)).as_posix())
    print(f'AppBundle criado: {output}\nNão foi enviado à APS.')


if __name__ == '__main__':
    main()
