#!/usr/bin/env python3
"""Render the golden path's skeleton the way Backstage's fetch:template does (for the values it uses), so CI can check
the repository a developer would get: no placeholders left, valid YAML, kustomize builds, workflows pass actionlint.

    python3 render_test.py OUTPUT_DIR
"""
import re
import shutil
import sys
from fnmatch import fnmatch
from pathlib import Path

import yaml

HERE = Path(__file__).resolve().parent
VALUES = {"name": "orders-api", "description": "Orders for ITL Pay merchants", "owner": "group:payments",
          "cloud": "gcp", "repoOwner": "itlearning"}
COPY_AS_IS = yaml.safe_load((HERE / "template.yaml").read_text())["spec"]["steps"][0]["input"]["copyWithoutTemplating"]
PLACEHOLDER = re.compile(r"\$\{\{\s*values\.(\w+)\s*(?:\|\s*replace\(\"([^\"]*)\",\s*\"([^\"]*)\"\))?\s*\}\}")


def render(text: str) -> str:
    def sub(m):
        value = VALUES[m.group(1)]
        return value.replace(m.group(2), m.group(3)) if m.group(2) is not None else value
    return PLACEHOLDER.sub(sub, text)


def main(out: Path) -> int:
    if out.exists():
        shutil.rmtree(out)
    skeleton = HERE / "skeleton"
    for src in skeleton.rglob("*"):
        if src.is_dir():
            continue
        rel = src.relative_to(skeleton).as_posix()
        dst = out / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        text = src.read_text()
        if any(fnmatch(rel, pattern) for pattern in COPY_AS_IS):
            assert "${{ values." not in text, f"{rel} is copied without templating but uses values"
            dst.write_text(text)
            continue
        rendered = render(text)
        assert "${{" not in rendered, f"{rel}: a placeholder wasn't filled in"
        dst.write_text(rendered)
        if rel.endswith((".yaml", ".yml")):
            list(yaml.safe_load_all(rendered))   # valid YAML
    catalog = yaml.safe_load((out / "catalog-info.yaml").read_text())
    assert catalog["metadata"]["name"] == VALUES["name"] and catalog["spec"]["owner"] == VALUES["owner"]
    print(f"rendered {sum(1 for p in out.rglob('*') if p.is_file())} files into {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1])))
