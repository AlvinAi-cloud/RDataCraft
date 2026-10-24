"""Make the official R shell launcher resolve its app-local framework.

RDataCraft modifications: make shell paths and fontconfig links relocatable.
Bundled Mach-O binaries are preserved.
"""
from pathlib import Path
import os

root = Path(__file__).resolve().parent.parent
runtime = Path(os.environ.get("RDATACRAFT_RUNTIME", root / "runtime"))
launcher = runtime / "R.framework/Resources/bin/R"
original = launcher.read_text()
modified = original.replace(
    'R_HOME_DIR="/Library/Frameworks/R.framework/Resources"',
    'R_HOME_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"', 1
)
for variable, suffix in [("R_SHARE_DIR", "share"), ("R_INCLUDE_DIR", "include"), ("R_DOC_DIR", "doc")]:
    modified = modified.replace(f'{variable}="/Library/Frameworks/R.framework/Resources/{suffix}"',
                                f'{variable}="${{R_HOME_DIR}}/{suffix}"')
launcher.write_text(modified)
framework = runtime / "R.framework"
prefix = "/Library/Frameworks/R.framework/"
repaired = 0
for link in framework.rglob("*"):
    if link.is_symlink():
        target = str(link.readlink())
        if target.startswith(prefix):
            local = framework / target[len(prefix):]
            if not local.exists():
                raise SystemExit("Cannot relocate missing framework target: " + target)
            relative = os.path.relpath(local, link.parent)
            link.unlink()
            link.symlink_to(relative)
            repaired += 1
print(f"R launcher uses its bundled framework; repaired {repaired} absolute framework links.")
