# 咕咕与嘎嘎的三维渲染：按改版前定稿形象（Assets/Brand/Mascots/duo-calibration-v1/corrected.png
# 与 ui-pack-v1）程序化建模，逐姿态渲染透明 PNG。
#
# 用法（仓库根目录）：
#   blender -b -P Tools/ArtPipeline/Blender/mascot3d.py -- <输出目录> [gugu,gaga] [姿态,...]
# 环境变量 MASCOT_RES（默认 512）、MASCOT_SAMPLES（默认 96）。
# 输出 <bird>-<pose>.png、需要眨眼的姿态另出 <bird>-<pose>-blink.png，
# 挥手/庆祝另出翅膀层 <bird>-<pose>-wing-l|r.png，以及记录翅膀转轴的 manifest.json。

import json
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(ARGS[0] if ARGS else "build/mascot3d")
BIRDS = ARGS[1].split(",") if len(ARGS) > 1 and ARGS[1] else ["gugu", "gaga"]
ALL_POSES = ["happy", "wave", "point", "celebrate", "sleepy", "curious", "thinking", "proud", "pout", "care"]
POSES = ARGS[2].split(",") if len(ARGS) > 2 and ARGS[2] else ALL_POSES
RES = int(os.environ.get("MASCOT_RES", "512"))
SAMPLES = int(os.environ.get("MASCOT_SAMPLES", "96"))

# 画面：正交相机，脚底在画面 93% 处，与旧版 100 单位画布一致。
FRAME = 2.6
FEET_ROW = 0.93
CENTER_Z = (FEET_ROW - 0.5) * FRAME

# MARK: - 颜色


def srgb(hex_value):
    value = int(hex_value.lstrip("#"), 16)
    return np.array([(value >> 16) & 255, (value >> 8) & 255, value & 255], dtype=np.float64) / 255


def linear(hex_value):
    c = srgb(hex_value)
    c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    return (c[0], c[1], c[2], 1.0)


BIRD = {
    "gugu": dict(
        body="#A9D3F8", deep="#7FB2EC", tip="#5C8EDB", cream="#FFF4E2", feet="#B39484",
        iris_top="#1C2B5C", iris_bottom="#4F9BEF", pupil="#101A3A", beak="#FFCF6A", beak_deep="#F2A43C",
        brow="#3D4A78", line="#1E2547", blush="#FF9BAE",
    ),
    "gaga": dict(
        body="#D5C6F2", deep="#B7A2E8", tip="#9C82DA", cream="#FFF4E2", feet="#F7C45E",
        iris_top="#2A1F55", iris_bottom="#9A73E6", pupil="#1A1238", beak="#FFCF6A", beak_deep="#F2A43C",
        brow="#4B3F78", line="#241B47", blush="#FF9BAE",
    ),
}

# MARK: - 姿态
# 翅膀：(外, 前后, 上下, 翻转) 为翅尖方向——外为正、朝镜头为负——和绕翅轴的翻转角。
# 左右指画面左右。eyes: open/half/smile/closed；gaze 为瞳孔偏移；brow: 眉形；beak: closed/smile/open/o。

POSE = {
    "happy": dict(wings=dict(l=(0.42, -0.15, -1, 14), r=(0.42, -0.15, -1, 14)), eyes="open", beak="smile",
                  brow="soft", blink=True),
    "wave": dict(wings=dict(l=(0.36, -0.15, -1, 14), r=(0.62, -0.2, 1, 0)), eyes="open", beak="open", brow="soft",
                 blink=True, animated=["r"]),
    "point": dict(wings=dict(l=(0.36, -0.15, -1, 14), r=(1, -0.55, 0.2, -10)), eyes="open", beak="smile",
                  brow="soft", blink=True, gaze=(0.18, 0.04)),
    "celebrate": dict(wings=dict(l=(0.75, -0.15, 1, 0), r=(0.75, -0.15, 1, 0)), eyes="smile", beak="open",
                      brow="up", animated=["l", "r"]),
    "sleepy": dict(wings=dict(l=(0.18, -0.12, -1, 20), r=(0.18, -0.12, -1, 20)), eyes="closed", beak="closed",
                   brow="soft", tilt=6),
    "curious": dict(wings=dict(l=(0.36, -0.15, -1, 14), r=(0.7, -0.2, -0.75, 10)), eyes="open", beak="o",
                    brow="up", blink=True, tilt=-9, gaze=(0.12, 0.12), eye_scale=1.08),
    "thinking": dict(wings=dict(l=(0.32, -0.15, -1, 14), r=(-0.4, -0.42, -0.16, 8)), eyes="open", beak="closed",
                     brow="think", blink=True, tilt=5, gaze=(-0.16, 0.2)),
    "proud": dict(wings=dict(l=(0.62, 0.05, -0.75, 25), r=(0.62, 0.05, -0.75, 25)), eyes="smile", beak="smile",
                  brow="up", lean=-6),
    "pout": dict(wings=dict(l=(-0.72, -0.5, -0.26, 4), r=(-0.72, -0.62, -0.14, 4)), eyes="half", beak="closed",
                 brow="cross", blink=True, puff=True, tilt=-3),
    "care": dict(wings=dict(l=(-0.3, -0.5, -0.3, 10), r=(-0.3, -0.5, -0.3, 10)), eyes="smile", beak="smile",
                 brow="soft", star=True, blush=1.4),
}

