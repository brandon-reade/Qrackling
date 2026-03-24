# Single-window step-through visualizer for Solar/Lunar modeling relative to LOS (ENU).

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Callable, List, Optional

import numpy as np
import matplotlib.pyplot as plt
from matplotlib.widgets import Button


# ---------------------------- Math functions ----------------------------

def deg2rad(d: float) -> float:
    return d * math.pi / 180.0

def rad2deg(r: float) -> float:
    return r * 180.0 / math.pi

def unit(v: np.ndarray, eps: float = 1e-12) -> np.ndarray:
    n = np.linalg.norm(v)
    if n < eps:
        raise ValueError("Cannot normalize near-zero vector.")
    return v / n

def clamp(x: float, lo: float = -1.0, hi: float = 1.0) -> float:
    return max(lo, min(hi, x))

def v_from_alt_az(alt_rad: float, az_rad: float) -> np.ndarray:
    """
    ENU convention:
      n = (1,0,0)
      e = (0,1,0)
      u = (0,0,1)

    v(a,A) = cos(a)*(n*cos(A) + e*sin(A)) + u*sin(a)
          = [cos(a)cos(A), cos(a)sin(A), sin(a)]
    """
    ca = math.cos(alt_rad)
    sa = math.sin(alt_rad)
    cA = math.cos(az_rad)
    sA = math.sin(az_rad)
    return np.array([ca * cA, ca * sA, sa], dtype=float)


# ---------------------------- Plot helpers ----------------------------

def setup_3d(ax, title: str):
    ax.set_title(title, pad=12)
    ax.set_xlabel("North (n)")
    ax.set_ylabel("East (e)")
    ax.set_zlabel("Up (u)")
    ax.set_xlim(-1.1, 1.1)
    ax.set_ylim(-1.1, 1.1)
    ax.set_zlim(-1.1, 1.1)
    ax.set_box_aspect((1, 1, 1))

def draw_axes(ax, scale: float = 1.0, alpha: float = 0.35):
    ax.quiver(0, 0, 0, scale, 0, 0, color="tab:blue", alpha=alpha, linewidth=2)
    ax.quiver(0, 0, 0, 0, scale, 0, color="tab:orange", alpha=alpha, linewidth=2)
    ax.quiver(0, 0, 0, 0, 0, scale, color="tab:green", alpha=alpha, linewidth=2)
    ax.text(scale, 0, 0, "n", color="tab:blue")
    ax.text(0, scale, 0, "e", color="tab:orange")
    ax.text(0, 0, scale, "u", color="tab:green")

def draw_vector(ax, vec: np.ndarray, label: str, color: str, linewidth: float = 3.0):
    ax.quiver(0, 0, 0, vec[0], vec[1], vec[2], color=color, linewidth=linewidth)
    ax.text(vec[0], vec[1], vec[2], label, color=color)

def draw_line_segment(ax, p0: np.ndarray, p1: np.ndarray, color: str, label: Optional[str] = None, linewidth: float = 2.5):
    ax.plot([p0[0], p1[0]], [p0[1], p1[1]], [p0[2], p1[2]], color=color, linewidth=linewidth)
    if label:
        mid = 0.5 * (p0 + p1)
        ax.text(mid[0], mid[1], mid[2], label, color=color)

def draw_plane_through_origin(ax, normal: np.ndarray, size: float = 1.0, color: str = "gray", alpha: float = 0.12):
    n = unit(normal)

    tmp = np.array([1.0, 0.0, 0.0])
    if abs(np.dot(tmp, n)) > 0.9:
        tmp = np.array([0.0, 1.0, 0.0])

    v1 = unit(np.cross(n, tmp))
    v2 = unit(np.cross(n, v1))

    s = size
    corners = [(-s, -s), (-s, s), (s, s), (s, -s)]
    pts = [a * v1 + b * v2 for a, b in corners]

    xs = [p[0] for p in pts] + [pts[0][0]]
    ys = [p[1] for p in pts] + [pts[0][1]]
    zs = [p[2] for p in pts] + [pts[0][2]]

    ax.plot(xs, ys, zs, color=color, alpha=alpha)
    ax.plot_trisurf(xs[:-1], ys[:-1], zs[:-1], color=color, alpha=alpha, linewidth=0)

