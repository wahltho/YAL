#!/usr/bin/env python3
from __future__ import annotations

import argparse
import pathlib
import re
import subprocess
import sys
from dataclasses import dataclass
from typing import Dict, List, Optional

ROOT = pathlib.Path(__file__).resolve().parents[1]

DEFAULT_RULES = {
    "data/modules/Custom Module/windows/taxi.lua": {
        "main": {
            "slots": {"warn_at": 200, "max": 210},
            "locals": {"warn_at": 200, "max": 210},
        },
        "functions": {
            "updateTaxiState": {
                "upvalues": {"warn_at": 58, "max": 60},
            },
        },
    },
}

MAIN_HEADER_RE = re.compile(r"^main <(?P<path>.+?):0,0> \((?P<instructions>\d+) instructions")
FUNC_HEADER_RE = re.compile(
    r"^function <(?P<path>.+?):(?P<start>\d+),(?P<end>\d+)> \((?P<instructions>\d+) instructions"
)
SIG_RE = re.compile(
    r"^(?P<params>\d+)\+? params, (?P<slots>\d+) slots, (?P<upvalues>\d+) upvalues?, (?P<locals>\d+) locals?, (?P<constants>\d+) constants?, (?P<functions>\d+) functions"
)
LOCAL_FUNCTION_RE = re.compile(r"^\s*local function\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)\b")
ASSIGN_FUNCTION_RE = re.compile(r"^\s*(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*function\b")


@dataclass
class ChunkInfo:
    start_line: int
    end_line: int
    slots: int
    upvalues: int
    locals_count: int


@dataclass
class FileReport:
    relpath: str
    syntax_ok: bool
    main_slots: Optional[int] = None
    main_upvalues: Optional[int] = None
    main_locals: Optional[int] = None
    functions: Optional[Dict[str, ChunkInfo]] = None
    warnings: Optional[List[str]] = None
    failures: Optional[List[str]] = None

    def __post_init__(self) -> None:
        if self.functions is None:
            self.functions = {}
        if self.warnings is None:
            self.warnings = []
        if self.failures is None:
            self.failures = []