# MARK: - 体型
# 身体是一个旋转体：底部 z=0.14，头顶 z=2.0；中段微收出脖子，头和肚子各鼓一圈。

BOTTOM, TOP = 0.09, 2.0
MID, HALF = (BOTTOM + TOP) / 2, (TOP - BOTTOM) / 2
EYE_Z = 1.39
EYE_X = 0.215


def gauss(t, c, w):
    return math.exp(-((t - c) / w) ** 2)


def profile(t, bird):
    head = 0.27 if bird == "gugu" else 0.29
    return 0.46 * (1 + head * gauss(t, 0.46, 0.36) - 0.03 * gauss(t, 0.02, 0.12) + 0.07 * gauss(t, -0.45, 0.36))


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for collection in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.curves):
        for item in list(collection):
            collection.remove(item)


def mesh_object(name, bm, parent=None, smooth=True, subsurf=1):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    if smooth:
        for polygon in mesh.polygons:
            polygon.use_smooth = True
    if subsurf:
        modifier = obj.modifiers.new("subsurf", "SUBSURF")
        modifier.levels = subsurf
        modifier.render_levels = subsurf + 1
    if parent:
        obj.parent = parent
    return obj


def sphere(segments=48, rings=24):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=1.0)
    return bm


def build_body(bird, root):
    bm = sphere(96, 64)
    for v in bm.verts:
        x, y, z = v.co
        rho = math.hypot(x, y)
        # 超椭圆截面：头顶和底部更圆钝，不像鸡蛋那样尖。
        power = 3.3 if z > 0 else 2.4
        radial = (1 - min(abs(z), 1) ** power) ** (1 / power)
        dx, dy = (x / rho, y / rho) if rho > 1e-6 else (0.0, 0.0)
        m = profile(z, bird) * radial
        depth = 0.9 if y < 0 else 0.95
        v.co = Vector((dx * m, dy * m * depth, MID + z * HALF))
    body = mesh_object("body", bm, root, subsurf=1)
    return body


# MARK: - 贴图（正面投影）


class Canvas:
    """在世界坐标的 x/z 平面上画抗锯齿形状，最后交给 Blender 作贴图。"""

    def __init__(self, width, height, x0, x1, z0, z1, color):
        self.w, self.h = width, height
        xs = x0 + (np.arange(width) + 0.5) / width * (x1 - x0)
        zs = z0 + (np.arange(height) + 0.5) / height * (z1 - z0)
        self.x, self.z = np.meshgrid(xs, zs)
        self.px = (x1 - x0) / width
        self.rgb = np.ones((height, width, 3)) * srgb(color)
        self.extra = np.zeros((height, width))

    def coverage(self, sdf, feather=1.2):
        return np.clip(0.5 - sdf / (self.px * feather), 0, 1)

    def paint(self, sdf, color, feather=1.2, opacity=1.0):
        a = self.coverage(sdf, feather)[..., None] * opacity
        self.rgb = self.rgb * (1 - a) + srgb(color) * a

    def glow(self, cx, cz, rx, rz, color, opacity):
        d = ((self.x - cx) / rx) ** 2 + ((self.z - cz) / rz) ** 2
        a = (np.exp(-d * 2.2) * opacity)[..., None]
        self.rgb = self.rgb * (1 - a) + srgb(color) * a

    def image(self, name, alpha=None):
        image = bpy.data.images.new(name, self.w, self.h, alpha=True)
        rgba = np.concatenate([self.rgb, (alpha if alpha is not None else np.ones((self.h, self.w)))[..., None]], 2)
        image.pixels.foreach_set(rgba.astype(np.float32).ravel())
        # alpha 只当光泽遮罩用，颜色不要跟着预乘变黑。
        image.alpha_mode = "CHANNEL_PACKED"
        image.pack()
        return image


def ellipse(c, cx, cz, rx, rz):
    return (np.sqrt(((c.x - cx) / rx) ** 2 + ((c.z - cz) / rz) ** 2) - 1) * min(rx, rz)


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b * (1 - h) + a * h - k * h * (1 - h)


