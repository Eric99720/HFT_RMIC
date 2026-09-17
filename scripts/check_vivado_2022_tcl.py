#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
vivado_dir = root / "vivado"

errors = []
for p in sorted(vivado_dir.glob("*.tcl")):
    text = p.read_text(encoding="utf-8")
    if "read_verilog -sv -include_dirs" in text or "read_verilog -include_dirs" in text:
        errors.append(f"{p.name}: unsupported read_verilog -include_dirs found")

required_in_memory = [
    vivado_dir / "i2_ooc_impl.tcl",
    vivado_dir / "i3_cl2ex_ooc_impl.tcl",
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