def annotate_angle_arc_on_sphere(ax, L: np.ndarray, B: np.ndarray, theta_rad: float, npts: int = 60, color: str = "k", label: str = "θ"):
    """
    Draw a great-circle arc on the unit sphere between unit vectors L and B.
    """
    L = unit(L)
    B = unit(B)
    if theta_rad < 1e-9:
        return

    ts = np.linspace(0, 1, npts)
    sinT = math.sin(theta_rad)
    pts = []
    for t in ts:
        a = math.sin((1 - t) * theta_rad) / sinT
        b = math.sin(t * theta_rad) / sinT
        p = a * L + b * B
        pts.append(unit(p))
    pts = np.array(pts)

    ax.plot(pts[:, 0], pts[:, 1], pts[:, 2], color=color, linewidth=2)
    mid = pts[len(pts) // 2]
    ax.text(mid[0], mid[1], mid[2], f"{label}={rad2deg(theta_rad):.1f}°", color=color)

def draw_azimuth_arc_in_LOS_plane(
    ax,
    L_hat: np.ndarray,
    u_perp_hat: np.ndarray,
    v_hat: np.ndarray,
    phi_rad: float,
    radius: float = 0.9,
    npts: int = 80,
    color: str = "k",
    label: str = "φ_rel,azi",
):
    """
    Draw an arc in the plane normal to L_hat measuring phi_rad from u_perp_hat
    toward the +v_hat direction (right-handed in that plane).

    Points on arc: p(t) = r*(cos(t) u_perp_hat + sin(t) v_hat), t in [0, phi]
    Works for positive or negative phi (arc goes the correct direction).
    """
    if not np.isfinite(phi_rad):
        return

    # Build parameter range respecting sign
    ts = np.linspace(0.0, phi_rad, npts)
    pts = np.array([radius * (math.cos(t) * u_perp_hat + math.sin(t) * v_hat) for t in ts])

    ax.plot(pts[:, 0], pts[:, 1], pts[:, 2], color=color, linewidth=2)

    mid = pts[len(pts) // 2]
    ax.text(mid[0], mid[1], mid[2], f"{label}={rad2deg(phi_rad):.1f}°", color=color)


# ---------------------------- Core derivation computations ----------------------------

@dataclass
class GeometryResult:
    L_hat: np.ndarray
    B_hat: np.ndarray
    theta_rel_zen_rad: float
    dotLB: float

    B_parallel: np.ndarray
    B_perp: np.ndarray
    B_perp_hat: np.ndarray

    u_ref: np.ndarray
    u_perp: np.ndarray
    u_perp_hat: np.ndarray
    v_hat: np.ndarray

    x: float
    y: float
    phi_rel_azi_rad: float

def compute_geometry(aL: float, AL: float, aB: float, AB: float, degrees: bool = True) -> GeometryResult:
    if degrees:
        aL, AL, aB, AB = map(deg2rad, (aL, AL, aB, AB))

    L_hat = unit(v_from_alt_az(aL, AL))
    B_hat = unit(v_from_alt_az(aB, AB))

    dotLB = clamp(float(np.dot(L_hat, B_hat)))
    theta = math.acos(dotLB)  # relative zenith

    B_parallel = dotLB * L_hat
    B_perp = B_hat - B_parallel

    if np.linalg.norm(B_perp) < 1e-12:
        B_perp_hat = np.array([np.nan, np.nan, np.nan], dtype=float)
    else:
        B_perp_hat = unit(B_perp)

    u_global = np.array([0.0, 0.0, 1.0])
    if abs(float(np.dot(u_global, L_hat))) <= 0.999:
        u_ref = u_global
    else:
        u_ref = np.array([0.0, 1.0, 0.0])  # fallback (East)

    u_perp = u_ref - float(np.dot(u_ref, L_hat)) * L_hat
    u_perp_hat = unit(u_perp)
    v_hat = unit(np.cross(L_hat, u_perp_hat))

    x = float(np.dot(B_perp_hat, u_perp_hat)) if np.all(np.isfinite(B_perp_hat)) else float("nan")
    y = float(np.dot(B_perp_hat, v_hat)) if np.all(np.isfinite(B_perp_hat)) else float("nan")
    phi = math.atan2(y, x) if (np.isfinite(x) and np.isfinite(y)) else float("nan")

    return GeometryResult(
        L_hat=L_hat,
        B_hat=B_hat,
        theta_rel_zen_rad=theta,
        dotLB=dotLB,
        B_parallel=B_parallel,
        B_perp=B_perp,
        B_perp_hat=B_perp_hat,
        u_ref=u_ref,
        u_perp=u_perp,
        u_perp_hat=u_perp_hat,
        v_hat=v_hat,
        x=x,
        y=y,
        phi_rel_azi_rad=phi,
    )


# ---------------------------- Stage rendering ----------------------------

StageFn = Callable[[plt.Axes, GeometryResult], None]

def stage1(ax, res: GeometryResult):
    setup_3d(ax, "Stage 1: ENU basis and unit vectors L̂ (LOS) and B̂ (Body)")
    draw_axes(ax)
    draw_vector(ax, res.L_hat, "L̂", "tab:red")
    draw_vector(ax, res.B_hat, "B̂", "tab:purple")

def stage2(ax, res: GeometryResult):
    setup_3d(ax, "Stage 2: Relative zenith θ_rel,zen = arccos(L̂·B̂)")
    draw_axes(ax)
    draw_vector(ax, res.L_hat, "L̂", "tab:red")
    draw_vector(ax, res.B_hat, "B̂", "tab:purple")
    annotate_angle_arc_on_sphere(
        ax,
        res.L_hat,
        res.B_hat,
        res.theta_rel_zen_rad,
        color="black",
        label="θ_rel,zen",
    )

def stage3(ax, res: GeometryResult):
    setup_3d(ax, "Stage 3: Projection (B̂·L̂)L̂ and perpendicular component B⊥")
    draw_axes(ax)
    draw_vector(ax, res.L_hat, "L̂", "tab:red")
    draw_vector(ax, res.B_hat, "B̂", "tab:purple")
    draw_plane_through_origin(ax, normal=res.L_hat, size=1.0)

    draw_vector(ax, res.B_parallel, "(B̂·L̂)L̂", "tab:cyan", linewidth=2.5)
    draw_line_segment(ax, res.B_parallel, res.B_hat, color="tab:olive", label="B⊥", linewidth=3.0)

def stage4(ax, res: GeometryResult):
    setup_3d(ax, "Stage 4: Normalize B⊥ to get B̂⊥")
    draw_axes(ax)
    draw_vector(ax, res.L_hat, "L̂", "tab:red")
    draw_vector(ax, res.B_hat, "B̂", "tab:purple", linewidth=2.0)
    draw_plane_through_origin(ax, normal=res.L_hat, size=1.0)

    if np.all(np.isfinite(res.B_perp_hat)):
        draw_vector(ax, res.B_perp, "B⊥", "0.5", linewidth=2.0)
        draw_vector(ax, res.B_perp_hat, "B̂⊥", "tab:olive", linewidth=3.0)
        ax.text(-1.05, -1.05, 1.0, f"||B⊥|| = {np.linalg.norm(res.B_perp):.3f}", color="black")
    else:
        ax.text(0, 0, 0, "B⊥ ~ 0 (B̂ aligned with L̂): azimuth undefined.", color="black")

def stage5(ax, res: GeometryResult):
    setup_3d(ax, "Stage 5: Build LOS-centered frame (u_ref → û⊥, v̂=L̂×û⊥)")
    draw_axes(ax)
    draw_vector(ax, res.L_hat, "L̂", "tab:red")
    draw_vector(ax, res.B_hat, "B̂", "tab:purple", linewidth=2.2)  # keep body visible
    draw_plane_through_origin(ax, normal=res.L_hat, size=1.0)

    draw_vector(ax, unit(res.u_ref), "u_ref", "tab:green", linewidth=2.0)
    draw_vector(ax, res.u_perp_hat, "û⊥ (0°)", "tab:blue", linewidth=3.0)
    draw_vector(ax, res.v_hat, "v̂ (90°)", "tab:orange", linewidth=3.0)

    if np.all(np.isfinite(res.B_perp_hat)):
        draw_vector(ax, res.B_perp_hat, "B̂⊥", "tab:olive", linewidth=2.6)

def stage6(ax, res: GeometryResult):
    setup_3d(ax, "Stage 6: Relative azimuth φ_rel,azi measured in plane ⟂ L̂")
    draw_axes(ax)

    draw_vector(ax, res.L_hat, "L̂", "tab:red")
    draw_vector(ax, res.B_hat, "B̂", "tab:purple", linewidth=2.2)  # keep body visible
    draw_plane_through_origin(ax, normal=res.L_hat, size=1.0)

    draw_vector(ax, res.u_perp_hat, "û⊥ (0°)", "tab:blue", linewidth=2.5)
    draw_vector(ax, res.v_hat, "v̂ (90°)", "tab:orange", linewidth=2.5)

    if np.all(np.isfinite(res.B_perp_hat)):
        draw_vector(ax, res.B_perp_hat, "B̂⊥", "tab:olive", linewidth=3.0)

        # Draw azimuth arc (like the separation arc, but in the LOS-normal plane)
        draw_azimuth_arc_in_LOS_plane(
            ax,
            L_hat=res.L_hat,
            u_perp_hat=res.u_perp_hat,
            v_hat=res.v_hat,
            phi_rad=res.phi_rel_azi_rad,
            radius=0.85,
            color="black",
            label="φ_rel,azi",
        )

        ax.text(
            -1.05, -1.05, 1.0,
            f"x = B̂⊥·û⊥ = {res.x:.3f}\n"
            f"y = B̂⊥·v̂  = {res.y:.3f}\n"
            f"φ_rel,azi   = {rad2deg(res.phi_rel_azi_rad):.2f}°",
            color="black",
        )
    else:
        ax.text(0, 0, 0, "B̂⊥ undefined (aligned).", color="black")


# ---------------------------- Viewer UI ----------------------------

class StageViewer:
    def __init__(self, res: GeometryResult, stages: List[StageFn], stage_names: Optional[List[str]] = None):
        self.res = res
        self.stages = stages
        self.stage_names = stage_names or [f"Stage {i+1}" for i in range(len(stages))]
        self.i = 0

        self.fig = plt.figure(figsize=(10, 7))
        self.ax = self.fig.add_subplot(111, projection="3d")

        plt.subplots_adjust(bottom=0.18)

        axprev = self.fig.add_axes([0.30, 0.05, 0.15, 0.08])
        axnext = self.fig.add_axes([0.55, 0.05, 0.15, 0.08])
        self.bprev = Button(axprev, "Previous")
        self.bnext = Button(axnext, "Next")
        self.bprev.on_clicked(self.prev)
        self.bnext.on_clicked(self.next)

        self.fig.canvas.mpl_connect("key_press_event", self.on_key)

        self.render()

    def render(self):
        self.ax.cla()
        self.stages[self.i](self.ax, self.res)
        self.fig.suptitle(f"{self.stage_names[self.i]}   ({self.i+1}/{len(self.stages)})", y=0.98, fontsize=12)

        # Keep the info text in a consistent location by overwriting it each render:
        # (simple approach: clear all fig-level texts and re-add one)
        for t in list(self.fig.texts):
            t.remove()

        info = (
            f"L̂ = {np.array2string(self.res.L_hat, precision=3)}\n"
            f"B̂ = {np.array2string(self.res.B_hat, precision=3)}\n"
            f"θ_rel,zen = {rad2deg(self.res.theta_rel_zen_rad):.2f}°   "
            f"φ_rel,azi = {rad2deg(self.res.phi_rel_azi_rad):.2f}°"
        )
        self.fig.text(0.02, 0.02, info, family="monospace", fontsize=9)

        self.fig.canvas.draw_idle()

    def next(self, _event=None):
        self.i = (self.i + 1) % len(self.stages)
        self.render()

    def prev(self, _event=None):
        self.i = (self.i - 1) % len(self.stages)
        self.render()

    def on_key(self, event):
        if event.key in ("right", "n", " "):
            self.next()
        elif event.key in ("left", "p", "backspace"):
            self.prev()


# ---------------------------- Main ----------------------------

def main():
    # ---- Example inputs (EDIT THESE) ----
    # LOS:
    obszen_deg = 50.0
    obsazi_deg = 170.0

    # Body (Sun/Moon):
    sourcezen_deg = 55.0
    sourceazi_deg = 110.0

    res = compute_geometry(obszen_deg, obsazi_deg, sourcezen_deg, sourceazi_deg, degrees=True)

    stages = [stage1, stage2, stage3, stage4, stage5, stage6]
    names = [
        "Stage 1: ENU + vectors",
        "Stage 2: Relative zenith",
        "Stage 3: Projection & B⊥",
        "Stage 4: Normalize to B̂⊥",
        "Stage 5: Construct LOS frame",
        "Stage 6: Relative azimuth in LOS plane",
    ]

    StageViewer(res, stages, names)
    plt.show()


if __name__ == "__main__":
    main()