def body_texture(bird, pose):
    colors = BIRD[bird]
    c = Canvas(1024, 1536, -0.75, 0.75, 0.0, 2.25, colors["body"])
    # 背光一侧和底部略深，像羽毛层次。
    c.glow(0, 0.2, 0.9, 0.5, colors["deep"], 0.25)
    if bird == "gugu":
        # 奶油色心形脸：两团围住眼睛，下缘包住喙和脸颊，中间额头留一道蓝色尖。
        mask = smin(ellipse(c, -0.2, 1.4, 0.26, 0.27), ellipse(c, 0.2, 1.4, 0.26, 0.27), 0.04)
        mask = smin(mask, ellipse(c, 0, 1.24, 0.37, 0.19), 0.1)
        c.paint(mask, colors["cream"], feather=1.6)
    else:
        # 嘎嘎：眼睛以下是奶油色毛绒脸颊，上缘带细碎绒毛。
        fluff = 0.012 * np.sin(c.x * 70) + 0.008 * np.sin(c.x * 131 + 1.3)
        mask = ellipse(c, 0, 1.17, 0.54, 0.19) + fluff
        c.paint(mask, colors["cream"], feather=1.6)
    # 肚皮。
    belly = ellipse(c, 0, 0.6, 0.37, 0.43)
    if bird == "gaga":
        belly = belly + 0.006 * np.sin(c.x * 90)
    c.paint(belly, colors["cream"], feather=1.6)
    blush = POSE[pose].get("blush", 1.0)
    for side in (-1, 1):
        c.glow(side * 0.34, 1.255, 0.1, 0.06, colors["blush"], 0.75 * blush)
    return c.image(f"{bird}-body")


def wing_texture(bird):
    colors = BIRD[bird]
    c = Canvas(256, 512, -0.25, 0.25, -0.7, 0.05, colors["body"])
    # 翅尖渐深，边界是三道羽毛扇贝。
    scallop = (c.z + 0.43 + 0.035 * np.cos(c.x * 38)) * 1.0
    c.paint(scallop, colors["tip"], feather=2.5)
    c.glow(0, -0.3, 0.3, 0.35, colors["deep"], 0.25)
    if bird == "gugu":
        c.paint(ellipse(c, 0.0, -0.2, 0.075, 0.1), colors["cream"], feather=2)
    return c.image(f"{bird}-wing")


def eye_texture(bird, mode, gaze):
    colors = BIRD[bird]
    c = Canvas(256, 320, -1, 1, -1, 1, "#FFFFFF")
    gx, gz = gaze
    iris = ellipse(c, gx, gz - 0.04, 0.8, 0.84)
    t = np.clip((c.z - (gz - 0.84)) / 1.68, 0, 1)[..., None]
    iris_color = srgb(colors["iris_bottom"]) * (1 - t) + srgb(colors["iris_top"]) * t
    a = c.coverage(iris)[..., None]
    c.rgb = c.rgb * (1 - a) + iris_color * a
    c.paint(ellipse(c, gx, gz - 0.06, 0.4, 0.46), colors["pupil"])
    # 下缘一弯亮色反光，让眼睛有水润感。
    c.glow(gx, gz - 0.55, 0.45, 0.16, "#BFE3FF" if bird == "gugu" else "#E3D2FF", 0.55)
    c.paint(ellipse(c, gx + 0.3, gz + 0.32, 0.27, 0.3), "#FFFFFF")
    c.paint(ellipse(c, gx - 0.3, gz - 0.38, 0.11, 0.11), "#FFFFFF")
    # 上眼线：贴着眼眶上缘的一道深色弧。
    rim = np.sqrt(c.x ** 2 + c.z ** 2)
    top = (c.z > -0.1)
    lash = np.where(top, np.abs(rim - 0.93) - 0.1 * np.clip((c.z + 0.1) / 0.6, 0, 1), 1)
    c.paint(lash, colors["line"], feather=2)
    gloss = np.ones((c.h, c.w))
    if mode == "half":
        lid_line = 0.12
        lid = (c.z - lid_line) * -1
        cover = c.coverage(lid, 2)
        body = srgb(BIRD[bird]["body"]) * 0.92
        c.rgb = c.rgb * (1 - cover[..., None]) + body * cover[..., None]
        c.paint(np.abs(c.z - lid_line) - 0.07, colors["line"], feather=2)
        gloss = 1 - cover
    return c.image(f"{bird}-eye-{mode}", alpha=gloss)


# MARK: - 材质


