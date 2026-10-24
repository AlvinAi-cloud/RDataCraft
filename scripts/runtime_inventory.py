"""Inventory every shipped non-base R package, including recommended packages."""
import csv
import json
from pathlib import Path
import shutil


def dcf(path):
    fields = {}
    key = None
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith((" ", "\t")) and key:
            fields[key] += "\n" + line.strip()
        elif ":" in line:
            key, value = line.split(":", 1)
            fields[key] = value.strip()
    return fields


def packages(home, library):
    records = {}
    for folder in [home / "library", library]:
        for desc in sorted(folder.glob("*/DESCRIPTION")):
            fields = dcf(desc)
            if fields.get("Priority") != "base" and not fields.get("License", "").startswith("Part of R "):
                records[fields["Package"]] = (fields, desc.parent)
    return records


def manifest(home, library, platform):
    return dict(r_version=dcf(home / "library/base/DESCRIPTION")["Version"],
                platform=platform, packages=[
                    dict(package=name, version=fields["Version"], license=fields["License"])
                    for name, (fields, _) in sorted(packages(home, library).items())])


def write_notices(home, library, destination):
    records = packages(home, library)
    for name, (_, source) in records.items():
        for file in source.rglob("*"):
            if file.is_file() and (file.name == "DESCRIPTION" or file.name.lower().startswith(
                    ("license", "licence", "copying", "copyright", "notice"))):
                target = destination / "packages" / name / file.relative_to(source)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(file, target)
    with (destination / "THIRD_PARTY.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=["package", "version", "license", "author"])
        writer.writeheader()
        for name, (fields, _) in sorted(records.items()):
            writer.writerow(dict(package=name, version=fields["Version"], license=fields["License"],
                                 author=fields.get("Author", "See DESCRIPTION")))
    return len(records)
