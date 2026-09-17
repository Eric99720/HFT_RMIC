from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

EXPECTED = {
    ROOT / "deps" / "hft-full-system-fpga": "50217fad1fd580f8c451ba893f9035f4be1dc21a",
    ROOT / "deps" / "RMIC": "de6c300f4f18b18296f013287ab0eca70d3abb72",
}


def git_head(path: Path) -> str:
    return subprocess.check_output(
        ["git", "-C", str(path), "rev-parse", "HEAD"],
        text=True,
    ).strip()


def require_text(path: Path, needles: list[str]) -> None:
    text = path.read_text(encoding="utf-8")
    missing = [needle for needle in needles if needle not in text]
    if missing:
        raise AssertionError(f"{path}: missing expected contract text: {missing}")


def main() -> int:
    for path, expected_sha in EXPECTED.items():
        if not path.exists():
            raise AssertionError(
                f"missing dependency {path}; run git submodule update --init --recursive"
            )
        actual = git_head(path)
        if actual != expected_sha:
            raise AssertionError(
                f"dependency SHA mismatch for {path}: expected {expected_sha}, got {actual}"
            )

    hft_defs = ROOT / "deps" / "hft-full-system-fpga" / "rtl" / "common" / "include" / "round_chip_defs.vh"
    hft_packer = ROOT / "deps" / "hft-full-system-fpga" / "rtl" / "bridge" / "hft_order_data_packer.v"
    rmic_defs = ROOT / "deps" / "RMIC" / "rtl" / "rmic_defs.svh"

    require_text(
        hft_defs,
        [
            "`define RC_ORDER_PRICE_LSB       0",
            "`define RC_ORDER_QTY_LSB         32",
            "`define RC_ORDER_SIDE_LSB        48",
            "`define RC_ORDER_TIF_LSB         56",
            "`define RC_ORDER_POS_EFFECT_LSB  64",
            "`define RC_ORDER_INV_FLAG_LSB    72",
            "`define RC_ORDER_INV_ACNO_LSB    80",
            "`define RC_ORDER_ID_LSB          112",
            "`define RC_ORDER_NO_LSB          144",
            "`define RC_ORDER_SYMBOL_SLOT_LSB 184",
            "`define RC_ORDER_FLAGS_LSB       200",
            "`define RC_ORDER_ORD_TYPE_LSB    208",
        ],
    )
    require_text(
        hft_packer,
        [
            "parameter [7:0] TMP_SIDE_BUY=8'h01, TMP_SIDE_SELL=8'h02",
            "packed_data[`RC_ORDER_QTY_LSB +:16]=qty[15:0]",
        ],
    )
    require_text(
        rmic_defs,
        [
            "`define RMIC_SIDE_BUY   1'b0",
            "`define RMIC_SIDE_SELL  1'b1",
            "`define RMIC_EXEC_FILL    2'd0",
            "`define RMIC_EXEC_CANCEL  2'd1",
            "`define RMIC_EXEC_REJECT  2'd2",
        ],
    )

    print("HFT_RMIC_DEPENDENCY_CONTRACT_PASS")
    for path, sha in EXPECTED.items():
        print(f"{path.relative_to(ROOT)}={sha}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001 - CLI validation should fail closed
        print(f"HFT_RMIC_DEPENDENCY_CONTRACT_FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