def principled(name, color=None, image=None, rough=0.55, sheen=0.35, sss=0.08, coat=0.0, coat_rough=0.08,
               projection=None, gloss_from_alpha=False, front_only_color=None):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes, links = material.node_tree.nodes, material.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Sheen Weight"].default_value = sheen
    bsdf.inputs["Sheen Roughness"].default_value = 0.45
    bsdf.inputs["Subsurface Weight"].default_value = sss
    bsdf.inputs["Subsurface Radius"].default_value = (0.6, 0.4, 0.3)
    bsdf.inputs["Subsurface Scale"].default_value = 0.05
    bsdf.inputs["Coat Weight"].default_value = coat
    bsdf.inputs["Coat Roughness"].default_value = coat_rough
    bsdf.inputs["Specular IOR Level"].default_value = 0.35
    if color is not None:
        bsdf.inputs["Base Color"].default_value = linear(color)
    if image is not None:
        coords = nodes.new("ShaderNodeTexCoord")
        separate = nodes.new("ShaderNodeSeparateXYZ")
        links.new(coords.outputs["Object"], separate.inputs[0])
        x0, x1, z0, z1 = projection
        u = nodes.new("ShaderNodeMapRange")
        u.inputs["From Min"].default_value, u.inputs["From Max"].default_value = x0, x1
        v = nodes.new("ShaderNodeMapRange")
        v.inputs["From Min"].default_value, v.inputs["From Max"].default_value = z0, z1
        links.new(separate.outputs["X"], u.inputs["Value"])
        links.new(separate.outputs["Z"], v.inputs["Value"])
        combine = nodes.new("ShaderNodeCombineXYZ")
        links.new(u.outputs["Result"], combine.inputs["X"])
        links.new(v.outputs["Result"], combine.inputs["Y"])
        texture = nodes.new("ShaderNodeTexImage")
        texture.image = image
        texture.extension = "EXTEND"
        texture.interpolation = "Cubic"
        links.new(combine.outputs[0], texture.inputs["Vector"])
        color_out = texture.outputs["Color"]
        if front_only_color is not None:
            # 只在朝前的一面投影图案，背面保持身体色。
            normal = nodes.new("ShaderNodeSeparateXYZ")
            links.new(coords.outputs["Normal"], normal.inputs[0])
            front = nodes.new("ShaderNodeMapRange")
            front.inputs["From Min"].default_value, front.inputs["From Max"].default_value = 0.05, -0.35
            links.new(normal.outputs["Y"], front.inputs["Value"])
            mix = nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            a = [s for s in mix.inputs if s.name == "A" and s.type == "RGBA"][0]
            b = [s for s in mix.inputs if s.name == "B" and s.type == "RGBA"][0]
            a.default_value = linear(front_only_color)
            links.new(front.outputs["Result"], mix.inputs["Factor"])
            links.new(color_out, b)
            color_out = [s for s in mix.outputs if s.type == "RGBA"][0]
        links.new(color_out, bsdf.inputs["Base Color"])
        if gloss_from_alpha:
            links.new(texture.outputs["Alpha"], bsdf.inputs["Coat Weight"])
    return material


def assign(obj, material):
    obj.data.materials.clear()
    obj.data.materials.append(material)


# MARK: - 部件


def surface(body, x, z, push=0.0):
    """从正前方打到身体表面，返回落点与法线（物体坐标）。"""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    ok, location, normal, _ = body.ray_cast(Vector((x, -5, z)), Vector((0, 1, 0)), depsgraph=depsgraph)
    if not ok:
        return Vector((x, -0.4, z)), Vector((0, -1, 0))
    return location + normal * push, normal


def tube(name, points, radius, color, parent, taper=None, material=None):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 6
    curve.use_fill_caps = True
    spline = curve.splines.new("NURBS")
    spline.points.add(len(points) - 1)
    for index, point in enumerate(points):
        spline.points[index].co = (point[0], point[1], point[2], 1)
        spline.points[index].radius = taper[index] if taper else 1
    spline.use_endpoint_u = True
    spline.order_u = min(4, len(points))
    obj = bpy.data.objects.new(name, curve)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = parent
    obj.data.materials.append(material or principled(name, color, rough=0.5, sheen=0, sss=0))
    return obj


def arc_on_face(body, cx, cz, half_width, bend, push, count=9):
    points = []
    for index in range(count):
        s = -1 + 2 * index / (count - 1)
        x = cx + s * half_width
        z = cz + bend * (1 - s * s)
        location, _ = surface(body, x, z, push)
        points.append(location)
    return points


def leaf(name, length, width, thickness, parent, material, pointy=1.0):
    bm = sphere(32, 20)
    for v in bm.verts:
        x, y, z = v.co
        t = (z + 1) / 2
        shape = math.sin(math.pi * min(max(t, 0), 1)) ** (0.35 * pointy)
        v.co = Vector((x * width * shape, y * thickness * shape, t * length))
    obj = mesh_object(name, bm, parent)
    assign(obj, material)
    return obj


