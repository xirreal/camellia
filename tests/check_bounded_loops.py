"""Fail if shader sources reintroduce syntactically unbounded loops."""

import re
from pathlib import Path


ROOT = Path(__file__).parents[1] / "shaders"
SHADER_SUFFIXES = {".csh", ".fsh", ".gsh", ".glsl", ".vsh"}
UNBOUNDED_LOOP = re.compile(r"\bwhile\s*\(|\bdo\s*\{|\bfor\s*\(\s*;\s*;\s*\)")


def test_shader_loops_are_bounded() -> None:
    offenders = []
    for path in sorted(ROOT.rglob("*")):
        if path.suffix in SHADER_SUFFIXES:
            for line_number, line in enumerate(path.read_text().splitlines(), 1):
                if UNBOUNDED_LOOP.search(line):
                    offenders.append(f"{path}:{line_number}: {line.strip()}")
    assert not offenders, "Unbounded shader loop(s):\n" + "\n".join(offenders)


if __name__ == "__main__":
    test_shader_loops_are_bounded()
    print("PASS: shader loops are bounded")
