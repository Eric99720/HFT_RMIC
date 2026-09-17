#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
vivado_dir = root / "vivado"

errors = []
for p in sorted(vivado_dir.glob("*.tcl")):
    lines = p.read_text(encoding="utf-8").splitlines()
    for lineno, raw in enumerate(lines, start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "read_verilog" in line and "-include_dirs" in line:
            errors.append(f"{p.name}:{lineno}: unsupported read_verilog -include_dirs found")

required_in_memory = [
    vivado_dir / "i2_ooc_impl.tcl",
    vivado_dir / "i3_cl2ex_ooc_impl.tcl",
    vivado_dir / "i4_r01_path_ooc_impl.tcl",
]
for p in required_in_memory:
    if not p.exists():
        errors.append(f"missing required OOC Tcl: {p.name}")
        continue
    text = p.read_text(encoding="utf-8")
    if "create_project -in_memory" not in text:
        errors.append(f"{p.name}: expected create_project -in_memory flow missing")
    if "set_property include_dirs" not in text:
        errors.append(f"{p.name}: expected fileset include_dirs property missing")
    if "auto_detect_xpm" not in text:
        errors.append(f"{p.name}: XPM auto-detection missing")

if errors:
    print("VIVADO_2022_TCL_CHECK_FAIL")
    for e in errors:
        print(e)
    raise SystemExit(1)

print("VIVADO_2022_TCL_CHECK_PASS")
