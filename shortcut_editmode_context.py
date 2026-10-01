#!/usr/bin/env python3
"""Export Apple's edit-mode Python with self-contained catalog references."""

import ast
import base64
import binascii
import json
import os
from pathlib import Path
import pprint
import re
import subprocess
import sys
import tempfile


class ExportError(Exception):
    pass


def referenced_tags(source: str) -> list[str]:
    try:
        tree = ast.parse(source)
    except SyntaxError as error:
        raise ExportError(f"Apple emitted invalid Python: {error}") from error
    tags: list[str] = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Name):
            continue
        if node.func.id != "ref":
            continue
        if len(node.args) != 1 or node.keywords or not isinstance(node.args[0], ast.Constant):
            raise ExportError("Apple emitted an unsupported ref() call")
        literal = ast.get_source_segment(source, node.args[0])
        if literal is None or re.fullmatch(r"0x[0-9A-Fa-f]{4}", literal) is None:
            raise ExportError("Apple emitted a ref() tag outside the four-digit hex format")
        tag = f"0x{node.args[0].value:04X}"
        if tag not in tags:
            tags.append(tag)
    return tags


def plist_value(value):
    if isinstance(value, dict):
        if set(value) == {"__base64Data"}:
            try:
                return base64.b64decode(value["__base64Data"], validate=True)
            except (ValueError, TypeError, binascii.Error) as error:
                raise ExportError(f"Invalid catalog data: {error}") from error
        if set(value) == {"__date"}:
            raise ExportError("Catalog NSDate values have no supported ref literal")
        return {key: plist_value(item) for key, item in value.items()}
    if isinstance(value, list):
        return [plist_value(item) for item in value]
    return value


def render_python(payload: dict) -> str:
    source = payload.get("python_code")
    if not isinstance(source, str):
        raise ExportError("Native helper returned no Python code")
    tags = referenced_tags(source)
    if not tags:
        return source
    catalog = payload.get("catalog")
    if not isinstance(catalog, dict):
        raise ExportError("Python contains ref() but native catalog is unavailable")
    lines = [source.rstrip(), "", "", "def ref(tag: int, /) -> CatalogRef:", "    match tag:"]
    for tag in tags:
        entry = catalog.get(tag)
        if not isinstance(entry, dict):
            raise ExportError(f"Native catalog has no entry for {tag}")
        if "parameterStateObject" in entry:
            value = entry["parameterStateObject"]
        elif isinstance(entry.get("modelDescription"), str):
            try:
                value = json.loads(entry["modelDescription"])
            except json.JSONDecodeError as error:
                raise ExportError(f"Catalog {tag} modelDescription is invalid: {error}") from error
        else:
            raise ExportError(f"Catalog {tag} has no representable parameter state")
        literal = pprint.pformat(plist_value(value), width=76, sort_dicts=False).splitlines()
        lines.append(f"        case {tag}:")
        prefix = "            return "
        lines.append(prefix + literal[0])
        lines.extend(" " * len(prefix) + line for line in literal[1:])
    return "\n".join(lines) + "\n"


def export(input_path: Path, output_path: Path) -> None:
    if input_path.resolve() == output_path.resolve():
        raise ExportError("Input and output paths must differ")
    helper = Path(__file__).resolve().parent / ".build" / "editmode-native"
    if not helper.is_file():
        raise ExportError("Native helper is not built; run make first")
    completed = subprocess.run(
        [str(helper), str(input_path)], capture_output=True, text=True, check=False
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or f"exit status {completed.returncode}"
        raise ExportError(f"Native editModeContext export failed: {detail}")
    try:
        payload = json.loads(completed.stdout)
        source = render_python(payload)
    except json.JSONDecodeError as error:
        raise ExportError(f"Native helper returned invalid JSON: {error}") from error
    missing = payload.get("missing_action_identifiers", [])
    if missing:
        print("Warning: WorkflowKit imported unresolved actions: " + ", ".join(missing),
              file=sys.stderr)
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=output_path.parent, prefix=".editmode-",
        suffix=".tmp", delete=False
    ) as temporary:
        temporary.write(source)
        staged = Path(temporary.name)
    try:
        os.replace(staged, output_path)
    finally:
        staged.unlink(missing_ok=True)


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: shortcut-editmode-context INPUT.plist OUTPUT.py", file=sys.stderr)
        return 2
    try:
        export(Path(sys.argv[1]), Path(sys.argv[2]))
    except (ExportError, OSError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
