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
        # Tcl's elseif/else are part of the same 'if' command.  A new line
        # beginning with elseif/else after the previous command has already
        # closed is parsed as a new command ("invalid command name elseif").
        # Keep this mechanical guard because Vivado batch flows otherwise fail
        # before synthesis and the old compatibility checker did not catch it.
        if line.startswith("elseif ") or line.startswith("elseif{") or line == "elseif":
            errors.append(f"{p.name}:{lineno}: standalone Tcl elseif command found")
        if line.startswith("else ") or line.startswith("else{") or line == "else":
            errors.append(f"{p.name}:{lineno}: standalone Tcl else command found")

required_in_memory = [
    vivado_dir / "i2_ooc_impl.tcl",
    vivado_dir / "i3_cl2ex_ooc_impl.tcl",
    vivado_dir / "i4_r01_path_ooc_impl.tcl",
    vivado_dir / "i5_dual_xgmii_full_system_ooc.tcl",
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


# I4 local XSim must use behavioral RAM fallbacks because direct xvlog/xelab
# does not automatically link Vivado XPM simulation libraries. Physical OOC,
# however, must keep real XPM block RAM.
parity_runner = root / "scripts" / "run_i4_r01_parity_xsim.ps1"
if not parity_runner.exists():
    errors.append("missing I4 parity runner")
else:
    parity_text = parity_runner.read_text(encoding="utf-8")
    for macro in ("AMU_BEHAVIORAL_RAM", "HFT_RMIC_BEHAVIORAL_RAM"):
        if macro not in parity_text:
            errors.append(f"run_i4_r01_parity_xsim.ps1: missing {macro} define")

i4_ooc = vivado_dir / "i4_r01_path_ooc_impl.tcl"
if i4_ooc.exists():
    i4_ooc_text = i4_ooc.read_text(encoding="utf-8")
    for macro in ("AMU_BEHAVIORAL_RAM", "HFT_RMIC_BEHAVIORAL_RAM"):
        if macro in i4_ooc_text:
            errors.append(f"i4_r01_path_ooc_impl.tcl: physical OOC must not define {macro}")


# I5 functional simulation deliberately uses behavioral RAM fallbacks, while
# the I5 physical OOC must use real XPM RAM.
i5_xsim = vivado_dir / "i5_dual_xgmii_full_system_xsim.tcl"
if not i5_xsim.exists():
    errors.append("missing I5 dual-XGMII XSim Tcl")
else:
    text = i5_xsim.read_text(encoding="utf-8")
    for macro in ("AMU_BEHAVIORAL_RAM", "HFT_RMIC_BEHAVIORAL_RAM"):
        if macro not in text:
            errors.append(f"i5_dual_xgmii_full_system_xsim.tcl: missing {macro}")

i5_ooc = vivado_dir / "i5_dual_xgmii_full_system_ooc.tcl"
if i5_ooc.exists():
    text = i5_ooc.read_text(encoding="utf-8")
    for macro in ("AMU_BEHAVIORAL_RAM", "HFT_RMIC_BEHAVIORAL_RAM"):
        if macro in text:
            errors.append(f"i5_dual_xgmii_full_system_ooc.tcl: physical OOC must not define {macro}")
    for token in (
        "place_design -directive AltSpreadLogic_high",
        "phys_opt_design -directive AggressiveExplore",
        "route_design -directive AlternateCLBRouting",
        "HFT_RMIC_I5_PRE_POSTROUTE_WNS",
    ):
        if token not in text:
            errors.append(f"i5_dual_xgmii_full_system_ooc.tcl: missing congestion/timing-closure token: {token}")

if errors:
    print("VIVADO_2022_TCL_CHECK_FAIL")
    for e in errors:
        print(e)
    raise SystemExit(1)

print("VIVADO_2022_TCL_CHECK_PASS")
