#!/usr/bin/env python3
"""Растеризатор с z-буфером: рисует сцены из примитивов Roblox в PNG.

Нужен для предпросмотра моделей, анимаций и карт без Roblox Studio.
Сцену готовят скрипты lune/shooter-view.luau и lune/shooter-map.luau:
все примитивы уже в координатах камеры (камера в нуле, смотрит вдоль -Z, +Y вверх).

Запуск: render.py scene.json out.png   (нужны numpy и pillow)
"""
import json
import math
import sys

import numpy as np
from PIL import Image, ImageDraw

SS = 2  # сглаживание: рисуем в двойном разрешении
NEAR = 0.05
LIGHT = np.array([-0.35, 0.8, 0.5])
LIGHT = LIGHT / np.linalg.norm(LIGHT)


def local_faces(shape, size):
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    if shape == "Ball":
        r = min(hx, hy, hz)
        lat, lon = 8, 12

        def pt(i, j):
            th, ph = math.pi * i / lat, 2 * math.pi * j / lon
            return (r * math.sin(th) * math.cos(ph), r * math.cos(th), r * math.sin(th) * math.sin(ph))

        return [[pt(i, j), pt(i, j + 1), pt(i + 1, j + 1), pt(i + 1, j)] for i in range(lat) for j in range(lon)]
    if shape == "Cylinder":  # ось вдоль локальной X, как у деталей Roblox
        n = 14
        ring = [(math.cos(2 * math.pi * k / n), math.sin(2 * math.pi * k / n)) for k in range(n)]
        faces = []
        for k in range(n):
            (c0, s0), (c1, s1) = ring[k], ring[(k + 1) % n]
            faces.append([(-hx, hy * c0, hz * s0), (hx, hy * c0, hz * s0), (hx, hy * c1, hz * s1), (-hx, hy * c1, hz * s1)])
        faces.append([(hx, hy * c, hz * s) for c, s in ring])
        faces.append([(-hx, hy * c, hz * s) for c, s in ring])
        return faces

    def v(x, y, z):
        return (x * hx, y * hy, z * hz)

    if shape == "Wedge":  # высокая стенка на +Z, скат спускается к -Z
        return [
            [v(-1, -1, -1), v(1, -1, -1), v(1, -1, 1), v(-1, -1, 1)],
            [v(-1, -1, 1), v(1, -1, 1), v(1, 1, 1), v(-1, 1, 1)],
            [v(-1, -1, -1), v(1, -1, -1), v(1, 1, 1), v(-1, 1, 1)],
            [v(-1, -1, -1), v(-1, -1, 1), v(-1, 1, 1)],
            [v(1, -1, -1), v(1, -1, 1), v(1, 1, 1)],
        ]
    return [
        [v(-1, -1, -1), v(1, -1, -1), v(1, 1, -1), v(-1, 1, -1)],
        [v(-1, -1, 1), v(1, -1, 1), v(1, 1, 1), v(-1, 1, 1)],
        [v(-1, -1, -1), v(-1, -1, 1), v(-1, 1, 1), v(-1, 1, -1)],
        [v(1, -1, -1), v(1, -1, 1), v(1, 1, 1), v(1, 1, -1)],
        [v(-1, 1, -1), v(1, 1, -1), v(1, 1, 1), v(-1, 1, 1)],
        [v(-1, -1, -1), v(1, -1, -1), v(1, -1, 1), v(-1, -1, 1)],
    ]


def clip_near(points):
    """Отсекает многоугольник плоскостью z = -NEAR (остаётся то, что перед камерой)."""
    result = []
    count = len(points)
    for i in range(count):
        a, b = points[i], points[(i + 1) % count]
        a_in, b_in = a[2] <= -NEAR, b[2] <= -NEAR
        if a_in:
            result.append(a)
        if a_in != b_in:
            t = (-NEAR - a[2]) / (b[2] - a[2])
            result.append(a + (b - a) * t)
    return result