def build_eyes(bird, body, pose):
    spec = POSE[pose]
    colors = BIRD[bird]
    mode = spec["eyes"]
    eyes = []
    scale = spec.get("eye_scale", 1.0)
    ex, ez = 0.128 * scale, 0.158 * scale
    if mode in ("open", "half"):
        material = principled(f"eye-{mode}", image=eye_texture(bird, mode, spec.get("gaze", (0, 0))),
                              rough=0.25, sheen=0, sss=0, coat=1.0, coat_rough=0.03,
                              projection=(-ex, ex, -ez, ez), gloss_from_alpha=(mode == "half"))
        for side in (-1, 1):
            location, normal = surface(body, side * EYE_X, EYE_Z, 0.0)
            bm = sphere(40, 24)
            for v in bm.verts:
                x, y, z = v.co
                v.co = Vector((x * ex, y * 0.05, z * ez))
            eye = mesh_object(f"eye-{side}", bm, body)
            # 让眼睛贴着脸的弧度：沿法线稍微转向两侧。
            yaw = math.atan2(normal.x, -normal.y)
            eye.matrix_basis = Matrix.Translation(location + normal * 0.022) @ Matrix.Rotation(-yaw, 4, "Z")
            assign(eye, material)
            eyes.append(eye)
            if bird == "gaga":
                # 外眼角两根上翘的睫毛。
                for k, (dx, dz, lift) in enumerate([(0.95, 0.55, 0.07), (1.05, 0.25, 0.05)]):
                    start = Vector((side * dx * ex, -0.03, dz * ez))
                    end = Vector((side * (dx * ex + 0.06), -0.03, dz * ez + lift))
                    mid = (start + end) / 2 + Vector((0, 0, 0.015))
                    tube(f"lash-{side}-{k}", [start, mid, end], 0.011, colors["line"], eye, taper=[1, 0.8, 0.2])
    else:
        # 弯弯的闭眼：smile 向上拱（^），closed 向下弯（‿）。
        bend = 0.055 if mode == "smile" else -0.045
        for side in (-1, 1):
            points = arc_on_face(body, side * EYE_X, EYE_Z - (0.0 if mode == "smile" else 0.02), 0.085, bend, 0.012)
            tube(f"closed-{side}", points, 0.017, colors["line"], body, taper=[0.4, 0.8, 1, 1, 1, 1, 1, 0.8, 0.4])
            if bird == "gaga" and mode == "closed":
                end = points[-1 if side > 0 else 0]
                tube(f"lash-{side}", [end, end + Vector((side * 0.04, -0.01, -0.03))], 0.01, colors["line"], body,
                     taper=[1, 0.3])
    return eyes


def build_brows(bird, body, pose):
    colors = BIRD[bird]
    style = POSE[pose]["brow"]
    base = EYE_Z + 0.215
    for side in (-1, 1):
        # (内端高度, 外端高度, 拱度)
        inner, outer, arch = {
            "soft": (0.0, 0.0, 0.018),
            "up": (0.03, 0.025, 0.022),
            "think": (0.04 if side < 0 else 0.0, 0.03 if side < 0 else -0.01, 0.02),
            "cross": (-0.035, 0.02, 0.0),
        }[style]
        points = []
        for index in range(7):
            s = index / 6
            x = side * (EYE_X - 0.065 + s * 0.13)
            z = base + inner * (1 - s) + outer * s + arch * math.sin(math.pi * s)
            location, _ = surface(body, x, z, 0.008)
            points.append(location)
        tube(f"brow-{side}", points, 0.012, colors["brow"], body, taper=[0.5, 0.9, 1, 1, 0.9, 0.7, 0.4])


