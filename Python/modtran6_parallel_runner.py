#!/usr/bin/env python3
r"""
Run many MODTRAN6 JSON cases in parallel using mod6con.exe.

Multi-case file format produced by modtran_case_generator.py:
  { "MODTRAN": [ case1, case2, ... ] }

So each per-case input.json is must be:
  { "MODTRAN": [ caseN ] }    (where MODTRAN must be an array)

Invocation used:
  mod6con.exe "<input.json>" "<MOD6DATA_DIR>" -workpath "<case_workdir>"

Example usage
python .\modtran6_parallel_runner.py `
>>   --cases-json "E:\MODTRAN_RESULTS\PythonGeneratedCases\HOGSWinterClear-1kVisib\moon_jan3rd_2026_1am_800to3000nm_full\HOGSWinter1am_1kmVis_800to3000_zen0step10_azi0step30.json" `
>>   --runs-dir "E:\MODTRAN_RESULTS\runs_tmp" `
>>   --max-workers 8 `
>>   --modtran-exe "E:\MODTRAN\MODTRAN6\x86_64\mod6con.exe" `
>>   --modtran-data-dir "E:\MODTRAN\MOD6DATA" `
>>   --output-mode shared `
>>   --collect-dir "E:\MODTRAN_RESULTS\PythonGeneratedCases\HOGSWinterClear-1kVisib\moon_jan3rd_2026_1am_800to3000nm_full" `
>>   --collect-glob "*_scan.csv" `
>>   --keep-failed-workdirs
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
from typing import Any, Dict, List, Optional, Sequence

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
    s = s.strip()
    s = re.sub(r"[^\w\-. ]+", "_", s)
    s = re.sub(r"\s+", "_", s)
    return s[:max_len] if len(s) > max_len else s


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
            out_name = src.name
            if prefix:
                out_name = f"{prefix}__{out_name}"
            dst = _unique_dest_path(dest_dir, out_name)
            shutil.copy2(src, dst)
            collected.append(str(dst))
    return collected

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
) -> RunResult:
    try:
        case_name = str(case["MODTRANINPUT"]["NAME"])
    except Exception:
        case_name = f"case_{case_index}"

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
            prefix = f"{case_index:06d}_{safe_name}"
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

    args = p.parse_args(argv)

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
    print()

    from concurrent.futures import ProcessPoolExecutor, as_completed

    results: List[RunResult] = []
    failures: List[RunResult] = []

    with ProcessPoolExecutor(max_workers=int(args.max_workers)) as ex:
        futs = []
        for i, case in enumerate(cases, start=1):
            futs.append(
                ex.submit(
                    _run_one_case,
                    case,
                    i,
                    runs_dir,
                    modtran_exe=args.modtran_exe,
                    modtran_data_dir=args.modtran_data_dir,
                    timeout_s=args.timeout_s,
                    output_mode=args.output_mode,
                    collect_dir=args.collect_dir,
                    collect_globs=args.collect_glob,
                    keep_failed_workdirs=bool(args.keep_failed_workdirs),
                    keep_workdirs=bool(args.keep_workdirs),
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
    summary_path = runs_dir / "summary.json"
    summary_path.write_text(json.dumps([r.__dict__ for r in results], indent=2), encoding="utf-8")

    print()
    print(f"Summary written: {summary_path}")
    print(f"Failures: {len(failures)}/{len(results)}")
    return 0 if not failures else 2


if __name__ == "__main__":
    raise SystemExit(main())