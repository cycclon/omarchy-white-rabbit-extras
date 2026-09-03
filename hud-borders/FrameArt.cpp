#include "FrameArt.hpp"

#include <algorithm>
#include <cmath>

namespace {
    constexpr double INV_SQRT2 = 0.70710678118654752;

    // A rectangle whose four corners are cut at independent depths. This is the
    // whole reason the plugin exists: Hyprland's renderBorder takes one radius
    // for the entire box, so an asymmetric corner is unreachable from config.
    void chamferPath(cairo_t* cr, double x, double y, double w, double h, double tl, double tr, double br, double bl) {
        // Keep opposing cuts from overlapping on small windows.
        const double maxH = w / 2.0, maxV = h / 2.0;
        tl = std::clamp(tl, 0.0, std::min(maxH, maxV));
        tr = std::clamp(tr, 0.0, std::min(maxH, maxV));
        br = std::clamp(br, 0.0, std::min(maxH, maxV));
        bl = std::clamp(bl, 0.0, std::min(maxH, maxV));

        cairo_move_to(cr, x + tl, y);
        cairo_line_to(cr, x + w - tr, y);
        cairo_line_to(cr, x + w, y + tr);
        cairo_line_to(cr, x + w, y + h - br);
        cairo_line_to(cr, x + w - br, y + h);
        cairo_line_to(cr, x + bl, y + h);
        cairo_line_to(cr, x, y + h - bl);
        cairo_line_to(cr, x, y + tl);
        cairo_close_path(cr);
    }

    void segment(cairo_t* cr, double x1, double y1, double x2, double y2, double width) {
        cairo_set_line_width(cr, width);
        cairo_new_path(cr);
        cairo_move_to(cr, x1, y1);
        cairo_line_to(cr, x2, y2);
        cairo_stroke(cr);
    }

    // A segment of `len` centred on (cx,cy) running along the unit vector (dx,dy).
    void centredSegment(cairo_t* cr, double cx, double cy, double dx, double dy, double len, double width) {
        const double hx = dx * len / 2.0, hy = dy * len / 2.0;
        segment(cr, cx - hx, cy - hy, cx + hx, cy + hy, width);
    }
}