def build_beak(bird, body, pose):
    colors = BIRD[bird]
    mode = POSE[pose]["beak"]
    location, normal = surface(body, 0, 1.265, -0.02)
    material = principled("beak", colors["beak"], rough=0.38, sheen=0.1, sss=0.15, coat=0.3)
    group = bpy.data.objects.new("beak", None)
    bpy.context.scene.collection.objects.link(group)
    group.parent = body
    group.matrix_basis = Matrix.Translation(location)

    def cone(name, radius, length, flat, droop, z_offset):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=32, radius1=radius, radius2=0.004, depth=length)
        for v in bm.verts:
            x, y, z = v.co
            # 圆锥沿 -Y（朝镜头）伸出。
            v.co = Vector((x, -(z + length / 2), y * flat))
        obj = mesh_object(name, bm, group, subsurf=2)
        obj.matrix_basis = Matrix.Translation((0, 0, z_offset)) @ Matrix.Rotation(math.radians(droop), 4, "X")
        assign(obj, material)
        return obj

    opening = {"closed": 0, "smile": 6, "open": 26, "o": 20}[mode]
    cone("beak-upper", 0.095, 0.13, 0.62, -14 + opening * 0.15, 0.008)
    cone("beak-lower", 0.075, 0.09, 0.5, 6 + opening, -0.018)
    if opening >= 6:
        mouth = sphere(24, 12)
        for v in mouth.verts:
            x, y, z = v.co
            v.co = Vector((x * 0.06, y * 0.035 - 0.02, z * 0.03 - 0.022 - opening * 0.0004))
        inner = mesh_object("mouth", mouth, group)
        assign(inner, principled("mouth", "#8C3140", rough=0.6, sheen=0, sss=0.2))
        if opening >= 20:
            tongue = sphere(20, 10)
            for v in tongue.verts:
                x, y, z = v.co
                v.co = Vector((x * 0.04, y * 0.03 - 0.035, z * 0.014 - 0.045))
            t = mesh_object("tongue", tongue, group)
            assign(t, principled("tongue", "#FF8C9E", rough=0.4, sheen=0, sss=0.3))


def wing_basis(side, direction, roll):
    """翅膀局部 -Z 指向翅尖，翅面尽量朝向镜头，再绕翅轴翻转 roll 度。"""
    dx, dy, dz = direction
    tip = Vector((side * dx, dy, dz)).normalized()
    z_axis = -tip
    reference = Vector((0, 1, 0))
    y_axis = reference - z_axis * reference.dot(z_axis)
    if y_axis.length < 1e-4:
        y_axis = Vector((0, 0, 1)) - z_axis * z_axis.z
    y_axis.normalize()
    x_axis = y_axis.cross(z_axis)
    basis = Matrix((x_axis, y_axis, z_axis)).transposed().to_4x4()
    return basis @ Matrix.Rotation(math.radians(side * roll), 4, "Z")


def build_wing(bird, body, side, pose_wing, material, tip_material):
    *direction, roll = pose_wing
    length, width, thickness = 0.66, 0.27, 0.06
    bm = sphere(48, 28)
    for v in bm.verts:
        x, y, z = v.co
        t = (z + 1) / 2  # 0 翅尖，1 根部
        profile_width = 0.5 + 0.62 * t - 0.2 * t * t
        bend = -0.05 * (1 - t) ** 2
        v.co = Vector((x * width * profile_width + bend * side, y * thickness * (0.6 + 0.5 * t), -length * (1 - t) + 0.04))
    wing = mesh_object(f"wing-{'l' if side < 0 else 'r'}", bm, body)
    assign(wing, material)
    shoulder = Vector((side * 0.43, -0.12, 1.1))
    wing.matrix_basis = Matrix.Translation(shoulder) @ wing_basis(side, direction, roll)
    # 翅尖三根小羽。
    for k, (dx, tilt, scale) in enumerate([(-0.07, -16, 0.78), (0.0, 0, 0.92), (0.07, 16, 0.78)]):
        feather = leaf(f"feather-{side}-{k}", 0.16 * scale, 0.05, 0.03, wing, tip_material, pointy=1.4)
        feather.matrix_basis = (
            Matrix.Translation((dx * side, 0.0, -length * 0.86))
            @ Matrix.Rotation(math.radians(180 + tilt * side), 4, "Y")
        )
    return wing, shoulder


def build_feet(bird, root):
    colors = BIRD[bird]
    material = principled("feet", colors["feet"], rough=0.5, sheen=0.05, sss=0.05)
    for side in (-1, 1):
        leg = sphere(20, 12)
        for v in leg.verts:
            x, y, z = v.co
            v.co = Vector((x * 0.045 + side * 0.17, y * 0.045, 0.1 + z * 0.08))
        assign(mesh_object(f"leg-{side}", leg, root), material)
        for k, yaw in enumerate((-28, 0, 28)):
            toe = sphere(20, 12)
            for v in toe.verts:
                x, y, z = v.co
                v.co = Vector((x * 0.036, y * 0.1 - 0.07, z * 0.03))
            obj = mesh_object(f"toe-{side}-{k}", toe, root)
            obj.matrix_basis = Matrix.Translation((side * 0.17, -0.02, 0.03)) @ Matrix.Rotation(math.radians(yaw + side * 8), 4, "Z")
            assign(obj, material)


def build_tail(bird, body, material):
    for k, (yaw, tilt, length) in enumerate([(-26, 58, 0.26), (0, 52, 0.3), (26, 58, 0.26)]):
        feather = leaf(f"tail-{k}", length, 0.07, 0.03, body, material, pointy=1.2)
        feather.matrix_basis = (
            Matrix.Translation((0, 0.38, 0.42))
            @ Matrix.Rotation(math.radians(yaw), 4, "Z")
            @ Matrix.Rotation(math.radians(180 - tilt), 4, "X")
        )


