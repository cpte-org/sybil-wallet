#!/usr/bin/env python3
"""Generate the Sybil Dart/Rust dependency license inventory.

The inventory is deliberately derived from the checked-in lock files.  It
records the package's declared SPDX expression, the exact lock source, and
the license files found in the local package cache.  The copied license text
files are kept under ``tools/licensing/licenses`` so the release source tree
retains the text that was inspected; packages without a local text file are
called out instead of being silently assigned a license.

This is a release aid, not a license decision.  Run it from the repository
root after changing pubspec.lock or rust/Cargo.lock.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tomllib
from urllib.parse import unquote, urlparse
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml


ROOT = Path(__file__).resolve().parents[2]
PUB_CACHE = Path.home() / ".pub-cache"
CARGO_CACHE = Path.home() / ".cargo"
OUTPUT = ROOT / "tools/licensing/SYBIL-DEPENDENCY-LICENSES.md"
LICENSE_ROOT = ROOT / "tools/licensing/licenses"
AGGREGATE_OUTPUT = ROOT / "assets/legal/THIRD-PARTY-NOTICES.txt"
ANDROID_NATIVE_NOTICES = ROOT / "tools/licensing/ANDROID-NATIVE-NOTICES.txt"
SIMPLEX_LICENSE_ROOT = ROOT / "tools/licensing/licenses/simplex-haskell"


@dataclass
class Row:
    ecosystem: str
    name: str
    version: str
    source: str
    revision: str
    declared_license: str
    package_path: str
    license_paths: list[str]
    license_hashes: list[str]
    release_exclusion: str | None = None


def portable_path(value: Path | str) -> str:
    """Render a cache or checkout path without publishing a workstation path."""
    if isinstance(value, str):
        if value in {"not found in cache", "SDK package or cache unavailable"}:
            return value
        path = Path(value)
    else:
        path = value
    try:
        return path.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        pass
    for root, variable in ((PUB_CACHE, "$PUB_CACHE"), (CARGO_CACHE, "$CARGO_HOME")):
        try:
            relative = path.resolve().relative_to(root.resolve())
        except ValueError:
            continue
        return f"{variable}/{relative.as_posix()}"
    # Flutter package_config roots are versioned SDK checkouts.  Keep the
    # package's SDK-relative location while avoiding the local fvm username
    # and versioned install path in the public inventory.
    parts = path.resolve().parts
    if "versions" in parts:
        index = parts.index("versions")
        if index + 2 < len(parts) and parts[index + 1]:
            sdk_relative = Path(*parts[index + 2 :])
            return f"$FLUTTER_ROOT/{sdk_relative.as_posix()}" if sdk_relative.parts else "$FLUTTER_ROOT"
    try:
        return f"$HOME/{path.resolve().relative_to(Path.home()).as_posix()}"
    except ValueError:
        return path.as_posix()


def safe_slug(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9._+-]+", "_", value).strip("._") or "package"


def hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def legal_filename(path: Path) -> bool:
    name = path.name.casefold()
    return (
        name == "license"
        or name.startswith("license.")
        or name.startswith("license-")
        or name == "licence"
        or name.startswith("licence.")
        or name.startswith("licence-")
        or name.startswith("copying")
        or name.startswith("notice")
    )


def find_license_files(package: Path, inherit_ancestors: bool = False) -> list[Path]:
    if not package.exists():
        return []
    found: list[Path] = []
    for path in package.rglob("*"):
        if not path.is_file() or any(part.startswith(".") for part in path.relative_to(package).parts):
            continue
        if not legal_filename(path):
            continue
        try:
            if path.stat().st_size > 2 * 1024 * 1024:
                continue
        except OSError:
            continue
        found.append(path)
    if found or not inherit_ancestors:
        return sorted(found)
    # Flutter SDK package roots such as flutter_test inherit the SDK's root
    # license. Keep the exact SDK path in the inventory rather than guessing a
    # license expression for the package itself.
    ancestor = package.parent
    for _ in range(6):
        if ancestor == ancestor.parent:
            break
        inherited = [
            path
            for path in ancestor.iterdir()
            if path.is_file() and legal_filename(path) and path.stat().st_size <= 2 * 1024 * 1024
        ]
        if inherited:
            return sorted(inherited)
        ancestor = ancestor.parent
    return []


def yaml_license(package: Path) -> str:
    path = package / "pubspec.yaml"
    if not path.is_file():
        return "not declared (no pubspec.yaml)"
    try:
        value = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except (OSError, UnicodeError, yaml.YAMLError) as error:
        return f"unreadable pubspec ({error.__class__.__name__})"
    license_value = value.get("license")
    if license_value:
        return str(license_value).replace("\n", " ")
    return "not declared in pubspec.yaml"


def load_dart_package_config() -> dict[str, Path]:
    """Resolve package roots exactly as Dart does for this checkout."""
    path = ROOT / ".dart_tool/package_config.json"
    if not path.is_file():
        return {}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        return {}
    roots: dict[str, Path] = {}
    for package in value.get("packages", []):
        name = package.get("name")
        uri = package.get("rootUri")
        if not name or not uri:
            continue
        parsed = urlparse(uri)
        if parsed.scheme == "file":
            root = Path(unquote(parsed.path))
        else:
            root = (path.parent / uri).resolve()
        roots[str(name)] = root.resolve()
    return roots


def git_head(package: Path) -> str | None:
    if not (package / ".git").exists():
        return None
    result = subprocess.run(
        ["git", "-C", str(package), "rev-parse", "HEAD"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return None
    return result.stdout.strip()


def cargo_license(package: Path) -> str:
    path = package / "Cargo.toml"
    if not path.is_file():
        return "not declared (no Cargo.toml)"
    try:
        import tomllib

        value = tomllib.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError):
        return "unreadable Cargo.toml"
    package_table = value.get("package", {})
    license_value = package_table.get("license")
    license_file = package_table.get("license-file")
    if license_value:
        return str(license_value).replace("\n", " ")
    if license_file:
        return f"license-file: {license_file}"
    return "not declared in Cargo.toml"


def copy_license_texts(ecosystem: str, name: str, version: str, package: Path, files: list[Path]) -> tuple[list[str], list[str]]:
    copied: list[str] = []
    hashes: list[str] = []
    destination = LICENSE_ROOT / ecosystem / safe_slug(f"{name}-{version}")
    for source in files:
        try:
            relative = source.relative_to(package)
        except ValueError:
            relative = Path("INHERITED") / source.name
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        copied.append(target.relative_to(ROOT).as_posix())
        hashes.append(f"{target.relative_to(ROOT).as_posix()} sha256:{hash_file(source)}")
    return copied, hashes


def hosted_pub_package(name: str, version: str) -> Path | None:
    candidate = PUB_CACHE / "hosted/pub.dev" / f"{name}-{version}"
    if candidate.is_dir():
        return candidate
    for path in sorted((PUB_CACHE / "hosted/pub.dev").glob(f"{name}-*")):
        if not path.is_dir():
            continue
        try:
            value = yaml.safe_load((path / "pubspec.yaml").read_text(encoding="utf-8")) or {}
            if str(value.get("version", "")) == version:
                return path
        except (OSError, UnicodeError, yaml.YAMLError):
            continue
    return None


def git_pub_package(name: str, description: dict[str, Any], configured: Path | None) -> Path | None:
    resolved = str(description.get("resolved-ref", ""))
    if configured is not None and git_head(configured) == resolved:
        return configured
    cache = PUB_CACHE / "git"
    candidate = cache / f"{name}-{resolved}"
    if candidate.is_dir() and git_head(candidate) == resolved:
        return candidate
    for path in sorted(cache.glob(f"{name}-*")):
        if path.is_dir() and git_head(path) == resolved:
            return path
    return None


def pub_rows() -> list[Row]:
    lock_path = ROOT / "pubspec.lock"
    lock = yaml.safe_load(lock_path.read_text(encoding="utf-8")) or {}
    package_config = load_dart_package_config()
    rows: list[Row] = []
    for name, entry in sorted((lock.get("packages") or {}).items()):
        raw_description = entry.get("description") or {}
        description = raw_description if isinstance(raw_description, dict) else {}
        source = str(entry.get("source", "unknown"))
        version = str(entry.get("version", ""))
        revision = ""
        package: Path | None = None
        configured = package_config.get(name)
        if source == "hosted":
            package = configured if configured and configured.is_dir() else hosted_pub_package(name, version)
            revision = str(description.get("sha256", ""))
        elif source == "git":
            package = git_pub_package(name, description, configured)
            revision = str(description.get("resolved-ref", ""))
        elif source == "path":
            package = configured if configured and configured.is_dir() else None
            if package is None:
                relative = description.get("path") or "."
                package = (ROOT / str(relative)).resolve()
            revision = str(description.get("relative", ""))
        else:
            package = configured if configured and configured.is_dir() else None
            revision = str(raw_description)
        files = find_license_files(package, source == "sdk") if package else []
        copied, hashes = copy_license_texts(
            "dart", name, version, package, files
        ) if package else ([], [])
        rows.append(
            Row(
                ecosystem="Dart",
                name=name,
                version=version,
                source=source,
                revision=revision,
                declared_license=yaml_license(package) if package else "SDK package or cache unavailable",
                package_path=portable_path(package) if package else "not found in cache",
                license_paths=copied,
                license_hashes=hashes,
            )
        )
    return rows


def cargo_rows() -> list[Row]:
    supplement_file = ROOT / "tools/licensing/rust-source-notices.json"
    supplements = {
        (r["name"], r["version"], r["source"]): r
        for r in json.loads(supplement_file.read_text())
    } if supplement_file.is_file() else {}
    command = [
        "cargo",
        "metadata",
        "--locked",
        "--offline",
        "--format-version=1",
        "--manifest-path",
        str(ROOT / "rust/Cargo.toml"),
    ]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "cargo metadata failed")
    metadata = json.loads(result.stdout)
    lock = tomllib.loads((ROOT / "rust/Cargo.lock").read_text())
    lock_checksums = {
        (p["name"], p["version"], p.get("source", "path")): p.get("checksum", "")
        for p in lock.get("package", [])
    }
    rows: list[Row] = []
    for package_data in sorted(metadata.get("packages", []), key=lambda item: (item["name"], item["version"], item.get("source") or "")):
        package = Path(package_data["manifest_path"]).parent
        source = str(package_data.get("source") or "path")
        revision = ""
        if source.startswith("git+"):
            revision = source.rsplit("#", 1)[-1]
        elif source.startswith("registry+"):
            revision = lock_checksums.get((package_data["name"], package_data["version"], source), "")
        files = find_license_files(package)
        copied, hashes = copy_license_texts(
            "rust", package_data["name"], package_data["version"], package, files
        )
        evidence = supplements.get((package_data["name"], package_data["version"], source))
        release_exclusion = None
        if not copied and evidence:
            for text in evidence.get("texts", []):
                relative = text["path"]
                retained = (ROOT / relative).resolve()
                if not retained.is_relative_to(LICENSE_ROOT.resolve()):
                    raise ValueError("Supplement text is outside the retained license directory")
                if hash_file(retained) != text["sha256"]:
                    raise ValueError(f"Supplement license hash mismatch: {relative}")
                copied.append(relative)
                hashes.append(f"{relative} sha256:{text['sha256']}")
            if not copied and not any(evidence.get("target_normal_or_build", {}).values()):
                release_exclusion = "Outside Linux and Android normal/build dependency closures"
        rows.append(
            Row(
                ecosystem="Rust",
                name=package_data["name"],
                version=package_data["version"],
                source=source,
                revision=revision,
                release_exclusion=release_exclusion,
                declared_license=package_data.get("license") or cargo_license(package),
                package_path=portable_path(package),
                license_paths=copied,
                license_hashes=hashes,
            )
        )
    return rows


def markdown_cell(value: str) -> str:
    return value.replace("|", "\\|").replace("\n", " ")


def render(rows: list[Row]) -> str:
    dart = [row for row in rows if row.ecosystem == "Dart"]
    rust = [row for row in rows if row.ecosystem == "Rust"]
    missing = [row for row in rows if not row.license_paths]
    copied = sum(len(row.license_paths) for row in rows)
    lines = [
        "# Sybil dependency license inventory",
        "",
        "This file is generated by `tools/licensing/generate_dependency_inventory.py`",
        "from the checked-in `pubspec.lock` and `rust/Cargo.lock` resolution. It is a",
        "release inventory and source pointer; it does not grant a license or replace",
        "the copyright and license terms shipped with each component.",
        "",
        f"- Dart lock packages: {len(dart)}",
        f"- Rust lock packages: {len(rust)}",
        f"- Copied package license/notice files: {copied}",
        f"- Lock entries without retained text: {len(missing)} (target exclusions are identified below)",
        "- Copied texts: `tools/licensing/licenses/dart/` and `tools/licensing/licenses/rust/`",
        "- SimpleX Haskell/native dependency texts: `tools/licensing/licenses/simplex-haskell/`",
        "",
        "The Dart rows are the lockfile superset and include dev, test, SDK, and",
        "platform packages; Rust rows are the locked metadata superset. A release",
        "target must filter this inventory to the packages actually shipped.",
        "",
        "The copied files are byte-for-byte cache copies. A row marked as missing",
        "retains the package's declared SPDX expression when available, but the local",
        "cache did not contain a license/notice text under a conventional filename.",
        "Exact-source supplements and their hashes are recorded in rust-source-notices.json.",
        ("All remaining missing-text entries have explicit target exclusions."
         if missing and all(row.release_exclusion for row in missing)
         else "Any entry without retained text or a target exclusion needs review before release."),
        "",
    ]
    for ecosystem, subset in (("Dart", dart), ("Rust", rust)):
        lines.extend([
            f"## {ecosystem} packages",
            "",
            "| Package | Version | Lock source/revision | Declared license | Retained text |",
            "| --- | --- | --- | --- | --- |",
        ])
        for row in subset:
            source = f"{row.source} {row.revision}".strip()
            text = "<br>".join(f"`{path}`" for path in row.license_paths) or row.release_exclusion or "**missing in inspected cache**"
            lines.append(
                f"| `{markdown_cell(row.name)}` | `{markdown_cell(row.version)}` | "
                f"`{markdown_cell(source)}` | `{markdown_cell(row.declared_license)}` | {text} |"
            )
        lines.append("")
    lines.extend([
        "## Missing local texts",
        "",
        "These rows are intentionally explicit. They are not assertions that the",
        "packages are unlicensed; they identify packages for which this cache-backed",
        "run could not retain a conventional license/notice file.",
        "",
        "| Ecosystem | Package | Version | Declared license | Cache path |",
        "| --- | --- | --- | --- | --- |",
    ])
    for row in missing:
        lines.append(
            f"| {row.ecosystem} | `{markdown_cell(row.name)}` | `{markdown_cell(row.version)}` | "
            f"`{markdown_cell(row.declared_license)}` | `{markdown_cell(row.release_exclusion or row.package_path)}` |"
        )
    lines.extend([
        "",
        "## Scope notes",
        "",
        "Dart SDK and Flutter SDK rows come from the SDK source in `pubspec.lock`; their",
        "license text is supplied by the SDK distribution rather than this repository's",
        "pub cache. Rust registry rows preserve the Cargo.lock checksum and the package",
        "manifest's license expression. Native libraries and the SimpleX Haskell",
        "dependency set are inventoried separately in the corresponding-source package",
        "and `tools/simplex/licenses/SIMPLEX-SOURCE-AND-BUILD.txt`.",
        "",
    ])
    return "\n".join(lines)


def render_aggregate(rows: list[Row]) -> bytes:
    """Combine retained texts into one readable runtime legal-notice asset."""
    chunks: list[bytes] = [
        b"Sybil wallet third-party dependency license texts\n",
        b"================================================\n\n",
        b"This file is generated from pubspec.lock, rust/Cargo.lock, and the\n",
        b"local package caches. Each section retains the copied license or notice\n",
        b"text for one resolved package. The package inventory records rows for\n",
        b"which the inspected cache had no conventional local text.\n\n",
    ]
    for row in rows:
        for path in row.license_paths:
            relative = path.removeprefix("tools/licensing/licenses/")
            header = (
                "\n\n----------------------------------------------------------------\n"
                f"{row.ecosystem} package: {row.name} {row.version}\n"
                f"Declared license: {row.declared_license}\n"
                f"Lock source/revision: {row.source} {row.revision}\n"
                f"Retained path: {path}\n"
                f"Text path: {relative}\n"
                "----------------------------------------------------------------\n\n"
            )
            chunks.append(header.encode("utf-8"))
            chunks.append((ROOT / path).read_bytes())
            if not chunks[-1].endswith(b"\n"):
                chunks.append(b"\n")
    if ANDROID_NATIVE_NOTICES.is_file():
        chunks.extend(
            [
                b"\n\n----------------------------------------------------------------\n",
                b"Android native dependency notice supplement\n",
                b"Retained path: tools/licensing/ANDROID-NATIVE-NOTICES.txt\n",
                b"----------------------------------------------------------------\n\n",
                ANDROID_NATIVE_NOTICES.read_bytes(),
            ]
        )
    if SIMPLEX_LICENSE_ROOT.is_dir():
        for path in sorted(p for p in SIMPLEX_LICENSE_ROOT.rglob("*") if p.is_file()):
            relative = path.relative_to(ROOT).as_posix()
            chunks.extend(
                [
                    b"\n\n----------------------------------------------------------------\n",
                    b"SimpleX Haskell/native dependency notice\n",
                    f"Retained path: {relative}\n".encode("utf-8"),
                    b"----------------------------------------------------------------\n\n",
                    path.read_bytes(),
                ]
            )
    return b"".join(chunks)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    LICENSE_ROOT.mkdir(parents=True, exist_ok=True)
    rows = pub_rows() + cargo_rows()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(render(rows), encoding="utf-8")
    AGGREGATE_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    AGGREGATE_OUTPUT.write_bytes(render_aggregate(rows))
    print(f"wrote {args.output} ({len(rows)} packages)")
    print(f"wrote {AGGREGATE_OUTPUT} ({AGGREGATE_OUTPUT.stat().st_size} bytes)")
    print(f"retained license files: {sum(len(row.license_paths) for row in rows)}")
    print(f"missing local license texts: {sum(not row.license_paths for row in rows)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
