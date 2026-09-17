# Repository placement and cleanup policy

Use this policy whenever creating, moving, renaming, consolidating or removing project files. Run `python -B scripts/check_repository_layout.py` before handoff.

## Canonical placement

| Content | Location | Rule |
|---|---|---|
| Agent/project rules | `AGENTS.md` | Repository-wide behavioral and evidence boundaries. |
| Shared current state | `docs/project_state.json` | Authored source for generated current summaries. |
| Human current handoff | `CURRENT_PHASE.md` | Generated current block plus authored operational detail only. |
| Task/progress/decision/change ledgers | root `TASKS.md`, `PROGRESS.md`, `DECISIONS.md`, `CHANGELOG.md` | Each owns one role; do not duplicate current state. |
| Phase plan format | `PLANS.md` | Template/rules only. |
| Living phase plans | `docs/exec_plans/YYYY-MM-DD-<phase>.md` | One plan per coherent substantial phase. |
| Architecture/integration contracts | `docs/` | Durable designs, interfaces, gap analyses and protocol contracts. Index in `docs/README.md`. |
| Integration-owned RTL | `rtl/adapters/`, `rtl/policy/`, `rtl/accounting/`, `rtl/integration/`, `rtl/include/` | Never place integration changes inside `deps/`. |
| Testbenches | `tb/` | Self-checking benches for integration-owned behavior. |
| Runnable orchestration | `scripts/` | PowerShell/Bash/Python entry points and checks. |
| Frozen external sources | `deps/` | Git submodules only; read-only and exact pinned SHAs. |
| Reviewed compact results | `results/` or durable `docs/results/` if created by decision | Small summaries with provenance only. |
| Local raw output | ignored `build/`, `reports/`, `sim/`, `waves/` | Vivado products, logs, waveforms, packet captures, raw measurements. Never commit by default. |

## Before adding a file

1. Identify the existing owner first.
2. Use stable descriptive names; avoid `copy`, `final2`, `new_new`, or manual backup suffixes.
3. Put generated output under ignored directories, not beside source RTL.
4. Add durable documents to `docs/README.md` in the same change.
5. New top-level directories require a durable decision and layout-check update.

## Before moving/removing a file

1. Inspect Git state, references, ownership and recovery path.
2. Preserve all unique evidence and source pins.
3. Never remove or mutate submodule content as cleanup.
4. Never delete raw evidence referenced by a committed summary until reconstructibility/recovery is verified.
5. Run layout, link, functional and diff checks after the change.

## Mechanical rules

`check_repository_layout.py` enforces a bounded subset:

- required governance files exist;
- forbidden generated suffixes are not tracked outside approved evidence locations;
- no tracked files are added under `build/`, `reports/`, `sim/` or `waves/`;
- submodule pins remain declared through `.gitmodules` and contract verification;
- obvious backup/status-note filename patterns are rejected;
- durable docs index exists.

The checker does not decide protocol correctness, scientific equivalence, timing closure or hardware validity. Those remain evidence/verification responsibilities.