def build_crest(bird, body, material, tip_material):
    if bird == "gugu":
        # 头顶一撮向右卷起的呆毛。
        points = [(0.0, 0, 1.88), (-0.03, 0, 2.04), (0.0, 0, 2.16), (0.09, 0, 2.22), (0.17, 0, 2.18),
                  (0.18, 0, 2.1), (0.12, 0, 2.07)]
        crest = tube("crest", points, 0.11, None, body, taper=[1.0, 0.92, 0.75, 0.58, 0.45, 0.32, 0.18],
                     material=material)
        crest.scale = (1, 0.62, 1)
    else:
        # 两片叶形羽毛 + 中间一片小的。
        for k, (tilt, length, width) in enumerate([(-26, 0.42, 0.09), (26, 0.42, 0.09), (0, 0.28, 0.06)]):
            feather = leaf(f"tuft-{k}", length, width, 0.035, body, material, pointy=1.3)
            feather.matrix_basis = (
                Matrix.Translation((0, 0.02, 1.9))
                @ Matrix.Rotation(math.radians(tilt), 4, "Y")
                @ Matrix.Rotation(math.radians(-8), 4, "X")
            )
        # 两颊外翘的奶油色绒毛。
        cream = principled("ruff", BIRD[bird]["cream"], rough=0.7, sheen=0.5, sss=0.1)
        for side in (-1, 1):
            for k, (z, angle, length) in enumerate([(1.22, 112, 0.13), (1.13, 128, 0.1)]):
                tuft = leaf(f"ruff-{side}-{k}", length, 0.05, 0.035, body, cream, pointy=1.6)
                location, _ = surface(body, side * 0.44, z, -0.02)
                tuft.matrix_basis = Matrix.Translation(location) @ Matrix.Rotation(math.radians(-side * angle), 4, "Y")


def build_puff(bird, body):
    # 鼓起的腮帮：两团身体色小球贴在喙两侧。
    material = principled("puff", BIRD[bird]["cream"], rough=0.6, sheen=0.4, sss=0.1)
    for side in (-1, 1):
        location, _ = surface(body, side * 0.18, 1.23, -0.05)
        bm = sphere(24, 16)
        for v in bm.verts:
            x, y, z = v.co
            v.co = Vector((x * 0.1, y * 0.07, z * 0.08))
        obj = mesh_object(f"puff-{side}", bm, body)
        obj.matrix_basis = Matrix.Translation(location)
        assign(obj, material)


def build_star(body):
    bm = bmesh.new()
    outer, inner = 0.17, 0.075
    top = []
    bottom = []
    for index in range(10):
        r = outer if index % 2 == 0 else inner
        angle = math.pi / 2 + index * math.pi / 5
        top.append(bm.verts.new((math.cos(angle) * r, -0.03, math.sin(angle) * r)))
        bottom.append(bm.verts.new((math.cos(angle) * r, 0.03, math.sin(angle) * r)))
    front_center = bm.verts.new((0, -0.07, 0))
    back_center = bm.verts.new((0, 0.07, 0))
    for index in range(10):
        j = (index + 1) % 10
        bm.faces.new((front_center, top[j], top[index]))
        bm.faces.new((back_center, bottom[index], bottom[j]))
        bm.faces.new((top[index], top[j], bottom[j], bottom[index]))
    star = mesh_object("star", bm, body, smooth=False, subsurf=0)
    bevel = star.modifiers.new("bevel", "BEVEL")
    bevel.width = 0.012
    bevel.segments = 3
    star.matrix_basis = Matrix.Translation((0, -0.62, 0.8)) @ Matrix.Rotation(math.radians(-8), 4, "Y")
    assign(star, principled("star", "#FFD35A", rough=0.3, sheen=0, sss=0, coat=0.8))


# MARK: - 场景


