#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "vivado" / "i2_ooc_impl.tcl"
text = p.read_text(encoding="utf-8")
if "read_verilog -sv -include_dirs" in text:
    raise SystemExit("VIVADO_2022_TCL_CHECK_FAIL: unsupported read_verilog -include_dirs found")
if "create_project -in_memory" not in text or "set_property include_dirs" not in text:
    raise SystemExit("VIVADO_2022_TCL_CHECK_FAIL: expected in-memory fileset include-dir flow missing")
print("VIVADO_2022_TCL_CHECK_PASS")
