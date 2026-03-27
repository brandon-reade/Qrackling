#!/usr/bin/env python3
r"""
Run many MODTRAN6 JSON cases in parallel using mod6con.exe.

Multi-case file format produced by modtran_case_generator.py:
  { "MODTRAN": [ case1, case2, ... ] }

So each per-case input.json must be:
  { "MODTRAN": [ caseN ] }    (where MODTRAN must be an array)

Invocation used:
  mod6con.exe "<input.json>" "<MOD6DATA_DIR>" -workpath "<case_workdir>"

Update (March 2026):
- De-duplicate collected outputs in shared collection dirs.
  * Removes "__001", "__002", ... duplicates (keeps newest by mtime).
- Find missing collected outputs and create a filtered JSON containing only missing cases.
- Optionally re-run missing cases automatically (looping up to N passes).
- Naming convention alignment with MATLAB:
  * prefix = "{case_index:06d}_{case_name}"
  * collected name = "{prefix}__{original_output_filename}"
  * The case_name comes from MODTRANINPUT.NAME (e.g. "Transm_HOGS_500mvis_none_urban_background_zen10_azi150")
  * Original output filename should already be in that convention, e.g. "..._scan.csv"

Example usage
python .\modtran6_parallel_runner.py `
  --cases-json "E:\MODTRAN_RESULTS\PythonGeneratedCases\HOGSWinterClear-1kVisib\moon_jan3rd_2026_1am_800to3000nm_full\HOGSWinter1am_1kmVis_800to3000_zen0step10_azi0step30.json" `
  --runs-dir "E:\MODTRAN_RESULTS\runs_tmp" `
  --max-workers 8 `
  --modtran-exe "E:\MODTRAN\MODTRAN6\x86_64\mod6con.exe" `
  --modtran-data-dir "E:\MODTRAN\MOD6DATA" `
  --output-mode shared `
  --collect-dir "E:\MODTRAN_RESULTS\PythonGeneratedCases\HOGSWinterClear-1kVisib\moon_jan3rd_2026_1am_800to3000nm_full" `
  --collect-glob "*_scan.csv" `
  --dedupe-collect `
  --verify-collect `
  --repair-missing `
  --repair-out-json "E:\MODTRAN_RESULTS\collect\missing_only.json" `
  --repair-max-passes 2 `
  --keep-failed-workdirs
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple


# -----------------------------------------------------------------------------------
# ----------------------------------- CLASSES ---------------------------------------
# -----------------------------------------------------------------------------------
@dataclass(frozen=True)
class RunResult:
    case_index: int
    case_name: str
    workdir: str
    returncode: int
    elapsed_s: float
    stdout_path: str
    stderr_path: str
    collected_files: List[str]


# -----------------------------------------------------------------------------------
# ---------------------------------- FUNCTIONS --------------------------------------
# -----------------------------------------------------------------------------------
def _sanitize_filename(s: str, max_len: int = 120) -> str:
    s = str(s).strip()
    s = re.sub(r"[^\w\-. ]+", "_", s)
    s = re.sub(r"\s+", "_", s)
    s = s[:max_len] if len(s) > max_len else s
    return s if s else "case"


def _default_max_workers() -> int:
    c = os.cpu_count() or 1
    return max(1, c - 1)


def _resolve_required_file(p: str) -> Path:
    path = Path(p).expanduser().resolve()
    if not path.exists():
        raise FileNotFoundError(f"File not found: {path}")
    if not path.is_file():
        raise IsADirectoryError(f"Expected file path but got directory: {path}")
    return path


def _resolve_required_dir(p: str) -> Path:
    path = Path(p).expanduser().resolve()
    if not path.exists():
        raise FileNotFoundError(f"Directory not found: {path}")
    if not path.is_dir():
        raise NotADirectoryError(f"Expected directory path but got file: {path}")
    return path


def _resolve_exe(p: str) -> Path:
    path = Path(p).expanduser().resolve()
    if not path.exists():
        raise FileNotFoundError(f"MODTRAN exe not found: {path}")
    if not path.is_file():
        raise IsADirectoryError(f"MODTRAN exe path is not a file: {path}")
    return path


def _load_cases(cases_json_path: Path) -> List[Dict[str, Any]]:
    data = json.loads(cases_json_path.read_text(encoding="utf-8"))
    if "MODTRAN" not in data or not isinstance(data["MODTRAN"], list):
        raise ValueError(f"Expected top-level key 'MODTRAN' list in {cases_json_path}")
    if not all(isinstance(x, dict) for x in data["MODTRAN"]):
        raise ValueError("Expected each element of top-level MODTRAN list to be an object/dict.")
    return data["MODTRAN"]


def _wrap_case_for_mod6con(case: Dict[str, Any]) -> Dict[str, Any]:
    """
    mod6con.exe expects: { "MODTRAN": [ ... ] } where MODTRAN is an array.
    For a single case we must write: { "MODTRAN": [case] }.
    """
    # If caller already provides correct form, keep it.
    if isinstance(case, dict) and "MODTRAN" in case and isinstance(case["MODTRAN"], list):
        return case
    return {"MODTRAN": [case]}


def _write_case_json(case: Dict[str, Any], out_path: Path) -> None:
    payload = _wrap_case_for_mod6con(case)
    out_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def _get_case_name(case: Dict[str, Any], case_index: int) -> str:
    """
    Align with MATLAB: case_name should be MODTRANINPUT.NAME.
    Example:
      "Transm_HOGS_500mvis_none_urban_background_zen10_azi150"
    """
    try:
        nm = str(case["MODTRANINPUT"]["NAME"])
        nm = nm.strip()
        return nm if nm else f"case_{case_index}"
    except Exception:
        return f"case_{case_index}"


def _case_prefix(case_index: int, case_name: str, mode: str) -> str:
    safe_name = _sanitize_filename(case_name)
    if mode == "index":
        return f"{case_index:06d}"
    return f"{case_index:06d}_{safe_name}"


def _unique_dest_path(dest_dir: Path, desired_name: str) -> Path:
    dest_dir.mkdir(parents=True, exist_ok=True)
    base = Path(desired_name).stem
    ext = Path(desired_name).suffix

    candidate = dest_dir / f"{base}{ext}"
    if not candidate.exists():
        return candidate

    i = 1
    while True:
        candidate = dest_dir / f"{base}__{i:03d}{ext}"
        if not candidate.exists():
            return candidate
        i += 1


def _collect_outputs(workdir: Path, collect_globs: Sequence[str], dest_dir: Path, prefix: Optional[str]) -> List[str]:
    collected: List[str] = []
    for pattern in collect_globs:
        for src in workdir.glob(pattern):
            if not src.is_file():
                continue

            # IMPORTANT: do not double-prefix; only prefix once, at collection time.
            out_name = src.name
            if prefix:
                out_name = f"{prefix}__{out_name}"

            dst = _unique_dest_path(dest_dir, out_name)
            shutil.copy2(src, dst)
            collected.append(str(dst))
    return collected


def _strip_trailing_numeric_suffix(name: str) -> str:
    """
    Dedupe helper:
      foo.csv
      foo__001.csv
      foo__002.csv
    are considered the same group => key foo.csv
    """
    p = Path(name)
    stem = p.stem
    ext = p.suffix
    stem2 = re.sub(r"__\d{3}$", "", stem)
    return f"{stem2}{ext}"


def dedupe_collection_dir(collect_dir: Path) -> int:
    """
    Remove duplicates in collect_dir by grouping on strip_trailing_numeric_suffix(filename).
    Keep the newest file (mtime) in each group.
    Returns number of removed files.
    """
    if not collect_dir.exists():
        return 0
    if not collect_dir.is_dir():
        raise NotADirectoryError(f"collect_dir is not a directory: {collect_dir}")

    groups: Dict[str, List[Path]] = {}
    for p in collect_dir.iterdir():
        if not p.is_file():
            continue
        key = _strip_trailing_numeric_suffix(p.name)
        groups.setdefault(key, []).append(p)

    removed = 0
    for key, files in groups.items():
        if len(files) <= 1:
            continue
        files_sorted = sorted(files, key=lambda x: x.stat().st_mtime, reverse=True)
        keep = files_sorted[0]
        for f in files_sorted[1:]:
            try:
                f.unlink()
                removed += 1
            except Exception:
                # ignore delete errors
                pass
    return removed


def _find_missing_case_indices(
    cases: Sequence[Dict[str, Any]],
    collect_dir: Path,
    collect_globs: Sequence[str],
    *,
    prefix_mode: str,
    require_collected_per_glob: int = 1,
) -> Tuple[List[int], List[Dict[str, Any]]]:
    """
    For each case, check if collect_dir contains at least require_collected_per_glob matches for:
      <prefix>__<glob>
    Returns:
      missing_indices: [case_index,...] (1-based indices)
      info: list of dicts describing missing globs per case
    """
    missing: List[int] = []
    info: List[Dict[str, Any]] = []

    for i, case in enumerate(cases, start=1):
        case_name = _get_case_name(case, i)
        prefix = _case_prefix(i, case_name, prefix_mode)

        missing_globs: List[str] = []
        for g in collect_globs:
            # At least N matches for this glob
            pat = f"{prefix}__{g}"
            matches = list(collect_dir.glob(pat))
            if len([m for m in matches if m.is_file()]) < int(require_collected_per_glob):
                missing_globs.append(g)

        if missing_globs:
            missing.append(i)
            info.append(
                {
                    "case_index": i,
                    "case_name": case_name,
                    "prefix": prefix,
                    "missing_globs": missing_globs,
                }
            )

    return missing, info


def write_filtered_cases_json(
    cases: Sequence[Dict[str, Any]],
    indices_1based: Sequence[int],
    out_path: Path,
) -> None:
    """
    Write a new multi-case JSON containing only selected case indices
    Format: { "MODTRAN": [ ... ] }
    """
    out_path.parent.mkdir(parents=True, exist_ok=True)
    filtered = [cases[i - 1] for i in indices_1based]
    payload = {"MODTRAN": filtered}
    out_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


# -----------------------------------------------------------------------------------
# ---------------------------------- RUN 1 CASE -------------------------------------
# -----------------------------------------------------------------------------------
def _run_one_case(
    case: Dict[str, Any],
    case_index: int,
    runs_dir: Path,
    *,
    modtran_exe: str,
    modtran_data_dir: str,
    timeout_s: Optional[float],
    output_mode: str,  # "per-case" | "shared"
    collect_dir: Optional[str],
    collect_globs: Sequence[str],
    keep_failed_workdirs: bool,
    keep_workdirs: bool,
    collect_prefix_mode: str,  # "index" | "index_name"
) -> RunResult:
    case_name = _get_case_name(case, case_index)
    safe_name = _sanitize_filename(case_name) or f"case_{case_index:06d}"
    workdir = runs_dir / f"{case_index:06d}_{safe_name}"

    if workdir.exists():
        shutil.rmtree(workdir)
    workdir.mkdir(parents=True, exist_ok=True)

    input_json = workdir / "input.json"
    _write_case_json(case, input_json)

    stdout_path = workdir / "stdout.txt"
    stderr_path = workdir / "stderr.txt"
    command_txt = workdir / "command.txt"

    exe_path = _resolve_exe(modtran_exe)
    data_dir = _resolve_required_dir(modtran_data_dir)
    cwd = exe_path.parent

    args = [str(exe_path), str(input_json), str(data_dir), "-workpath", str(workdir)]

    command_txt.write_text(
        "MODE: mod6con\n"
        f"CWD: {cwd}\n"
        "ARGS:\n" + "\n".join(args) + "\n",
        encoding="utf-8",
    )

    start = time.time()
    collected: List[str] = []
    try:
        cp = subprocess.run(
            args,
            cwd=str(cwd),
            shell=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout_s,
        )
        elapsed = time.time() - start

        stdout_path.write_text(cp.stdout or "", encoding="utf-8", errors="replace")
        stderr_path.write_text(cp.stderr or "", encoding="utf-8", errors="replace")

        rc = int(cp.returncode)

        if output_mode == "shared" and rc == 0:
            if not collect_dir:
                raise ValueError("--output-mode shared requires --collect-dir")
            dest = Path(collect_dir).expanduser().resolve()
            prefix = _case_prefix(case_index, case_name, collect_prefix_mode)
            collected = _collect_outputs(workdir, collect_globs, dest, prefix=prefix)

        result = RunResult(
            case_index=case_index,
            case_name=case_name,
            workdir=str(workdir),
            returncode=rc,
            elapsed_s=float(elapsed),
            stdout_path=str(stdout_path),
            stderr_path=str(stderr_path),
            collected_files=collected,
        )
    except subprocess.TimeoutExpired as e:
        elapsed = time.time() - start
        stdout_path.write_text((e.stdout or ""), encoding="utf-8", errors="replace")
        stderr_path.write_text((e.stderr or ""), encoding="utf-8", errors="replace")
        result = RunResult(
            case_index=case_index,
            case_name=case_name,
            workdir=str(workdir),
            returncode=124,
            elapsed_s=float(elapsed),
            stdout_path=str(stdout_path),
            stderr_path=str(stderr_path),
            collected_files=[],
        )

    if result.returncode == 0:
        if not keep_workdirs:
            shutil.rmtree(workdir)
    else:
        if not keep_failed_workdirs:
            shutil.rmtree(workdir)

    return result


# -----------------------------------------------------------------------------------
# ------------------------------------ MAIN -----------------------------------------
# -----------------------------------------------------------------------------------
def main(argv: Optional[List[str]] = None) -> int:
    p = argparse.ArgumentParser(description="Run MODTRAN6 cases in parallel using mod6con.exe (Windows).")

    p.add_argument("--cases-json", required=True)
    p.add_argument("--runs-dir", required=True)

    p.add_argument("--modtran-exe", required=True)
    p.add_argument("--modtran-data-dir", required=True)

    p.add_argument("--max-workers", type=int, default=_default_max_workers())
    p.add_argument("--timeout-s", type=float, default=None)

    p.add_argument("--output-mode", choices=["per-case", "shared"], default="per-case")
    p.add_argument("--collect-dir", default=None)
    p.add_argument("--collect-glob", action="append", default=[])

    p.add_argument("--keep-workdirs", action="store_true")
    p.add_argument("--keep-failed-workdirs", action="store_true")
    p.add_argument("--python-exe", default=sys.executable)

    # naming / verification / repair
    p.add_argument("--collect-prefix-mode", choices=["index", "index_name"], default="index_name")
    p.add_argument("--dedupe-collect", action="store_true", help="Remove duplicate collected files (keeps newest).")
    p.add_argument("--verify-collect", action="store_true", help="Check for missing collected outputs after the run.")
    p.add_argument("--require-collected-per-glob", type=int, default=1, help="Required matches per glob per case.")
    p.add_argument("--repair-missing", action="store_true", help="If missing outputs detected, generate filtered JSON and run again.")
    p.add_argument("--repair-out-json", default=None, help="Path to write missing-only JSON (default: <runs_dir>/missing_only.json).")
    p.add_argument("--repair-max-passes", type=int, default=1, help="How many repair passes to attempt.")

    args = p.parse_args(argv)

    t_total = time.time()

    cases_json_path = _resolve_required_file(args.cases_json)
    runs_dir = Path(args.runs_dir).expanduser().resolve()
    runs_dir.mkdir(parents=True, exist_ok=True)

    cases = _load_cases(cases_json_path)

    if args.output_mode == "shared":
        if not args.collect_dir:
            raise ValueError("--output-mode shared requires --collect-dir")
        Path(args.collect_dir).expanduser().resolve().mkdir(parents=True, exist_ok=True)

    print(f"Python exe:      {args.python_exe}")
    print(f"Cases file:      {cases_json_path}")
    print(f"Runs dir:        {runs_dir}")
    print(f"Cases:           {len(cases)}")
    print(f"Workers:         {args.max_workers}")
    print(f"MODTRAN exe:     {_resolve_exe(args.modtran_exe)}")
    print(f"MODTRAN data:    {_resolve_required_dir(args.modtran_data_dir)}")
    print(f"Output mode:     {args.output_mode}")
    if args.output_mode == "shared":
        print(f"Collect dir:     {Path(args.collect_dir).expanduser().resolve()}")
        print(f"Collect globs:   {args.collect_glob}")
        print(f"Collect prefix:  {args.collect_prefix_mode}")
    print()

    from concurrent.futures import ProcessPoolExecutor, as_completed

    def run_batch(batch_cases: Sequence[Dict[str, Any]], base_index_map: Optional[Sequence[int]] = None) -> Tuple[List[RunResult], List[RunResult]]:
        """
        Run a set of cases. If base_index_map is provided, it is a list of original case indices,
        aligned with batch_cases, so we keep consistent prefixes.
        """
        results: List[RunResult] = []
        failures: List[RunResult] = []

        with ProcessPoolExecutor(max_workers=int(args.max_workers)) as ex:
            futs = []
            for j, case in enumerate(batch_cases, start=1):
                original_index = base_index_map[j - 1] if base_index_map is not None else j

                futs.append(
                    ex.submit(
                        _run_one_case,
                        case,
                        original_index,
                        runs_dir,
                        modtran_exe=args.modtran_exe,
                        modtran_data_dir=args.modtran_data_dir,
                        timeout_s=args.timeout_s,
                        output_mode=args.output_mode,
                        collect_dir=args.collect_dir,
                        collect_globs=args.collect_glob,
                        keep_failed_workdirs=bool(args.keep_failed_workdirs),
                        keep_workdirs=bool(args.keep_workdirs),
                        collect_prefix_mode=args.collect_prefix_mode,
                    )
                )

            for fut in as_completed(futs):
                r = fut.result()
                results.append(r)
                status = "OK" if r.returncode == 0 else f"FAIL(rc={r.returncode})"
                extra = ""
                if args.output_mode == "shared" and r.returncode == 0:
                    extra = f" collected={len(r.collected_files)}"
                print(f"[{status}] case={r.case_index:06d} elapsed={r.elapsed_s:7.2f}s{extra}")
                if r.returncode != 0:
                    failures.append(r)

        results.sort(key=lambda x: x.case_index)
        failures.sort(key=lambda x: x.case_index)
        return results, failures

    # --------------------------
    # 1) Initial run
    # --------------------------
    results, failures = run_batch(cases)

    summary_path = runs_dir / "summary.json"
    summary_path.write_text(json.dumps([r.__dict__ for r in results], indent=2), encoding="utf-8")

    print()
    print(f"Summary written: {summary_path}")
    print(f"Failures: {len(failures)}/{len(results)}")

    # --------------------------
    # 2) Optional dedupe
    # --------------------------
    if args.output_mode == "shared" and args.dedupe_collect:
        collect_dir = Path(args.collect_dir).expanduser().resolve()
        removed = dedupe_collection_dir(collect_dir)
        print(f"De-dupe removed: {removed}")

    # --------------------------
    # 3) Optional verify + repair missing
    # --------------------------
    if args.output_mode == "shared" and (args.verify_collect or args.repair_missing):
        collect_dir = Path(args.collect_dir).expanduser().resolve()
        missing_idx, missing_info = _find_missing_case_indices(
            cases,
            collect_dir,
            args.collect_glob,
            prefix_mode=args.collect_prefix_mode,
            require_collected_per_glob=int(args.require_collected_per_glob),
        )

        if missing_idx:
            print()
            print(f"Missing collected outputs for {len(missing_idx)} cases.")
            # Print a few lines (still safe for large runs)
            for mi in missing_info[:20]:
                print(f"  case={mi['case_index']:06d} missing={mi['missing_globs']}")

            if args.repair_missing:
                out_json = Path(args.repair_out_json).expanduser().resolve() if args.repair_out_json else (runs_dir / "missing_only.json")

                passes = max(1, int(args.repair_max_passes))
                remaining = list(missing_idx)

                for pass_i in range(1, passes + 1):
                    if not remaining:
                        break

                    print()
                    print(f"Repair pass {pass_i}/{passes}: remaining missing cases = {len(remaining)}")

                    # Write filtered JSON (missing-only)
                    write_filtered_cases_json(cases, remaining, out_json)
                    print(f"Wrote missing-only JSON: {out_json}")

                    # Run only missing cases, but keep ORIGINAL indices for consistent naming/prefixing
                    batch_cases = [cases[i - 1] for i in remaining]
                    results_missing, failures_missing = run_batch(batch_cases, base_index_map=remaining)

                    # Optional dedupe after each pass
                    if args.dedupe_collect:
                        removed = dedupe_collection_dir(collect_dir)
                        print(f"De-dupe removed: {removed}")

                    # Re-check missing
                    missing_idx2, missing_info2 = _find_missing_case_indices(
                        cases,
                        collect_dir,
                        args.collect_glob,
                        prefix_mode=args.collect_prefix_mode,
                        require_collected_per_glob=int(args.require_collected_per_glob),
                    )

                    remaining = list(missing_idx2)

                if remaining:
                    print()
                    print(f"After repair passes, still missing: {len(remaining)} cases.")
                else:
                    print()
                    print("Repair completed: no missing cases detected.")
        else:
            print()
            print("No missing collected outputs detected.")

    print()
    print(f"Total elapsed: {time.time() - t_total:.2f} s")

    return 0 if not failures else 2


if __name__ == "__main__":
    raise SystemExit(main())