"""一条命令完成咕咕模型的后台轮廓渲染和多视图评分。"""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_BLEND = PROJECT_ROOT / "Assets/Brand/Model/source/gugu-sculpt-v2-stage-04-transition-refine.blend"
DEFAULT_REGISTRATION = PROJECT_ROOT / "Assets/Brand/Model/analysis/reference/gugu-orthographic-registration.auto.json"
REFERENCE_DIR = PROJECT_ROOT / "Assets/Brand/Model/reference"
CLEAN_REFERENCE_DIR = PROJECT_ROOT / "Assets/Brand/Model/analysis/reference/clean-character-masks"
VENV_PYTHON = PROJECT_ROOT / ".venv-blender-fit/bin/python"
BLENDER = Path("/opt/homebrew/bin/blender")
RENDER_SCRIPT = Path(__file__).with_name("render_gugu_silhouettes.py")
VALIDATOR = Path.home() / ".codex/skills/reference-analysis-validator/scripts/render_overlay_validator.py"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--blend", type=Path, default=DEFAULT_BLEND)
    parser.add_argument("--registration", type=Path, default=DEFAULT_REGISTRATION)
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=PROJECT_ROOT / "Assets/Brand/Model/analysis/fit/stage04",
    )
    parser.add_argument("--prefix", default="gugu-stage04")
    return parser.parse_args()


def run(command: list[str]) -> None:
    subprocess.run(command, check=True, cwd=PROJECT_ROOT)


def main() -> None:
    args = parse_args()
    required = [args.blend, args.registration, VENV_PYTHON, BLENDER, RENDER_SCRIPT, VALIDATOR]
    missing = [str(path) for path in required if not path.exists()]
    if missing:
        raise SystemExit("缺少运行文件：\n" + "\n".join(missing))

    args.out_dir.mkdir(parents=True, exist_ok=True)
    render_dir = args.out_dir / "renders"
    overlay_dir = args.out_dir / "overlays"
    metrics_dir = args.out_dir / "metrics"
    for directory in (render_dir, overlay_dir, metrics_dir):
        directory.mkdir(parents=True, exist_ok=True)

    run(
        [
            str(BLENDER),
            "--background",
            str(args.blend),
            "--python-exit-code",
            "2",
            "--python",
            str(RENDER_SCRIPT),
            "--",
            "--registration",
            str(args.registration),
            "--out-dir",
            str(render_dir),
            "--prefix",
            args.prefix,
        ]
    )

    reports = {}
    for role in ("front", "side", "back"):
        reference = CLEAN_REFERENCE_DIR / f"gugu-{role}-clean-silhouette.png"
        render = render_dir / f"{args.prefix}-{role}.png"
        metric = metrics_dir / f"{role}.json"
        overlay = overlay_dir / f"{role}.png"
        run(
            [
                str(VENV_PYTHON),
                str(VALIDATOR),
                "--reference",
                str(reference),
                "--render",
                str(render),
                "--reference-mode",
                "bright_on_dark",
                "--render-mode",
                "bright_on_dark",
                "--out",
                str(metric),
                "--overlay",
                str(overlay),
            ]
        )
        reports[role] = json.loads(metric.read_text(encoding="utf-8"))

    summary = {
        "schema": "gugu_multiview_fit.v1",
        "blend": str(args.blend),
        "note": "当前参考掩码包含完整角色；模型部件未完成前，IoU 只作为基线，不作为放行结论。",
        "views": reports,
        "mean_iou": sum(item["iou"] for item in reports.values()) / len(reports),
    }
    summary_path = args.out_dir / "fit-summary.json"
    summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"summary": str(summary_path), "mean_iou": summary["mean_iou"]}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
