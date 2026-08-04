"""从 stage420 母版渲染指定动作的 PNG 序列，供 FFmpeg 合成预览。"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import bpy


ROOT = Path("/Volumes/data/rplearn")
BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-420-animation-refined.blend"
OUTPUT_DIR = ROOT / "Assets/Brand/Model/renders/gugu-v3/stage420-animation/videos"
CLIPS = {
    "idle": ("GUGU_IDLE_LOOP", 1, 97, "gugu-stage420-idle-loop.mp4"),
    "celebrate": ("GUGU_CELEBRATE", 1, 73, "gugu-stage420-celebrate.mp4"),
    "talk": ("GUGU_TALK_LOOP", 1, 49, "gugu-stage420-talk-loop.mp4"),
}


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--clip", required=True, choices=sorted(CLIPS))
    parser.add_argument("--frames-dir", required=True)
    return parser.parse_args(argv)


def main() -> None:
    args = parse_args()
    action_name, start, end, filename = CLIPS[args.clip]
    frames_dir = Path(args.frames_dir).resolve()
    bpy.ops.wm.open_mainfile(filepath=str(BLEND))
    scene = bpy.context.scene
    rig = bpy.data.objects["RIG_GUGU"]
    rig.animation_data.action = bpy.data.actions[action_name]
    scene.frame_start = start
    scene.frame_end = end
    scene.render.fps = 24
    scene.render.fps_base = 1.0
    scene.camera = bpy.data.objects["CAM_验证_四分之三"]
    scene.camera.data.ortho_scale = 12.0
    scene.render.resolution_x = 480
    scene.render.resolution_y = 640
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.image_settings.color_depth = "8"
    scene.render.image_settings.compression = 35
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    frames_dir.mkdir(parents=True, exist_ok=True)
    scene.render.filepath = str(frames_dir / "frame-")
    bpy.ops.render.render(animation=True)
    print(f"动作帧已输出：{frames_dir}；目标视频：{OUTPUT_DIR / filename}")


if __name__ == "__main__":
    main()
