#!/usr/bin/env python3
"""Build RDataCraft.app with a native macOS host and an app-local R runtime."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import os
import plistlib
import shutil
import subprocess
from runtime_inventory import write_notices
from build_ai import build as build_ai

ROOT = Path(__file__).resolve().parent.parent
VERSION = "0.4"


def run(*args):
    subprocess.run(list(map(str, args)), check=True, cwd=ROOT)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="Build into a separate .app path to preserve an open earlier version.")
    parser.add_argument("--arch",choices=["arm64","x86_64"],default=platform.machine())
    parser.add_argument("--runtime-root",type=Path,default=ROOT/"runtime")
    parser.add_argument("--cross-build",action="store_true",help="Compile a different Mac CPU without claiming target execution tests.")
    parser.add_argument("--runtime-manifest",type=Path,help="Previously verified target dependency manifest, required for cross-builds.")
    parser.add_argument("--allow-rosetta",action="store_true",help="Explicitly allow an Intel R runtime in an ARM development host.")
    parser.add_argument("--zip", action="store_true", help="Create a development ZIP containing RDataCraft.app.")
    parser.add_argument("--install", action="store_true", help="Copy the build to /Applications/RDataCraft.app.")
    args = parser.parse_args()
    if platform.system() != "Darwin":
        raise SystemExit("The native desktop host currently targets macOS.")
    runtime=args.runtime_root.resolve()
    cross=args.arch!=platform.machine()
    if cross and not args.cross_build:
        raise SystemExit("Use --cross-build with a matching --runtime-manifest for a different CPU.")
    target_manifest=None
    if cross:
        if not args.runtime_manifest:raise SystemExit("Cross-builds require the target runtime's dependency manifest.")
        target_manifest=json.loads(args.runtime_manifest.read_text())
        marker='aarch64' if args.arch=='arm64' else 'x86_64'
        if marker not in target_manifest['platform']:raise SystemExit('Dependency manifest CPU does not match the target.')
        descriptions=list((runtime/'library').glob('*/DESCRIPTION'))+list((runtime/'R.framework/Resources/library').glob('*/DESCRIPTION'))
        records={}
        for desc in descriptions:
            fields={line.split(':',1)[0]:line.split(':',1)[1].strip() for line in desc.read_text().splitlines() if ':' in line and not line.startswith((' ','\t'))}
            records[fields.get('Package')]=fields.get('Version')
        if any(records.get(p['package'])!=p['version'] for p in target_manifest['packages']):raise SystemExit('Target package versions differ from the supplied manifest.')
        for binary in list((runtime/'library').rglob('*.so'))+list((runtime/'R.framework/Resources/lib').glob('*.dylib')):
            if args.arch not in subprocess.check_output(['lipo','-archs',str(binary)],text=True).split():raise SystemExit(f'Wrong CPU in {binary}')
        print('Cross-build: target binaries and package versions audited; target execution is NOT tested.',flush=True)
    os.environ["RDATACRAFT_RUNTIME"]=str(runtime)
    if not (runtime / "R.framework").is_dir():
        raise SystemExit("Run scripts/bootstrap.py to install the app-local R runtime first.")
    arches=subprocess.check_output(['lipo','-archs',str(runtime/'R.framework/Resources/bin/exec/R')],text=True).strip().split()
    deployment = "14.0" if args.arch == "arm64" and "arm64" in arches else "13.0"
    if args.arch not in arches and not (args.allow_rosetta and args.arch=='arm64' and 'x86_64' in arches):
        raise SystemExit(f'R architecture {arches} does not match host {args.arch}. Use bootstrap.py --arch {args.arch} --runtime-root runtime-{args.arch}.')
    required = ["R/r_packages.R", "R/r_packages_server.R", "scripts/r_packages_worker.R", "R/advanced_r.R", "R/advanced_r_server.R", "scripts/advanced_r_worker.R", "examples/Advanced R teaching example.rdatacraft", "R/prism_xml.R", "R/prism_convert.R", "R/portable_ai.R", "R/tutorials.R", "R/prism_archive.R", "desktop/RDataCraft.swift", "R/pca.R", "R/assistant.R", "R/assistant_server.R", "www/assistant.js", "desktop/PrismXML.swift", "desktop/PrismDecode.swift",
                "www/rdatacraft.css", "www/craft.css", "examples/xy.csv", "examples/dose-response.csv",
                "examples/Prism workflow improvements.rdatacraft", "examples/Figure studio.rdatacraft",
                "R/graph_options.R", "R/layout_editor.R", "www/layout-editor.js"]
    missing = [name for name in required if not (ROOT / name).is_file()]
    if missing:
        raise SystemExit("Incomplete project copy; missing files: " + ", ".join(missing))
    if not cross:run(ROOT / "scripts/rscript.sh", "scripts/check_runtime.R")
    run("/usr/bin/python3", "scripts/relocate_runtime.py")
    app = args.output.resolve() if args.output else ROOT / "dist" / f"RDataCraft v{VERSION}.app"
    if app.suffix != ".app":
        raise SystemExit("The output path must end in .app.")
    # Rebuild the generated bundle from scratch so removed dependencies cannot linger.
    if app.exists():
        previous = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        if previous.get("CFBundleIdentifier") != "org.rdatacraft.desktop":
            raise SystemExit("Unexpected application in the build destination.")
        shutil.rmtree(app)
    ai_output=build_ai(target=("aarch64-apple-darwin" if args.arch=="arm64" else "x86_64-apple-darwin") if cross else None)
    macos = app / "Contents/MacOS"
    resources = app / "Contents/Resources"
    backend = resources / "RDataCraft"
    macos.mkdir(parents=True, exist_ok=True)
    backend.mkdir(parents=True, exist_ok=True)
    for name in ("app.R", "README.md", "PLATFORM_SUPPORT.md", "WORKFLOWS.md", "RELEASE.md", "LICENSE", "CHANGELOG.md", "dependencies.csv", "dependencies.lock.json", "source-manifest.json"):
        shutil.copy2(ROOT / name, backend / name)
    for name in ("R", "www", "config", "scripts", "tests", "examples", "licenses", "runtime", "desktop"):
        if name == "runtime":
            shutil.copytree(runtime, backend / name, symlinks=True,
                            ignore=shutil.ignore_patterns(".DS_Store", "__pycache__", "*.pyc"))
            continue
        shutil.copytree(ROOT / name, backend / name, symlinks=True, dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns(".git", "__pycache__", "*.pyc", ".DS_Store", "cache", "target", "bin", "obj"))
    shutil.copytree(ai_output, backend/"desktop/ai-helper/bin",dirs_exist_ok=True)
    run("codesign","--force","--sign","-",backend/"desktop/ai-helper/bin/rdatacraft-ai")
    ai_manifest=backend/"desktop/ai-helper/bin/build.json"
    ai_record=json.loads(ai_manifest.read_text())
    for name,digest in ai_record['source_files'].items():
        if hashlib.sha256((backend/'desktop/ai-helper'/name).read_bytes()).hexdigest()!=digest:raise SystemExit('Bundled AI source differs from its build: '+name)
    ai_record['sha256']=hashlib.sha256((backend/"desktop/ai-helper/bin/rdatacraft-ai").read_bytes()).hexdigest()
    ai_record['ad_hoc_signed']=True
    ai_manifest.write_text(json.dumps(ai_record,indent=2)+'\n')
    if (ROOT / "downloads/sources").is_dir():
        shutil.copytree(ROOT / "downloads/sources", backend / "downloads/sources", dirs_exist_ok=True)
    if (ROOT / "downloads/native-sources").is_dir():
        shutil.copytree(ROOT / "downloads/native-sources", backend / "downloads/native-sources")
    if cross:
        shutil.copy2(args.runtime_manifest,backend/'dependencies.lock.json')
        import csv
        with (backend/'dependencies.csv').open('w') as output:
            writer=csv.DictWriter(output,fieldnames=['package','version','license']);writer.writeheader();writer.writerows(target_manifest['packages'])
    else:run(ROOT / "scripts/rscript.sh", "scripts/runtime_manifest.R", backend)
    write_notices(runtime/'R.framework/Resources',runtime/'library',backend/'licenses')
    info = {
        "CFBundleName": "RDataCraft", "CFBundleDisplayName": "RDataCraft", "CFBundleExecutable": "RDataCraft",
        "CFBundleIdentifier": "org.rdatacraft.desktop", "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": VERSION, "CFBundleVersion": str(json.loads((ROOT / "config/release.json").read_text())["build"]), "CFBundleIconFile": "RDataCraft.icns",
        "LSMinimumSystemVersion": deployment, "NSHighResolutionCapable": True,
        "NSPrincipalClass": "NSApplication", "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True},
        "NSHumanReadableCopyright": "Copyright © 2026 RDataCraft contributors. GPL-3.0.",
        "CFBundleDocumentTypes": [{"CFBundleTypeName": "RDataCraft Project", "CFBundleTypeRole": "Editor",
                                   "LSHandlerRank": "Owner", "CFBundleTypeIconFile": "RDataCraftDocument.icns",
                                   "LSItemContentTypes": ["org.rdatacraft.study", "org.rdatacraft.project"]}],
        "UTExportedTypeDeclarations": [{"UTTypeIdentifier": "org.rdatacraft.study", "UTTypeDescription": "RDataCraft Study",
                                         "UTTypeConformsTo": ["public.json"],
                                         "UTTypeTagSpecification": {"public.filename-extension": ["rdcraft"]}},
                                       {"UTTypeIdentifier": "org.rdatacraft.project", "UTTypeDescription": "RDataCraft Study (legacy)",
                                         "UTTypeConformsTo": ["public.json"],
                                         "UTTypeTagSpecification": {"public.filename-extension": ["rdatacraft"]}}],
    }
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
    (backend/'build-platform.json').write_text(json.dumps({'version':VERSION,'platform':'Darwin','architecture':args.arch,'cross_compiled':cross,'target_execution_tested':False,'note':'Consult the accompanying validation report for executed tests.'},indent=2)+'\n')
    module_cache = ROOT / ("artifacts/desktop/module-cache" if args.arch=="arm64" else "artifacts/desktop/module-cache-intel")
    module_cache.mkdir(parents=True, exist_ok=True)
    run("xcrun", "swiftc", "-module-cache-path", module_cache, "-parse-as-library", "-swift-version", "5", "-O", "-target", f"{args.arch}-apple-macosx{deployment}",
        "-framework", "Cocoa", "-framework", "WebKit", "-framework", "PDFKit", ROOT / "desktop/RDataCraft.swift", "-o", macos / "RDataCraft")
    decoder = backend / "desktop/PrismDecode"
    run("xcrun", "swiftc", "-module-cache-path", module_cache, "-parse-as-library", "-swift-version", "5", "-O", "-target", f"{args.arch}-apple-macosx{deployment}",
        ROOT / "desktop/PrismXML.swift", ROOT / "desktop/PrismDecode.swift", "-o", decoder)
    run("codesign", "--force", "--sign", "-", decoder)
    shutil.copy2(decoder, ROOT / "artifacts/desktop/PrismDecode")
    tooling = ROOT / "artifacts/desktop"
    tooling.mkdir(parents=True, exist_ok=True)
    # Generate every build from the artwork; a checked-in .icns may be stale.
    run("xcrun", "swiftc", "-module-cache-path", module_cache, "desktop/MakeIcon.swift", "-o", tooling / "MakeIcon")
    run(tooling / "MakeIcon", tooling / "icon.png")
    iconset = tooling / "RDataCraft.iconset"
    iconset.mkdir(exist_ok=True)
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            suffix = "@2x" if scale == 2 else ""
            run("sips", "-z", size * scale, size * scale, tooling / "icon.png", "--out", iconset / f"icon_{size}x{size}{suffix}.png")
    run("iconutil", "-c", "icns", iconset, "-o", resources / "RDataCraft.icns")
    # The same checked-in artwork is available to Windows packaging as an ICO.
    shutil.copy2(ROOT / "desktop/RDataCraftDocument.icns", resources / "RDataCraftDocument.icns")
    # Finder transfers may leave source directories owner-only. Installed apps
    # must remain readable when copied to Applications by a different account.
    for entry in app.rglob('*'):
        if entry.is_symlink():continue
        entry.chmod(0o755 if entry.is_dir() or entry.stat().st_mode & 0o111 else 0o644)
    run("codesign", "--force", "--sign", "-", macos / "RDataCraft")
    run("codesign", "--force", "--sign", "-", app)
    run("codesign", "--verify", "--strict", app)
    if args.zip:
        archive = ROOT / "dist" / f"RDataCraft-{VERSION}-macos-{args.arch}-desktop-dev.zip"
        run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, archive)
        sha = hashlib.sha256(archive.read_bytes()).hexdigest()
        archive.with_suffix(".zip.sha256").write_text(f"{sha}  {archive.name}\n")
        print(f"Development ZIP: {archive} ({archive.stat().st_size / 1024**2:.1f} MiB)")
    if args.install:
        destination = Path("/Applications/RDataCraft.app")
        if destination.exists():
            current = plistlib.loads((destination / "Contents/Info.plist").read_bytes())
            if current.get("CFBundleIdentifier") != info["CFBundleIdentifier"]:
                raise SystemExit("A different application already uses /Applications/RDataCraft.app.")
        run("ditto", app, destination)
        print("Installed:", destination)
    print("Built:", app)


if __name__ == "__main__":
    main()