cairo_surface_t* renderHudFrame(const SFrameParams& p) {
    if (p.w <= 0 || p.h <= 0)
        return nullptr;

    auto* surf = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, p.w, p.h);
    if (cairo_surface_status(surf) != CAIRO_STATUS_SUCCESS) {
        cairo_surface_destroy(surf);
        return nullptr;
    }

    auto* cr = cairo_create(surf);
    cairo_set_antialias(cr, CAIRO_ANTIALIAS_BEST);
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_BUTT);
    cairo_set_line_join(cr, CAIRO_LINE_JOIN_MITER);

    const double W = p.w, H = p.h;

    // Stroke centrelines, measured in from the edge of the reserved box.
    const double outerInset = p.outer / 2.0;
    const double innerInset = p.outer + p.gap + p.inner / 2.0;

    // Offsetting a chamfered path inward shortens each cut by the offset.
    const double shrink = p.outer + p.gap;
    const double iTL = std::max(0.0, p.chamTL - shrink);
    const double iTR = std::max(0.0, p.chamTR - shrink);
    const double iBR = std::max(0.0, p.chamBR - shrink);
    const double iBL = std::max(0.0, p.chamBL - shrink);

    // ---- corner mask -------------------------------------------------------
    // Everything outside the frame path, filled in one even-odd pass: that is
    // exactly the four corner cuts.
    if (p.mask && p.ma > 0) {
        cairo_set_fill_rule(cr, CAIRO_FILL_RULE_EVEN_ODD);
        cairo_set_source_rgba(cr, p.mr, p.mg, p.mb, p.ma);
        cairo_new_path(cr);
        cairo_rectangle(cr, 0, 0, W, H);
        chamferPath(cr, 0, 0, W, H, p.chamTL, p.chamTR, p.chamBR, p.chamBL);
        cairo_fill(cr);
        cairo_set_fill_rule(cr, CAIRO_FILL_RULE_WINDING);
    }

    // ---- outer hairline -----------------------------------------------------
    if (p.outer > 0 && p.oa > 0) {
        cairo_set_source_rgba(cr, p.or_, p.og, p.ob, p.oa);
        cairo_set_line_width(cr, p.outer);
        cairo_new_path(cr);
        chamferPath(cr, outerInset, outerInset, W - p.outer, H - p.outer, p.chamTL, p.chamTR, p.chamBR, p.chamBL);
        cairo_stroke(cr);
    }

    // ---- inner line and every ornament, all in the main colour --------------
    if (p.inner <= 0 || p.ia <= 0) {
        cairo_destroy(cr);
        return surf;
    }

    cairo_set_source_rgba(cr, p.ir, p.ig, p.ib, p.ia);
    cairo_set_line_width(cr, p.inner);
    cairo_new_path(cr);
    chamferPath(cr, innerInset, innerInset, W - innerInset * 2, H - innerInset * 2, iTL, iTR, iBR, iBL);
    cairo_stroke(cr);

    // Ornaments sit this far inside the inner line.
    const double orn = innerInset + p.inner / 2.0 + p.tickInset;
    const double runX = W - orn * 2.0; // usable span between ornament guides
    const double runY = H - orn * 2.0;

    // ---- corner ticks: short accents parallel to each edge ------------------
    if (p.ticks && p.tickLength > 0 && runX > 0 && runY > 0) {
        const double len = std::min(p.tickLength, std::min(runX, runY) / 3.0);

        struct STick {
            double x, y, dx, dy, cut;
        };
        // Two per corner: one along the horizontal edge, one along the vertical.
        const STick ticks[] = {
            {orn + iTL, orn, 1, 0, iTL}, {orn, orn + iTL, 0, 1, iTL},
            {W - orn - iTR, orn, -1, 0, iTR}, {W - orn, orn + iTR, 0, 1, iTR},
            {W - orn - iBR, H - orn, -1, 0, iBR}, {W - orn, H - orn - iBR, 0, -1, iBR},
            {orn + iBL, H - orn, 1, 0, iBL}, {orn, H - orn - iBL, 0, -1, iBL},
        };

        for (const auto& t : ticks) {
            segment(cr, t.x, t.y, t.x + t.dx * len, t.y + t.dy * len, p.inner);
        }
    }

    // ---- top-right tab: a heavier bar riding the corner cut -----------------
    if (p.tab && iTR > 0 && p.tabLength > 0) {
        // Midpoint of the top-right cut, pushed inward along its normal.
        const double mx = W - innerInset - iTR / 2.0;
        const double my = innerInset + iTR / 2.0;
        const double off = p.inner / 2.0 + p.tickInset;
        centredSegment(cr, mx - off * INV_SQRT2, my + off * INV_SQRT2, INV_SQRT2, INV_SQRT2, p.tabLength, p.inner * 2.0);
    }

    // ---- bottom-right hatch: parallel diagonals inside the corner -----------
    if (p.hatch && p.hatchCount > 0 && p.hatchSize > 0) {
        const double mx = W - innerInset - iBR / 2.0;
        const double my = H - innerInset - iBR / 2.0;
        const double spacing = std::max(p.inner * 2.0, 3.0);

        for (int i = 0; i < p.hatchCount; ++i) {
            const double off = p.inner / 2.0 + p.tickInset + i * spacing;
            // Inward normal of the bottom-right cut is (-1,-1)/sqrt(2).
            centredSegment(cr, mx - off * INV_SQRT2, my - off * INV_SQRT2, -INV_SQRT2, INV_SQRT2, p.hatchSize, p.inner);
        }
    }

    cairo_destroy(cr);
    cairo_surface_flush(surf);
    return surf;
}