class Frame:
    def __init__(self, spec, width, height, background):
        self.w, self.h = width, height
        self.ortho = spec.get("ortho")
        self.tan = math.tan(math.radians(spec.get("fov", 70)) / 2)
        self.aspect = width / height
        self.img = np.empty((height, width, 3), dtype=np.float32)
        self.img[:] = background
        self.zbuf = np.full((height, width), -np.inf, dtype=np.float32)

    def project(self, p):
        """Точка в координатах камеры -> (x, y) в пикселях и «близость» (больше = ближе)."""
        if self.ortho:
            x, y, near = p[0] / (self.ortho * self.aspect), p[1] / self.ortho, p[2]
        else:
            d = -p[2]
            x, y, near = p[0] / (d * self.tan * self.aspect), p[1] / (d * self.tan), 1 / d
        return (x + 1) / 2 * self.w, (1 - y) / 2 * self.h, near

    def triangle(self, pts, color, alpha):
        (x0, y0, n0), (x1, y1, n1), (x2, y2, n2) = pts
        min_x = max(int(math.floor(min(x0, x1, x2))), 0)
        max_x = min(int(math.ceil(max(x0, x1, x2))), self.w - 1)
        min_y = max(int(math.floor(min(y0, y1, y2))), 0)
        max_y = min(int(math.ceil(max(y0, y1, y2))), self.h - 1)
        if min_x > max_x or min_y > max_y:
            return
        area = (x2 - x0) * (y1 - y0) - (y2 - y0) * (x1 - x0)
        if abs(area) < 1e-9:
            return
        xs, ys = np.meshgrid(np.arange(min_x, max_x + 1) + 0.5, np.arange(min_y, max_y + 1) + 0.5)
        w0 = ((xs - x1) * (y2 - y1) - (ys - y1) * (x2 - x1)) / area
        w1 = ((xs - x2) * (y0 - y2) - (ys - y2) * (x0 - x2)) / area
        w2 = 1 - w0 - w1
        near = w0 * n0 + w1 * n1 + w2 * n2
        zsub = self.zbuf[min_y : max_y + 1, min_x : max_x + 1]
        mask = (w0 >= 0) & (w1 >= 0) & (w2 >= 0) & (near > zsub)
        if not mask.any():
            return
        sub = self.img[min_y : max_y + 1, min_x : max_x + 1]
        if alpha >= 1:
            zsub[mask] = near[mask]
            sub[mask] = color
        else:
            sub[mask] = sub[mask] * (1 - alpha) + color * alpha

    def draw(self, prims):
        opaque, blended = [], []
        for prim in prims:
            cf = prim["cf"]
            pos = np.array(cf[:3], dtype=np.float64)
            rot = np.array(cf[3:], dtype=np.float64).reshape(3, 3)
            color = np.array(prim["color"], dtype=np.float32)
            alpha = prim.get("alpha", 1)
            for face in local_faces(prim.get("shape", "Block"), prim["size"]):
                pts = np.array(face, dtype=np.float64) @ rot.T + pos
                normal = np.cross(pts[1] - pts[0], pts[2] - pts[0])
                length = np.linalg.norm(normal)
                if length < 1e-12:
                    continue
                normal /= length
                view = np.array([0.0, 0.0, 1.0]) if self.ortho else -pts.mean(axis=0)
                if np.dot(normal, view) < 0:
                    normal = -normal
                shade = 0.5 + 0.5 * max(0.0, float(np.dot(normal, LIGHT)))
                poly = list(pts) if self.ortho else clip_near(list(pts))
                if len(poly) < 3:
                    continue
                screen = [self.project(p) for p in poly]
                target = opaque if alpha >= 1 else blended
                for k in range(1, len(screen) - 1):
                    target.append(((screen[0], screen[k], screen[k + 1]), color * shade, alpha))
        for pts, color, alpha in opaque:
            self.triangle(pts, color, alpha)
        blended.sort(key=lambda item: sum(p[2] for p in item[0]))
        for pts, color, alpha in blended:
            self.triangle(pts, color, alpha)


def render(scene, out_path):
    width, height = scene.get("width", 480), scene.get("height", 270)
    background = np.array(scene.get("background", [150, 170, 190]), dtype=np.float32)
    frames = scene["frames"]
    cols = max(1, min(scene.get("cols", 4), len(frames)))
    rows = math.ceil(len(frames) / cols)
    sheet = Image.new("RGB", (cols * width, rows * height), (0, 0, 0))
    for index, spec in enumerate(frames):
        big = Frame(spec, width * SS, height * SS, background)
        big.draw(spec.get("prims", []))
        image = Image.fromarray(np.clip(big.img, 0, 255).astype(np.uint8)).resize((width, height), Image.LANCZOS)
        final = Frame(spec, width, height, background)
        pen = ImageDraw.Draw(image)
        for dot in spec.get("dots", []):
            p = dot["p"]
            if final.ortho or p[2] < -NEAR:
                x, y, _ = final.project(p)
                r = dot.get("r", 1)
                pen.rectangle([x - r, y - r, x + r, y + r], fill=tuple(int(c) for c in dot["color"]))
        for label in spec.get("labels", []):
            p = label["p"]
            if final.ortho or p[2] < -NEAR:
                x, y, _ = final.project(p)
                text = label["text"]
                color = tuple(int(c) for c in label.get("color", [255, 255, 255]))
                pen.rectangle([x - 2, y - 2, x + 2, y + 2], fill=color)
                pen.text((x + 5, y - 5), text, fill=(0, 0, 0))
                pen.text((x + 4, y - 6), text, fill=color)
        if spec.get("label"):
            pen.text((7, 5), spec["label"], fill=(0, 0, 0))
            pen.text((6, 4), spec["label"], fill=(255, 255, 255))
        sheet.paste(image, ((index % cols) * width, (index // cols) * height))
    sheet.save(out_path)


if __name__ == "__main__":
    with open(sys.argv[1], encoding="utf-8") as handle:
        render(json.load(handle), sys.argv[2])
