#!/usr/bin/env python3
"""Package development Mac disk images or a per-user Windows NSIS installer.

Does not publish, sign with a distribution identity, or certify target execution.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
VERSION = "0.3"


def checksum(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    path.with_suffix(path.suffix + '.sha256').write_text(digest.hexdigest() + '  ' + path.name + '\n')


def mac(app, arch, distribution=False):
    app = app.resolve()
    subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True)
    if distribution:
        details = subprocess.check_output(['codesign', '-dv', '--verbose=4', str(app)], stderr=subprocess.STDOUT, text=True)
        if 'Authority=Developer ID Application:' not in details or 'runtime' not in details:
            raise SystemExit('Distribution packaging requires a Developer ID signature and hardened runtime.')
        subprocess.run(['xcrun', 'stapler', 'validate', str(app)], check=True)
        subprocess.run(['spctl', '--assess', '--type', 'execute', str(app)], check=True)
    actual = subprocess.check_output(['lipo', '-archs', str(app / 'Contents/MacOS/RDataCraft')], text=True).split()
    if arch not in actual:
        raise SystemExit('Mac host CPU does not match the requested disk image.')
    stage = ROOT / 'artifacts/installer-staging' / VERSION / arch
    if stage.exists():
        raise SystemExit('Choose a clean installer staging directory: ' + str(stage))
    stage.mkdir(parents=True)
    shutil.copytree(app, stage / app.name, symlinks=True, ignore=shutil.ignore_patterns('.DS_Store'))
    (stage / 'Applications').symlink_to('/Applications')
    (stage / 'Read me.txt').write_text(
        f'RDataCraft {VERSION} — {arch} Mac\n\nDrag the app into Applications, then open it there.\n'
        'R and packages are bundled; no separate R installation is required.\n'
        'Help contains examples and the PCA analysis guide.\n\n' +
        ('Developer ID signed and Apple-notarized application.\n' if distribution else
         'Release candidate: ad-hoc signed, not Apple-notarized.\n') +
        'See the accompanying release report for platform validation.\n')
    image = ROOT / 'dist' / f'RDataCraft-{VERSION}-macos-{arch}.dmg'
    subprocess.run(['hdiutil', 'create', '-ov', '-format', 'UDZO', '-volname',
                    f'RDataCraft {VERSION} {arch}', '-srcfolder', str(stage), str(image)], check=True)
    subprocess.run(['hdiutil', 'verify', str(image)], check=True)
    checksum(image)
    return image


def nsis_quote(value):
    return str(value).replace('$', '$$').replace('"', '$\\"')


def windows(bundle, compiler, nsis_dir, certificate=None, timestamp=None, signtool='signtool.exe', webview_installer=None):
    bundle = bundle.resolve()
    metadata = json.loads((bundle / 'build-platform.json').read_text())
    if metadata['platform'] != 'Windows' or metadata['architecture'] != 'x86_64' or metadata['version'] != VERSION:
        raise SystemExit('Expected the matching Windows x64 portable bundle.')
    # Reuse the PE/package audit immediately before embedding the runtime.
    from package_portable import verify_windows_runtime
    audit = verify_windows_runtime(bundle / 'runtime/R', bundle / 'runtime/library')
    native = (bundle/'RDataCraft.exe').is_file()
    if native:
        from fetch_windows_components import verify
        if not webview_installer:raise SystemExit('The native Windows installer requires --webview-installer for offline setup.')
        verify(webview_installer)
    output = ROOT / 'dist' / f'RDataCraft-{VERSION}-windows-x64-setup.exe'
    script = ROOT / 'artifacts/installer-staging/windows.nsi'
    script.parent.mkdir(parents=True, exist_ok=True)
    key = f'Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\RDataCraft-{VERSION}'
    lines = [
        'Unicode true', '!include "MUI2.nsh"', '!include "x64.nsh"',
        f'Name "RDataCraft {VERSION}"', f'OutFile "{nsis_quote(output)}"',
        f'InstallDir "$LOCALAPPDATA\\Programs\\RDataCraft-{VERSION}"',
        'RequestExecutionLevel user', 'SetCompressor /FINAL zlib',
        'VIProductVersion "0.3.0.2"', 'VIAddVersionKey "ProductName" "RDataCraft"',
        'VIAddVersionKey "FileDescription" "RDataCraft 0.3 development setup"',
        'VIAddVersionKey "FileVersion" "0.3.0.2"', 'VIAddVersionKey "LegalCopyright" "RDataCraft contributors; GPL-3.0"',
        '!insertmacro MUI_PAGE_WELCOME', f'!insertmacro MUI_PAGE_LICENSE "{nsis_quote(ROOT / "LICENSE")}"',
        '!insertmacro MUI_PAGE_DIRECTORY', '!insertmacro MUI_PAGE_INSTFILES', '!insertmacro MUI_PAGE_FINISH',
        '!insertmacro MUI_UNPAGE_CONFIRM', '!insertmacro MUI_UNPAGE_INSTFILES', '!insertmacro MUI_LANGUAGE "English"',
        'Function .onInit', '  ${IfNot} ${IsNativeAMD64}',
        '    MessageBox MB_OK|MB_ICONSTOP "This package requires x64 Windows. Windows ARM is not supported by this build."',
        '    Abort', '  ${EndIf}', 'FunctionEnd',
        'Section "RDataCraft"', '  SetShellVarContext current', '  SetOutPath "$INSTDIR"',
        f'  File /r "{nsis_quote(bundle)}/*"', '  WriteUninstaller "$INSTDIR\\Uninstall.exe"',
        f'  CreateDirectory "$SMPROGRAMS\\RDataCraft {VERSION}"',
        f'  CreateShortCut "$SMPROGRAMS\\RDataCraft {VERSION}\\RDataCraft.lnk" "$INSTDIR\\' + ('RDataCraft.exe"' if native else 'Launch RDataCraft.cmd"'),
        f'  CreateShortCut "$SMPROGRAMS\\RDataCraft {VERSION}\\RDataCraft help.lnk" "$INSTDIR\\examples\\RDataCraft help.html"',
        f'  CreateShortCut "$SMPROGRAMS\\RDataCraft {VERSION}\\Uninstall.lnk" "$INSTDIR\\Uninstall.exe"',
        f'  WriteRegStr HKCU "{key}" "DisplayName" "RDataCraft {VERSION}"',
        f'  WriteRegStr HKCU "{key}" "DisplayVersion" "{VERSION}"',
        f'  WriteRegStr HKCU "{key}" "InstallLocation" "$INSTDIR"',
        f'  WriteRegStr HKCU "{key}" "UninstallString" \'$\\"$INSTDIR\\Uninstall.exe$\\"\'',
        f'  WriteRegDWORD HKCU "{key}" "NoModify" 1',
        f'  WriteRegDWORD HKCU "{key}" "NoRepair" 1', 'SectionEnd',
        'Section "Uninstall"', '  SetShellVarContext current',
    ]
    if native:
        # Install Microsoft's separately licensed, signed Evergreen component only
        # when absent. It remains shared after RDataCraft is uninstalled.
        section = lines.index('Section "RDataCraft"')
        lines[section:section] = [
            'Section "Microsoft WebView2 (if required)"',
            '  ReadRegStr $0 HKCU "Software\\Microsoft\\EdgeUpdate\\Clients\\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" "pv"',
            '  StrCmp $0 "" 0 webview_done',
            '  SetRegView 32',
            '  ReadRegStr $0 HKLM "Software\\Microsoft\\EdgeUpdate\\Clients\\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" "pv"',
            '  StrCmp $0 "" 0 webview_done',
            '  InitPluginsDir', '  SetOutPath "$PLUGINSDIR"',
            f'  File /oname=WebView2Setup.exe "{nsis_quote(webview_installer.resolve())}"',
            '  DetailPrint "Installing Microsoft WebView2 Runtime…"',
            '  ExecWait \'"$PLUGINSDIR\\WebView2Setup.exe" /silent /install\' $0',
            '  StrCmp $0 "0" webview_done',
            '  IfSilent +2',
            '  MessageBox MB_OK|MB_ICONSTOP "Microsoft WebView2 could not be installed. Restart Windows and run setup again."',
            '  SetErrorLevel 1', '  Abort',
            '  webview_done:', '  SetRegView 64', 'SectionEnd']
        # The setup itself uses the same app icon and exposes a finish-page launch.
        lines[1:1] = [f'Icon "{nsis_quote(ROOT/"desktop/windows/RDataCraft.ico")}"',
                      '!define MUI_FINISHPAGE_RUN "$INSTDIR\\RDataCraft.exe"',
                      '!define MUI_FINISHPAGE_RUN_TEXT "Open RDataCraft"']
    if certificate or timestamp:
        if os.name != 'nt' or not certificate or not timestamp:
            raise SystemExit('Windows signing needs a Windows host, --sign-certificate and --timestamp-url.')
        from sign_windows import signing_command
        signing_command(signtool, certificate, timestamp, output)  # Validate public configuration first.
        arguments = [sys.executable, str(ROOT/'scripts/sign_windows.py'), '--certificate', certificate,
                     '--timestamp-url', timestamp, '--signtool', signtool, '--file', '%1']
        if any(any(c in str(arg) for c in '\"\'\n\r!') or ('%' in str(arg) and arg != '%1') for arg in arguments):
            raise SystemExit('Unsupported quoting character in an NSIS signing path or argument.')
        command = ' '.join('"' + str(arg) + '"' for arg in arguments)
        # Fail compilation if either the embedded uninstaller or final setup
        # cannot be signed AND verified. No signing passwords enter this script.
        lines[0:0] = ["!uninstfinalize '" + nsis_quote(command) + "' = 0",
                      "!finalize '" + nsis_quote(command) + "' = 0"]
    # Delete only the files installed by this package; preserve extra user studies.
    for file in sorted(bundle.rglob('*')):
        if file.is_file():
            relative = str(file.relative_to(bundle)).replace('/', '\\')
            lines.append(f'  Delete "$INSTDIR\\{nsis_quote(relative)}"')
    lines += ['  Delete "$INSTDIR\\Uninstall.exe"']
    for folder in sorted((p for p in bundle.rglob('*') if p.is_dir()), key=lambda p: len(p.parts), reverse=True):
        relative = str(folder.relative_to(bundle)).replace('/', '\\')
        lines.append(f'  RMDir "$INSTDIR\\{nsis_quote(relative)}"')
    lines += [f'  Delete "$SMPROGRAMS\\RDataCraft {VERSION}\\RDataCraft.lnk"',
              f'  Delete "$SMPROGRAMS\\RDataCraft {VERSION}\\RDataCraft help.lnk"',
              f'  Delete "$SMPROGRAMS\\RDataCraft {VERSION}\\Uninstall.lnk"',
              f'  RMDir "$SMPROGRAMS\\RDataCraft {VERSION}"', '  RMDir "$INSTDIR"',
              f'  DeleteRegKey HKCU "{key}"', 'SectionEnd']
    script.write_text('\n'.join(lines) + '\n')
    environment = dict(os.environ, NSISDIR=str(nsis_dir.resolve()))
    subprocess.run([str(compiler.resolve()), '-V2', str(script)], env=environment, check=True)
    checksum(output)
    (ROOT / 'artifacts/windows-installer-audit-0.3.json').write_text(json.dumps(
        dict(audit, installer='NSIS', execution_tested=False, per_user=True,
             setup_and_uninstaller_signatures_verified=bool(certificate),
             uninstall_preserves_extra_files=True, script=str(script.relative_to(ROOT))), indent=2) + '\n')
    return output


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mac-app', type=Path)
    parser.add_argument('--arch', choices=['arm64', 'x86_64'])
    parser.add_argument('--windows-bundle', type=Path)
    parser.add_argument('--makensis', type=Path)
    parser.add_argument('--nsis-dir', type=Path)
    parser.add_argument('--distribution', action='store_true', help='Require a notarized Developer ID Mac app.')
    parser.add_argument('--sign-certificate', help='Existing Windows certificate-store SHA-1 thumbprint.')
    parser.add_argument('--timestamp-url', help='HTTPS RFC 3161 endpoint from your signing provider.')
    parser.add_argument('--signtool', default='signtool.exe')
    parser.add_argument('--webview-installer', type=Path, help='Pinned official offline WebView2 x64 runtime installer.')
    args = parser.parse_args()
    if args.mac_app and args.arch:
        print(mac(args.mac_app, args.arch, args.distribution))
    elif args.windows_bundle and args.makensis and args.nsis_dir:
        if args.distribution and not args.sign_certificate:
            parser.error('Distribution packaging on Windows requires --sign-certificate and --timestamp-url.')
        print(windows(args.windows_bundle, args.makensis, args.nsis_dir,
                      args.sign_certificate, args.timestamp_url, args.signtool, args.webview_installer))
    else:
        parser.error('Choose --mac-app/--arch or --windows-bundle/--makensis/--nsis-dir.')