def run_luac(args: List[str], file_path: pathlib.Path) -> str:
    result = subprocess.run(
        ["luac", *args, str(file_path)],
        cwd=ROOT,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(detail or f"luac {' '.join(args)} failed for {file_path}")
    return result.stdout


def collect_function_lines(file_path: pathlib.Path) -> Dict[str, int]:
    found: Dict[str, int] = {}
    with file_path.open("r", encoding="utf-8") as handle:
        for lineno, line in enumerate(handle, start=1):
            match = LOCAL_FUNCTION_RE.match(line) or ASSIGN_FUNCTION_RE.match(line)
            if not match:
                continue
            name = match.group("name")
            found.setdefault(name, lineno)
    return found


def parse_luac_listing(listing: str) -> tuple[dict, List[ChunkInfo]]:
    lines = listing.splitlines()
    main_metrics = {}
    chunks: List[ChunkInfo] = []
    idx = 0
    while idx < len(lines):
        line = lines[idx].strip()
        main_match = MAIN_HEADER_RE.match(line)
        func_match = FUNC_HEADER_RE.match(line)
        if main_match and idx + 1 < len(lines):
            sig_match = SIG_RE.match(lines[idx + 1].strip())
            if sig_match:
                main_metrics = {
                    "slots": int(sig_match.group("slots")),
                    "upvalues": int(sig_match.group("upvalues")),
                    "locals": int(sig_match.group("locals")),
                }
            idx += 1
        elif func_match and idx + 1 < len(lines):
            sig_match = SIG_RE.match(lines[idx + 1].strip())
            if sig_match:
                chunks.append(
                    ChunkInfo(
                        start_line=int(func_match.group("start")),
                        end_line=int(func_match.group("end")),
                        slots=int(sig_match.group("slots")),
                        upvalues=int(sig_match.group("upvalues")),
                        locals_count=int(sig_match.group("locals")),
                    )
                )
            idx += 1
        idx += 1
    return main_metrics, chunks


def find_chunk_for_line(chunks: List[ChunkInfo], line_no: int) -> Optional[ChunkInfo]:
    exact = [chunk for chunk in chunks if chunk.start_line == line_no]
    if exact:
        return exact[0]
    nearby = sorted(chunks, key=lambda chunk: abs(chunk.start_line - line_no))
    if nearby and abs(nearby[0].start_line - line_no) <= 2:
        return nearby[0]
    return None


def apply_threshold(report: FileReport, label: str, metric: str, value: int, rule: dict) -> None:
    warn_at = rule.get("warn_at")
    max_value = rule.get("max")
    if max_value is not None and value > max_value:
        report.failures.append(f"{label} {metric}={value} exceeds max {max_value}")
    elif warn_at is not None and value >= warn_at:
        report.warnings.append(f"{label} {metric}={value} near limit (warn_at {warn_at})")


def check_file(relpath: str) -> FileReport:
    file_path = ROOT / relpath
    report = FileReport(relpath=relpath, syntax_ok=False)
    run_luac(["-p"], file_path)
    report.syntax_ok = True
    listing = run_luac(["-l", "-l"], file_path)
    main_metrics, chunks = parse_luac_listing(listing)
    report.main_slots = main_metrics.get("slots")
    report.main_upvalues = main_metrics.get("upvalues")
    report.main_locals = main_metrics.get("locals")

    rules = DEFAULT_RULES.get(relpath, {})
    main_rules = rules.get("main", {})
    if report.main_slots is not None and "slots" in main_rules:
        apply_threshold(report, "main", "slots", report.main_slots, main_rules["slots"])
    if report.main_locals is not None and "locals" in main_rules:
        apply_threshold(report, "main", "locals", report.main_locals, main_rules["locals"])

    function_lines = collect_function_lines(file_path)
    for func_name, func_rules in rules.get("functions", {}).items():
        line_no = function_lines.get(func_name)
        if line_no is None:
            report.failures.append(f"function {func_name} not found in source")
            continue
        chunk = find_chunk_for_line(chunks, line_no)
        if chunk is None:
            report.failures.append(f"function {func_name} has no matching luac chunk near line {line_no}")
            continue
        report.functions[func_name] = chunk
        for metric_name, threshold in func_rules.items():
            value = getattr(chunk, metric_name if metric_name != "locals" else "locals_count")
            apply_threshold(report, func_name, metric_name, value, threshold)
    return report


def format_report(report: FileReport) -> List[str]:
    lines = [f"FILE {report.relpath}"]
    if report.main_slots is not None:
        lines.append(
            f"  main: slots={report.main_slots} upvalues={report.main_upvalues} locals={report.main_locals}"
        )
    for func_name, chunk in sorted(report.functions.items()):
        lines.append(
            f"  {func_name}: line={chunk.start_line} slots={chunk.slots} upvalues={chunk.upvalues} locals={chunk.locals_count}"
        )
    for warning in report.warnings:
        lines.append(f"  WARN: {warning}")
    for failure in report.failures:
        lines.append(f"  FAIL: {failure}")
    if not report.warnings and not report.failures:
        lines.append("  OK")
    return lines


def main(argv: List[str]) -> int:
    parser = argparse.ArgumentParser(description="Check known SASL-sensitive Lua files with luac metrics.")
    parser.add_argument(
        "files",
        nargs="*",
        help="Repo-relative Lua files to inspect. Defaults to configured high-risk files.",
    )
    args = parser.parse_args(argv)

    targets = args.files or list(DEFAULT_RULES.keys())
    reports = [check_file(relpath) for relpath in targets]
    for report in reports:
        print("\n".join(format_report(report)))
    return 1 if any(report.failures for report in reports) else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