def setup_scene():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    preferences = bpy.context.preferences.addons["cycles"].preferences
    preferences.compute_device_type = "METAL"
    preferences.get_devices()
    for device in preferences.devices:
        device.use = True
    scene.cycles.device = "GPU"
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.render.resolution_x = scene.render.resolution_y = RES
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0
    world = bpy.data.worlds.new("world")
    world.use_nodes = True
    background = world.node_tree.nodes["Background"]
    background.inputs["Color"].default_value = linear("#E8EEFF")
    background.inputs["Strength"].default_value = 0.35
    scene.world = world

    camera_data = bpy.data.cameras.new("camera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = FRAME
    camera = bpy.data.objects.new("camera", camera_data)
    scene.collection.objects.link(camera)
    pitch = math.radians(5)
    camera.location = (0, -12 * math.cos(pitch), CENTER_Z + 12 * math.sin(pitch))
    camera.rotation_euler = (math.pi / 2 - pitch, 0, 0)
    scene.camera = camera

    def area(name, location, energy, size, color="#FFFFFF"):
        light_data = bpy.data.lights.new(name, "AREA")
        light_data.energy = energy
        light_data.size = size
        light_data.color = linear(color)[:3]
        light = bpy.data.objects.new(name, light_data)
        light.location = location
        direction = Vector((0, 0, 1.0)) - Vector(location)
        light.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(light)

    area("key", (-3.5, -5.5, 5.5), 440, 4.5, "#FFF6EA")
    area("fill", (5, -4.5, 1.8), 175, 5, "#DDE6FF")
    area("rim", (2.5, 5, 4.5), 380, 3, "#FFFFFF")
    area("bounce", (0, -3, -3), 40, 6, "#FFF2DC")


def build_bird(bird, pose, hidden_wings=(), solo_wing=None):
    spec = POSE[pose]
    colors = BIRD[bird]
    root = bpy.data.objects.new("root", None)
    bpy.context.scene.collection.objects.link(root)
    root.rotation_euler = (0, 0, math.radians(-8))
    body = build_body(bird, root)
    body_material = principled("body", image=body_texture(bird, pose), rough=0.62, sheen=0.45, sss=0.1,
                               projection=(-0.75, 0.75, 0.0, 2.25), front_only_color=colors["body"])
    assign(body, body_material)
    bpy.context.view_layer.update()

    feather_material = principled("feather", colors["body"], rough=0.6, sheen=0.4, sss=0.08)
    tip_material = principled("tip", colors["tip"], rough=0.55, sheen=0.35, sss=0.05)
    wing_material = principled("wing", image=wing_texture(bird), rough=0.6, sheen=0.4, sss=0.08,
                               projection=(-0.25, 0.25, -0.7, 0.05))
    build_eyes(bird, body, pose)
    build_brows(bird, body, pose)
    build_beak(bird, body, pose)
    build_crest(bird, body, feather_material, tip_material)
    build_tail(bird, body, tip_material)
    if spec.get("puff"):
        build_puff(bird, body)
    if spec.get("star"):
        build_star(body)
    build_feet(bird, root)
    wings = {}
    for key, side in (("l", -1), ("r", 1)):
        wing, shoulder = build_wing(bird, body, side, spec["wings"][key], wing_material, tip_material)
        wings[key] = (wing, shoulder)
    # 身体姿态：tilt 绕视线轴歪头，lean 前后仰；以脚底为支点。
    body.matrix_basis = (
        Matrix.Rotation(math.radians(spec.get("tilt", 0)), 4, "Y")
        @ Matrix.Rotation(math.radians(spec.get("lean", 0)), 4, "X")
    )
    bpy.context.view_layer.update()

    def family(obj):
        result = [obj]
        for child in obj.children:
            result += family(child)
        return result

    for key in hidden_wings:
        for obj in family(wings[key][0]):
            obj.hide_render = True
    if solo_wing:
        keep = set(family(wings[solo_wing][0]))
        for obj in bpy.context.scene.objects:
            if obj.type in ("MESH", "CURVE") and obj not in keep:
                obj.is_holdout = True
    pivots = {}
    for key, (wing, shoulder) in wings.items():
        world = body.matrix_world @ shoulder
        co = world_to_camera_view(bpy.context.scene, bpy.context.scene.camera, world)
        pivots[key] = [round(co.x, 4), round(1 - co.y, 4)]
    return pivots


def render(name):
    bpy.context.scene.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    manifest_path = os.path.join(OUT, "manifest.json")
    manifest = json.load(open(manifest_path)) if os.path.exists(manifest_path) else {}
    for bird in BIRDS:
        for pose in POSES:
            spec = POSE[pose]
            animated = spec.get("animated", [])
            variants = [("", None)]
            if spec.get("blink"):
                variants.append(("-blink", "closed"))
            for suffix, eyes in variants:
                reset()
                setup_scene()
                if eyes:
                    original = spec["eyes"]
                    spec["eyes"] = eyes
                pivots = build_bird(bird, pose, hidden_wings=animated)
                if eyes:
                    spec["eyes"] = original
                render(f"{bird}-{pose}{suffix}")
            for key in animated:
                reset()
                setup_scene()
                build_bird(bird, pose, solo_wing=key)
                render(f"{bird}-{pose}-wing-{key}")
            manifest[f"{bird}-{pose}"] = {"pivots": pivots, "animated": animated, "blink": bool(spec.get("blink"))}
    json.dump(manifest, open(manifest_path, "w"), indent=1, sort_keys=True)


main()
