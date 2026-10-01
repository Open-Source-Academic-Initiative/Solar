#!/usr/bin/env python3
"""Build a looping cartoon solar system in Blender 5.2.

Stylised, not to scale: a smiling Sun with spinning rays, eight cel-shaded
planets with ink outlines, the Moon, Saturn's rings, an asteroid belt, dashed
orbits and a starry sky. Every orbit completes an integer number of turns in
LOOP_FRAMES, so the animation loops seamlessly.

Shading is emission-only. Each planet computes its own day/night terminator as
dot(normal, direction to the Sun) through a constant colour ramp, so the look is
identical in EEVEE and independent of light falloff. Outlines are inverted
hulls (Solidify, flipped normals, back-face culled ink material).

Runs in the persistent MCP session and replaces the current scene contents. It
writes a `.blend` copy plus a JSON manifest into an empty artifact directory;
rendering is left to the MCP render tools.

    blender_run_project_script build_solar_system.py -- --output-dir <empty dir>
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import random
import sys
from pathlib import Path
from typing import Any

import bmesh
import bpy
import mathutils

BLENDER_MCP_RESULT: dict[str, Any] | None = None

WIDTH, HEIGHT = 1920, 1080
FPS = 24
LOOP_FRAMES = 480  # 20 s
FRAME_START = 1
FRAME_END = FRAME_START + LOOP_FRAMES - 1

INK = (0.012, 0.010, 0.035)
SUN_RADIUS = 1.6

# name, radius, orbit distance, orbits per loop, start angle (deg),
# spins per loop, axial tilt (deg), pattern
PLANETS = [
    ("Mercurio", 0.34, 3.7, 8, 20, 4, 0, "mercury"),
    ("Venus", 0.55, 5.1, 6, 140, -3, 3, "venus"),
    ("Tierra", 0.60, 6.8, 5, 250, 10, 23, "earth"),
    ("Marte", 0.45, 8.3, 4, 330, 10, 25, "mars"),
    ("Jupiter", 1.45, 11.8, 3, 60, 16, 3, "jupiter"),
    ("Saturno", 1.15, 14.9, 2, 200, 14, 24, "saturn"),
    ("Urano", 0.85, 17.5, 1, 300, -8, 97, "uranus"),
    ("Neptuno", 0.82, 19.7, 1, 110, 8, 28, "neptune"),
]
BELT = (9.4, 10.1)  # asteroid belt inner/outer radius


def srgb(hex_code: str) -> tuple[float, float, float, float]:
    """Hex sRGB to linear RGBA (Blender colour sockets are linear)."""
    hex_code = hex_code.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(hex_code[i : i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (*out, 1.0)


# --- helpers ----------------------------------------------------------------


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    own = argv[argv.index("--") + 1 :] if "--" in argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", required=True)
    return parser.parse_args(own)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sock(sockets: Any, identifier: str) -> Any:
    for s in sockets:
        if s.identifier == identifier:
            return s
    raise KeyError(identifier)


class Graph:
    """Tiny node-tree builder for readable shader code."""

    def __init__(self, tree: Any) -> None:
        self.tree = tree
        self.nodes = tree.nodes
        self.links = tree.links
        self.nodes.clear()
        self.x = 0

    def node(self, kind: str, **props: Any) -> Any:
        n = self.nodes.new(kind)
        n.location = (self.x, 0)
        self.x += 200
        for key, value in props.items():
            setattr(n, key, value)
        return n

    def link(self, a: Any, b: Any) -> None:
        self.links.new(a, b)

    def math(self, op: str, a: Any, b: Any = None) -> Any:
        n = self.node("ShaderNodeMath", operation=op)
        for i, v in enumerate((a, b)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                n.inputs[i].default_value = v
            else:
                self.link(v, n.inputs[i])
        return n.outputs[0]

    def vmath(self, op: str, a: Any, b: Any = None, scale: float | None = None) -> Any:
        n = self.node("ShaderNodeVectorMath", operation=op)
        for i, v in enumerate((a, b)):
            if v is None:
                continue
            if isinstance(v, (tuple, list)):
                n.inputs[i].default_value = v
            else:
                self.link(v, n.inputs[i])
        if scale is not None:
            sock(n.inputs, "Scale").default_value = scale
        return n.outputs["Value"] if op in {"DOT_PRODUCT", "LENGTH", "DISTANCE"} else n.outputs["Vector"]

    def ramp(self, fac: Any, stops: list[tuple[float, tuple]], constant: bool = True) -> Any:
        n = self.node("ShaderNodeValToRGB")
        cr = n.color_ramp
        cr.interpolation = "CONSTANT" if constant else "LINEAR"
        els = cr.elements
        while len(els) > 1:
            els.remove(els[-1])
        els[0].position = stops[0][0]
        els[0].color = stops[0][1]
        for pos, col in stops[1:]:
            e = els.new(pos)
            e.color = col
        self.link(fac, n.inputs["Fac"])
        return n.outputs["Color"]

    def mix(self, fac: Any, a: Any, b: Any, blend: str = "MIX") -> Any:
        n = self.node("ShaderNodeMix", data_type="RGBA", blend_type=blend)
        f = sock(n.inputs, "Factor_Float")
        if isinstance(fac, (int, float)):
            f.default_value = fac
        else:
            self.link(fac, f)
        for ident, v in (("A_Color", a), ("B_Color", b)):
            if isinstance(v, tuple):
                sock(n.inputs, ident).default_value = v
            else:
                self.link(v, sock(n.inputs, ident))
        return sock(n.outputs, "Result_Color")

    def emit(self, color: Any, strength: float = 1.0) -> Any:
        n = self.node("ShaderNodeEmission")
        if isinstance(color, tuple):
            n.inputs["Color"].default_value = color
        else:
            self.link(color, n.inputs["Color"])
        n.inputs["Strength"].default_value = strength
        return n.outputs["Emission"]

    def output(self, shader: Any) -> None:
        out = self.node("ShaderNodeOutputMaterial")
        self.link(shader, out.inputs["Surface"])


def new_material(name: str) -> tuple[Any, Graph]:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    return mat, Graph(mat.node_tree)


def obj_coords(g: Graph, radius: float) -> Any:
    """Object-space coordinates normalised to the unit sphere."""
    tc = g.node("ShaderNodeTexCoord")
    return g.vmath("SCALE", tc.outputs["Object"], scale=1.0 / radius)


def toon_shade(g: Graph, base: Any) -> Any:
    """Cel-shade `base` with a terminator facing the Sun at the origin."""
    geo = g.node("ShaderNodeNewGeometry")
    to_sun = g.vmath("NORMALIZE", g.vmath("SCALE", geo.outputs["Position"], scale=-1.0))
    ndl = g.vmath("DOT_PRODUCT", geo.outputs["Normal"], to_sun)
    fac = g.math("MULTIPLY_ADD", ndl, 0.5)
    sock_in = fac.node.inputs[2]
    sock_in.default_value = 0.5  # (n.l) * 0.5 + 0.5
    band = g.ramp(
        fac,
        [
            (0.0, srgb("5550a0")),  # night side: cool violet
            (0.46, srgb("b4acdf")),  # soft terminator band
            (0.53, (1, 1, 1, 1)),  # day
            (0.86, srgb("fff6e0")),  # sunlit highlight
        ],
    )
    lit = g.mix(1.0, base, band, blend="MULTIPLY")
    # Hot highlight cap pushes the brightest band a touch over white.
    cap = g.math("GREATER_THAN", fac, 0.86)
    lit = g.mix(g.math("MULTIPLY", cap, 0.18), lit, (1, 1, 1, 1))
    # Cartoon rim light on the silhouette.
    lw = g.node("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.35
    rim = g.math("GREATER_THAN", lw.outputs["Facing"], 0.9)
    lit = g.mix(g.math("MULTIPLY", rim, 0.35), lit, srgb("9fd8ff"))
    return g.emit(lit)


# --- planet surface patterns --------------------------------------------------


def bands(g: Graph, co: Any, stops: list[tuple[float, str]], wobble: float, scale: float = 2.0) -> Any:
    xyz = g.node("ShaderNodeSeparateXYZ")
    g.link(co, xyz.inputs[0])
    noise = g.node("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = scale
    noise.inputs["Detail"].default_value = 1.0
    g.link(co, noise.inputs["Vector"])
    warp = g.math("MULTIPLY_ADD", noise.outputs["Fac"], wobble)
    warp.node.inputs[2].default_value = -wobble * 0.5
    z = g.math("ADD", xyz.outputs["Z"], warp)
    fac = g.math("MULTIPLY_ADD", z, 0.5)
    fac.node.inputs[2].default_value = 0.5
    return g.ramp(fac, [(p, srgb(c)) for p, c in stops])


def blotches(g: Graph, co: Any, scale: float, stops: list[tuple[float, str]]) -> Any:
    noise = g.node("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = scale
    noise.inputs["Detail"].default_value = 2.0
    noise.inputs["Roughness"].default_value = 0.45
    g.link(co, noise.inputs["Vector"])
    return g.ramp(noise.outputs["Fac"], [(p, srgb(c)) for p, c in stops])


def spot(g: Graph, co: Any, base: Any, center: tuple, radius: float, color: str, ring: str | None = None) -> Any:
    dist = g.vmath("DISTANCE", co, center)
    if ring:
        base = g.mix(g.math("LESS_THAN", dist, radius * 1.3), base, srgb(ring))
    return g.mix(g.math("LESS_THAN", dist, radius), base, srgb(color))


def caps(g: Graph, co: Any, base: Any, level: float, color: str) -> Any:
    xyz = g.node("ShaderNodeSeparateXYZ")
    g.link(co, xyz.inputs[0])
    noise = g.node("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 3.0
    g.link(co, noise.inputs["Vector"])
    z = g.math("ADD", g.math("ABSOLUTE", xyz.outputs["Z"]), g.math("MULTIPLY", noise.outputs["Fac"], 0.12))
    return g.mix(g.math("GREATER_THAN", z, level), base, srgb(color))


def craters(g: Graph, co: Any, base: Any, scale: float, color: str, size: float) -> Any:
    vor = g.node("ShaderNodeTexVoronoi")
    vor.inputs["Scale"].default_value = scale
    vor.inputs["Randomness"].default_value = 0.9
    g.link(co, vor.inputs["Vector"])
    keep = g.math("GREATER_THAN", vor.outputs["Color"], 0.55)  # only some cells
    hole = g.math("LESS_THAN", vor.outputs["Distance"], size)
    return g.mix(g.math("MULTIPLY", keep, hole), base, srgb(color))


def planet_base(g: Graph, pattern: str, radius: float) -> Any:
    co = obj_coords(g, radius)
    if pattern == "mercury":
        base = blotches(g, co, 3.5, [(0.0, "8d8a93"), (0.52, "b3aeb8"), (0.66, "cfcad3")])
        return craters(g, co, base, 5.0, "6f6b78", 0.22)
    if pattern == "venus":
        return bands(g, co, [(0.0, "e8b35a"), (0.3, "f3cf7e"), (0.55, "f8e1a0"), (0.78, "efc26a")], 0.5, 1.6)
    if pattern == "earth":
        base = blotches(g, co, 2.2, [(0.0, "2f7fe0"), (0.5, "3a9bf0"), (0.535, "5dc15a"), (0.64, "3e9a44")])
        return caps(g, co, base, 0.84, "f4fbff")
    if pattern == "mars":
        base = blotches(g, co, 3.0, [(0.0, "c9502e"), (0.5, "e0673a"), (0.63, "a33e25")])
        return caps(g, co, base, 0.9, "fff1ea")
    if pattern == "jupiter":
        base = bands(
            g,
            co,
            [
                (0.0, "c9a27e"), (0.14, "f1dcc0"), (0.26, "c98a5b"), (0.36, "f6e7cf"),
                (0.46, "d9a071"), (0.56, "f7ead6"), (0.66, "c47f52"), (0.78, "efd7b8"),
                (0.9, "b98d6b"),
            ],
            0.22,
            2.5,
        )
        return spot(g, co, base, (0.72, -0.55, -0.38), 0.24, "d9482f", ring="f1b58f")
    if pattern == "saturn":
        return bands(
            g,
            co,
            [(0.0, "d9b779"), (0.2, "f2dca6"), (0.35, "e2c285"), (0.5, "f7e7bd"), (0.66, "dcb775"), (0.82, "f0d9a2")],
            0.12,
            2.0,
        )
    if pattern == "uranus":
        return bands(g, co, [(0.0, "7fd8de"), (0.4, "9fe8ea"), (0.62, "b8f1f0")], 0.1, 1.5)
    if pattern == "neptune":
        base = bands(g, co, [(0.0, "2f5fd9"), (0.3, "4a7ef0"), (0.5, "3a68e2"), (0.72, "5b8ff5")], 0.3, 2.0)
        return spot(g, co, base, (0.8, 0.3, 0.45), 0.2, "1f3fa8")
    raise ValueError(pattern)


# --- geometry ---------------------------------------------------------------


def link(obj: Any, parent: Any = None) -> Any:
    bpy.context.scene.collection.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    return obj


def empty(name: str, parent: Any = None, location=(0, 0, 0)) -> Any:
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = 0.5
    e.location = location
    return link(e, parent)


def mesh_object(name: str, bm: Any, parent: Any = None, smooth: bool = True) -> Any:
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    if smooth:
        me.shade_smooth()
    return link(bpy.data.objects.new(name, me), parent)


def sphere(name: str, radius: float, parent: Any = None, segments: int = 64) -> Any:
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=segments // 2, radius=radius)
    return mesh_object(name, bm, parent)


def outline(obj: Any, ink: Any, thickness: float) -> None:
    obj.data.materials.append(ink)
    mod = obj.modifiers.new("Contorno", "SOLIDIFY")
    mod.thickness = thickness
    mod.offset = 1.0
    mod.use_flip_normals = True
    mod.use_rim = False
    mod.use_even_offset = True
    mod.material_offset = 1


def keyframes(obj: Any, path: str, index: int, points: list[tuple[int, float]], interp: str) -> None:
    for frame, value in points:
        getattr(obj, path)[index] = value
        obj.keyframe_insert(path, index=index, frame=frame)
    ad = obj.animation_data
    bag = ad.action.layers[0].strips[0].channelbag(ad.action_slot)
    for fc in bag.fcurves:
        if fc.data_path == path and fc.array_index == index:
            for kp in fc.keyframe_points:
                kp.interpolation = interp


def spin(obj: Any, path: str, index: int, start: float, turns: float) -> None:
    keyframes(
        obj,
        path,
        index,
        [(FRAME_START, start), (FRAME_END + 1, start + turns * 2 * math.pi)],
        "LINEAR",
    )


# --- scene parts ------------------------------------------------------------


def make_ink() -> Any:
    ink, g = new_material("Tinta")
    g.output(g.emit((*INK[:3], 1.0)))
    ink.use_backface_culling = True
    return ink


def build_world(scene: Any) -> None:
    world = bpy.data.worlds.new("Cielo_Cartoon")
    scene.world = world
    world.use_nodes = True
    g = Graph(world.node_tree)
    tc = g.node("ShaderNodeTexCoord")
    direction = g.vmath("NORMALIZE", tc.outputs["Generated"])
    xyz = g.node("ShaderNodeSeparateXYZ")
    g.link(direction, xyz.inputs[0])
    height = g.math("MULTIPLY_ADD", xyz.outputs["Z"], 0.5)
    height.node.inputs[2].default_value = 0.5
    sky = g.ramp(
        height,
        [(0.0, srgb("0b0a24")), (0.45, srgb("141038")), (0.75, srgb("22134a")), (1.0, srgb("2e1656"))],
        constant=False,
    )
    color = sky
    for scale, size, keep, tint in ((70.0, 0.09, 0.55, "fff6d8"), (160.0, 0.07, 0.4, "cfe2ff"), (32.0, 0.06, 0.8, "ffe38a")):
        vor = g.node("ShaderNodeTexVoronoi")
        vor.inputs["Scale"].default_value = scale
        g.link(direction, vor.inputs["Vector"])
        star = g.math(
            "MULTIPLY",
            g.math("LESS_THAN", vor.outputs["Distance"], size),
            g.math("GREATER_THAN", vor.outputs["Color"], keep),
        )
        color = g.mix(star, color, srgb(tint))
    bg = g.node("ShaderNodeBackground")
    g.link(color, bg.inputs["Color"])
    out = g.node("ShaderNodeOutputWorld")
    g.link(bg.outputs["Background"], out.inputs["Surface"])


def star_polygon(points: int, r_in: float, r_out: float, y: float) -> Any:
    bm = bmesh.new()
    center = bm.verts.new((0, y, 0))
    ring = []
    for i in range(points * 2):
        a = math.pi * i / points
        r = r_out if i % 2 == 0 else r_in
        ring.append(bm.verts.new((r * math.cos(a), y, r * math.sin(a))))
    for i in range(len(ring)):
        bm.faces.new((center, ring[(i + 1) % len(ring)], ring[i]))
    return bm


def build_sun(ink: Any) -> dict[str, Any]:
    sun = sphere("Sol", SUN_RADIUS, segments=96)
    mat, g = new_material("Sol_Toon")
    lw = g.node("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.5
    col = g.ramp(
        lw.outputs["Facing"],
        [(0.0, srgb("fff27a")), (0.55, srgb("ffd23f")), (0.82, srgb("ffa62b"))],
    )
    g.output(g.emit(col, 1.15))
    sun.data.materials.append(mat)
    outline(sun, ink, 0.07)
    spin(sun, "rotation_euler", 2, 0.0, 1)

    # Face and rays always face the camera through this pivot.
    pivot = empty("Sol_Cara_Pivote")
    face = []

    black, gb = new_material("Sol_Ojos")
    gb.output(gb.emit(srgb("2a1606")))
    white, gw = new_material("Brillo_Ojos")
    gw.output(gw.emit((1, 1, 1, 1), 1.2))
    blush, gp = new_material("Mejillas")
    gp.output(gp.emit(srgb("ff8a5c")))

    def on_surface(x: float, z: float, lift: float = 0.0) -> tuple:
        return (x, -(math.sqrt(SUN_RADIUS**2 - x * x - z * z) + lift), z)

    eyes = []
    for side in (-1, 1):
        eye = sphere(f"Sol_Ojo_{'I' if side < 0 else 'D'}", 0.22, pivot, 32)
        eye.location = on_surface(side * 0.55, 0.32, -0.02)
        eye.scale = (0.8, 0.35, 1.15)
        eye.data.materials.append(black)
        shine = sphere(eye.name + "_Brillo", 0.07, eye, 16)
        shine.location = (0.07, -0.2, 0.09)
        shine.scale = (1 / 0.8, 1 / 0.35, 1 / 1.15)
        shine.data.materials.append(white)
        cheek = sphere(f"Sol_Mejilla_{'I' if side < 0 else 'D'}", 0.2, pivot, 24)
        cheek.location = on_surface(side * 0.95, -0.22, -0.035)
        cheek.scale = (1.2, 0.25, 0.7)
        cheek.data.materials.append(blush)
        eyes.append(eye)
        face += [eye.name, shine.name, cheek.name]

    # Blink twice per loop.
    for eye in eyes:
        pts = [(FRAME_START, 1.15)]
        for f0 in (140, 380):
            pts += [(f0, 1.15), (f0 + 3, 0.08), (f0 + 6, 1.15)]
        pts.append((FRAME_END + 1, 1.15))
        keyframes(eye, "scale", 2, pts, "BEZIER")

    curve = bpy.data.curves.new("Sol_Sonrisa", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = 0.055
    curve.bevel_resolution = 4
    curve.use_fill_caps = True
    spline = curve.splines.new("POLY")
    samples = 24
    spline.points.add(samples - 1)
    for i in range(samples):
        x = -0.55 + 1.1 * i / (samples - 1)
        z = -0.28 - 0.3 * (1 - (x / 0.55) ** 2)
        spline.points[i].co = (*on_surface(x, z, 0.0), 1.0)
    smile = link(bpy.data.objects.new("Sol_Sonrisa", curve), pivot)
    curve.materials.append(black)
    face.append(smile.name)

    rays = empty("Sol_Rayos_Giro", pivot)
    ray_mat, gr = new_material("Sol_Rayos")
    lwr = gr.node("ShaderNodeTexCoord")
    dist = gr.math("DIVIDE", gr.vmath("LENGTH", lwr.outputs["Object"]), SUN_RADIUS * 1.6)
    rcol = gr.ramp(dist, [(0.0, srgb("ffd23f")), (0.82, srgb("ffb02e"))])
    gr.output(gr.emit(rcol, 1.1))
    ray_disc = mesh_object("Sol_Rayos", star_polygon(14, SUN_RADIUS * 1.12, SUN_RADIUS * 1.55, 0.25), rays, False)
    ray_disc.data.materials.append(ray_mat)
    ray_ink = mesh_object("Sol_Rayos_Tinta", star_polygon(14, SUN_RADIUS * 1.16, SUN_RADIUS * 1.62, 0.32), rays, False)
    ray_ink.data.materials.append(ink)
    spin(rays, "rotation_euler", 1, 0.0, -1)

    halo_mat, gh = new_material("Sol_Halo")
    halo_mat.surface_render_method = "BLENDED"
    tch = gh.node("ShaderNodeTexCoord")
    hd = gh.math("DIVIDE", gh.vmath("LENGTH", tch.outputs["Object"]), SUN_RADIUS * 2.6)
    alpha = gh.ramp(hd, [(0.5, (0.32, 0.32, 0.32, 1)), (0.62, (0.12, 0.12, 0.12, 1)), (1.0, (0, 0, 0, 1))], constant=False)
    tr = gh.node("ShaderNodeBsdfTransparent")
    em = gh.emit(srgb("ffe27a"), 1.0)
    mixs = gh.node("ShaderNodeMixShader")
    bw = gh.node("ShaderNodeRGBToBW")
    gh.link(alpha, bw.inputs["Color"])
    gh.link(bw.outputs["Val"], mixs.inputs["Fac"])
    gh.link(tr.outputs[0], mixs.inputs[1])
    gh.link(em, mixs.inputs[2])
    gh.output(mixs.outputs["Shader"])
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=True, segments=96, radius=SUN_RADIUS * 2.6)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=mathutils.Matrix.Rotation(math.pi / 2, 3, "X"))
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0.6, 0))
    halo = mesh_object("Sol_Halo", bm, pivot, False)
    halo.data.materials.append(halo_mat)

    sun.visible_shadow = False
    return {"sun": sun, "pivot": pivot, "face": face}


def build_orbit(name: str, radius: float) -> Any:
    ring_segments, tube_segments, tube = 360, 6, 0.022
    verts, faces = [], []
    for i in range(ring_segments):
        a = 2 * math.pi * i / ring_segments
        for j in range(tube_segments):
            b = 2 * math.pi * j / tube_segments
            r = radius + tube * math.cos(b)
            verts.append((r * math.cos(a), r * math.sin(a), tube * math.sin(b)))
    for i in range(ring_segments):
        for j in range(tube_segments):
            a = i * tube_segments + j
            b = i * tube_segments + (j + 1) % tube_segments
            c = ((i + 1) % ring_segments) * tube_segments + (j + 1) % tube_segments
            d = ((i + 1) % ring_segments) * tube_segments + j
            faces.append((a, b, c, d))
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    obj = link(bpy.data.objects.new(name, me))

    mat, g = new_material(name + "_Mat")
    mat.surface_render_method = "DITHERED"
    tc = g.node("ShaderNodeTexCoord")
    xyz = g.node("ShaderNodeSeparateXYZ")
    g.link(tc.outputs["Object"], xyz.inputs[0])
    angle = g.math("ARCTAN2", xyz.outputs["Y"], xyz.outputs["X"])
    dashes = round(radius * 7)
    dash = g.math("GREATER_THAN", g.math("SINE", g.math("MULTIPLY", angle, float(dashes))), -0.1)
    tr = g.node("ShaderNodeBsdfTransparent")
    em = g.emit(srgb("8fa6ff"), 0.55)
    ms = g.node("ShaderNodeMixShader")
    g.link(dash, ms.inputs["Fac"])
    g.link(tr.outputs[0], ms.inputs[1])
    g.link(em, ms.inputs[2])
    g.output(ms.outputs["Shader"])
    obj.data.materials.append(mat)
    obj.visible_shadow = False
    return obj


def build_saturn_rings(parent: Any, radius: float) -> Any:
    inner, outer = radius * 1.35, radius * 2.3
    bm = bmesh.new()
    segs = 128
    rin, rout = [], []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        rin.append(bm.verts.new((inner * math.cos(a), inner * math.sin(a), 0)))
        rout.append(bm.verts.new((outer * math.cos(a), outer * math.sin(a), 0)))
    for i in range(segs):
        j = (i + 1) % segs
        bm.faces.new((rin[i], rin[j], rout[j], rout[i]))
    rings = mesh_object("Saturno_Anillos", bm, parent, False)
    mat, g = new_material("Saturno_Anillos_Mat")
    mat.surface_render_method = "DITHERED"
    mat.use_backface_culling = False
    tc = g.node("ShaderNodeTexCoord")
    d = g.vmath("LENGTH", tc.outputs["Object"])
    rel = g.math("DIVIDE", g.math("SUBTRACT", d, inner), outer - inner)
    col = g.ramp(
        rel,
        [(0.0, srgb("b89a6a")), (0.12, srgb("e7cf9c")), (0.38, srgb("f4e3b8")), (0.58, srgb("1a1030")),
         (0.63, srgb("d8bb85")), (0.84, srgb("c6a676")), (0.95, srgb("e9d3a6"))],
    )
    gap = g.math("MULTIPLY", g.math("GREATER_THAN", rel, 0.58), g.math("LESS_THAN", rel, 0.63))
    edge_in = g.math("LESS_THAN", rel, 0.02)
    edge_out = g.math("GREATER_THAN", rel, 0.98)
    edge = g.math("MAXIMUM", edge_in, edge_out)
    col = g.mix(edge, col, (*INK[:3], 1.0))
    tr = g.node("ShaderNodeBsdfTransparent")
    em = g.emit(col, 1.0)
    ms = g.node("ShaderNodeMixShader")
    g.link(gap, ms.inputs["Fac"])
    g.link(em, ms.inputs[1])
    g.link(tr.outputs[0], ms.inputs[2])
    g.output(ms.outputs["Shader"])
    rings.data.materials.append(mat)
    return rings


def build_belt(ink: Any) -> Any:
    rng = random.Random(7)

    bm = bmesh.new()
    for _ in range(240):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(*BELT)
        z = rng.uniform(-0.18, 0.18)
        size = rng.uniform(0.05, 0.14)
        m = (
            mathutils.Matrix.Translation((r * math.cos(a), r * math.sin(a), z))
            @ mathutils.Euler((rng.uniform(0, 6), rng.uniform(0, 6), rng.uniform(0, 6))).to_matrix().to_4x4()
            @ mathutils.Matrix.Diagonal((size * rng.uniform(0.7, 1.4), size, size * rng.uniform(0.6, 1.0), 1))
        )
        bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0, matrix=m)
    belt = mesh_object("Cinturon_Asteroides", bm, None, False)
    mat, g = new_material("Asteroides_Toon")
    g.output(toon_shade(g, srgb("a08a78")))
    belt.data.materials.append(mat)
    outline(belt, ink, 0.018)
    spin(belt, "rotation_euler", 2, 0.0, 1)
    return belt


def build_planets(ink: Any) -> list[dict[str, Any]]:
    records = []
    for name, radius, dist, orbits, start, spins, tilt, pattern in PLANETS:
        orbit = empty(f"{name}_Orbita")
        theta0 = math.radians(start)
        spin(orbit, "rotation_euler", 2, theta0, orbits)

        # Carrier cancels the orbit rotation so the axial tilt stays fixed in space.
        carrier = empty(f"{name}_Eje", orbit, (dist, 0, 0))
        carrier.rotation_euler = (math.radians(tilt), 0, -theta0)
        keyframes(
            carrier,
            "rotation_euler",
            2,
            [(FRAME_START, -theta0), (FRAME_END + 1, -theta0 - orbits * 2 * math.pi)],
            "LINEAR",
        )

        body = sphere(name, radius, carrier)
        mat, g = new_material(f"{name}_Toon")
        g.output(toon_shade(g, planet_base(g, pattern, radius)))
        body.data.materials.append(mat)
        outline(body, ink, max(0.035, radius * 0.07))
        spin(body, "rotation_euler", 2, 0.0, spins)

        extra = []
        if name == "Saturno":
            extra.append(build_saturn_rings(carrier, radius).name)
        if name == "Tierra":
            moon_orbit = empty("Luna_Orbita", carrier)
            spin(moon_orbit, "rotation_euler", 2, 0.0, 12)
            moon = sphere("Luna", 0.17, moon_orbit, 32)
            moon.location = (1.05, 0, 0)
            mm, gm = new_material("Luna_Toon")
            co = obj_coords(gm, 0.17)
            base = blotches(gm, co, 3.0, [(0.0, "b9b6c4"), (0.55, "d9d6e2")])
            base = craters(gm, co, base, 4.0, "8e8a9c", 0.25)
            gm.output(toon_shade(gm, base))
            moon.data.materials.append(mm)
            outline(moon, ink, 0.02)
            extra.append(moon.name)

        orbit_line = build_orbit(f"{name}_Trayectoria", dist)
        records.append(
            {
                "name": name,
                "radius": radius,
                "orbit_distance": dist,
                "orbits_per_loop": orbits,
                "seconds_per_orbit": round(LOOP_FRAMES / FPS / orbits, 3),
                "axial_tilt_deg": tilt,
                "spins_per_loop": spins,
                "objects": [orbit.name, carrier.name, body.name, orbit_line.name, *extra],
            }
        )
    return records


def build_camera(scene: Any, pivot: Any) -> Any:
    target = empty("Camara_Objetivo", None, (0, -2.5, -1.0))
    rig = empty("Camara_Rig")
    cam_data = bpy.data.cameras.new("Camara")
    cam_data.lens = 30
    cam_data.clip_end = 500
    cam = link(bpy.data.objects.new("Camara", cam_data), rig)
    elevation = math.radians(32)
    distance = 42.0
    cam.location = (0, -distance * math.cos(elevation), distance * math.sin(elevation))
    track = cam.constraints.new("TRACK_TO")
    track.target = target
    track.track_axis = "TRACK_NEGATIVE_Z"
    track.up_axis = "UP_Y"
    scene.camera = cam

    # Gentle sway that returns to its start, so the loop is seamless.
    mid = FRAME_START + LOOP_FRAMES // 2
    keyframes(
        rig,
        "rotation_euler",
        2,
        [(FRAME_START, math.radians(-12)), (mid, math.radians(12)), (FRAME_END + 1, math.radians(-12))],
        "BEZIER",
    )

    face = pivot.constraints.new("TRACK_TO")
    face.target = cam
    face.track_axis = "TRACK_NEGATIVE_Y"
    face.up_axis = "UP_Z"
    return cam


def configure_scene(scene: Any) -> None:
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights, bpy.data.curves):
        for block in list(coll):
            if block.users == 0:
                coll.remove(block)
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = WIDTH
    scene.render.resolution_y = HEIGHT
    scene.render.resolution_percentage = 100
    scene.render.fps = FPS
    scene.frame_start = FRAME_START
    scene.frame_end = FRAME_END
    scene.frame_current = FRAME_START
    scene.render.use_motion_blur = False
    scene.render.film_transparent = False
    scene.eevee.taa_render_samples = 32
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0


def main() -> dict[str, Any]:
    args = parse_args()
    artifacts = Path(os.environ["BLENDER_MCP_ARTIFACTS_ROOT"]).resolve(strict=True)
    output_dir = Path(args.output_dir).expanduser().resolve()
    output_dir.relative_to(artifacts)
    output_dir.mkdir(parents=True, exist_ok=True)
    if any(output_dir.iterdir()):
        raise RuntimeError(f"Output directory must be empty: {output_dir}")

    scene = bpy.context.scene
    configure_scene(scene)
    ink = make_ink()
    build_world(scene)
    sun = build_sun(ink)
    planets = build_planets(ink)
    belt = build_belt(ink)
    cam = build_camera(scene, sun["pivot"])

    blend_path = output_dir / "sistema_solar_cartoon.blend"
    result = bpy.ops.wm.save_as_mainfile(filepath=str(blend_path), copy=True, check_existing=False)
    if "FINISHED" not in result:
        raise RuntimeError(f"Saving returned {sorted(result)}")

    manifest = {
        "schema_version": "1.0",
        "project": "Sistema solar cartoon (bucle)",
        "blender": bpy.app.version_string,
        "build_hash": bpy.app.build_hash.decode(),
        "render": {
            "engine": scene.render.engine,
            "resolution": [WIDTH, HEIGHT],
            "fps": FPS,
            "frame_start": FRAME_START,
            "frame_end": FRAME_END,
            "loop_seconds": LOOP_FRAMES / FPS,
            "view_transform": scene.view_settings.view_transform,
            "taa_render_samples": scene.eevee.taa_render_samples,
        },
        "camera": cam.name,
        "sun": {"radius": SUN_RADIUS, "face_objects": sun["face"]},
        "planets": planets,
        "asteroid_belt": {"object": belt.name, "radius": list(BELT), "rocks": 240},
        "object_total": len(scene.objects),
        "material_total": len(bpy.data.materials),
        "blend": {
            "path": str(blend_path),
            "size_bytes": blend_path.stat().st_size,
            "sha256": sha256(blend_path),
        },
    }
    manifest_path = output_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return manifest


if __name__ in {"__main__", "__blender_mcp_script__"}:
    BLENDER_MCP_RESULT = main()
