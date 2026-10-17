#include "FrameArt.hpp"

#include <algorithm>
#include <cmath>
#include <vector>

namespace {
    constexpr double INV_SQRT2 = 0.70710678118654752;

    struct SPt {
        double x, y;
    };

    // The frame outline on the edge of the reserved box, clockwise from the
    // top-left. Hyprland's renderBorder takes one radius for the entire box, so
    // independent corner cuts and edge notches are unreachable from config --
    // that is the whole reason the plugin exists.
    std::vector<SPt> framePolygon(const SFrameParams& p) {
        const double W = p.w, H = p.h;

        // Keep opposing cuts from overlapping on small windows.
        const double lim = std::min(W, H) / 2.0;
        const double tl  = std::clamp(p.chamTL, 0.0, lim);
        const double tr  = std::clamp(p.chamTR, 0.0, lim);
        const double br  = std::clamp(p.chamBR, 0.0, lim);
        const double bl  = std::clamp(p.chamBL, 0.0, lim);

        std::vector<SPt> pts = {{tl, 0}, {W - tr, 0}, {W, tr}};

        // Clamps a side notch between the corner cuts at either end of its
        // edge. The slopes need room, so the depth gives way before the run
        // does. Returns the depth, or 0 when the notch does not fit.
        auto notchSpan = [&](double start, double length, double depth, double cutTop, double cutBottom, double& y0, double& y1) {
            if (depth <= 0 || length <= 0)
                return 0.0;
            y0             = std::max(H * start, cutTop);
            y1             = std::min(H * (start + length), H - cutBottom);
            const double d = std::min({depth, (y1 - y0) / 2.0, W / 4.0});
            return d >= 1.0 ? d : 0.0;
        };

        double y0 = 0, y1 = 0;

        // The right edge is walked downward...
        if (const double d = notchSpan(p.notchRStart, p.notchRLength, p.notchRDepth, tr, br, y0, y1); d > 0)
            pts.insert(pts.end(), {{W, y0}, {W - d, y0 + d}, {W - d, y1 - d}, {W, y1}});

        pts.insert(pts.end(), {{W, H - br}, {W - br, H}, {bl, H}, {0, H - bl}});

        // ...and the left edge upward.
        if (const double d = notchSpan(p.notchLStart, p.notchLLength, p.notchLDepth, tl, bl, y0, y1); d > 0)
            pts.insert(pts.end(), {{0, y1}, {d, y1 - d}, {d, y0 + d}, {0, y0}});

        pts.push_back({0, tl});

        // A zero cut leaves two vertices on the same spot, and a straight run
        // leaves collinear ones; both would give the offset below a
        // degenerate edge.
        std::vector<SPt> out;
        for (const auto& pt : pts) {
            if (!out.empty() && std::hypot(pt.x - out.back().x, pt.y - out.back().y) < 1e-6)
                continue;
            out.push_back(pt);
        }
        while (out.size() > 1 && std::hypot(out.front().x - out.back().x, out.front().y - out.back().y) < 1e-6)
            out.pop_back();

        std::vector<SPt> clean;
        for (size_t i = 0; i < out.size(); ++i) {
            const auto& a = out[(i + out.size() - 1) % out.size()];
            const auto& b = out[i];
            const auto& c = out[(i + 1) % out.size()];
            if (std::abs((b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)) > 1e-9)
                clean.push_back(b);
        }
        return clean;
    }

    // Moves every edge `s` inward and re-joins them at mitred vertices, so the
    // two rings stay parallel around cuts and notches alike.
    std::vector<SPt> offsetPolygon(const std::vector<SPt>& pts, double s) {
        const size_t     n = pts.size();
        std::vector<SPt> normals(n);
        for (size_t i = 0; i < n; ++i) {
            const auto&  a   = pts[i];
            const auto&  b   = pts[(i + 1) % n];
            const double len = std::hypot(b.x - a.x, b.y - a.y);
            // Clockwise in y-down coordinates: the inward normal is (-dy, dx).
            normals[i] = {-(b.y - a.y) / len, (b.x - a.x) / len};
        }

        std::vector<SPt> out(n);
        for (size_t i = 0; i < n; ++i) {
            const auto&  n1 = normals[(i + n - 1) % n];
            const auto&  n2 = normals[i];
            const double k  = s / (1.0 + n1.x * n2.x + n1.y * n2.y);
            out[i]          = {pts[i].x + (n1.x + n2.x) * k, pts[i].y + (n1.y + n2.y) * k};
        }
        return out;
    }

    void tracePolygon(cairo_t* cr, const std::vector<SPt>& pts) {
        for (size_t i = 0; i < pts.size(); ++i) {
            if (i == 0)
                cairo_move_to(cr, pts[i].x, pts[i].y);
            else
                cairo_line_to(cr, pts[i].x, pts[i].y);
        }
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

    // Where the ornaments put the inner line's cuts. The line itself is a true
    // offset of the outline, drawn below.
    const double shrink = p.outer + p.gap;
    const double iTL = std::max(0.0, p.chamTL - shrink);
    const double iTR = std::max(0.0, p.chamTR - shrink);
    const double iBR = std::max(0.0, p.chamBR - shrink);
    const double iBL = std::max(0.0, p.chamBL - shrink);

    const auto outline = framePolygon(p);
    if (outline.size() < 3) {
        cairo_destroy(cr);
        return surf;
    }

    // ---- corner mask -------------------------------------------------------
    // Everything outside the frame path, filled in one even-odd pass: that is
    // exactly the corner cuts and the notch.
    if (p.fitContent && p.ma > 0) {
        // Inside the outline but outside the content: the panel band.
        cairo_set_fill_rule(cr, CAIRO_FILL_RULE_EVEN_ODD);
        cairo_set_source_rgba(cr, p.mr, p.mg, p.mb, p.ma);
        cairo_new_path(cr);
        tracePolygon(cr, outline);
        cairo_rectangle(cr, p.padL, p.padT, W - p.padL - p.padR, H - p.padT - p.padB);
        cairo_fill(cr);
        cairo_set_fill_rule(cr, CAIRO_FILL_RULE_WINDING);
    } else if (p.mask && p.ma > 0) {
        cairo_set_fill_rule(cr, CAIRO_FILL_RULE_EVEN_ODD);
        cairo_set_source_rgba(cr, p.mr, p.mg, p.mb, p.ma);
        cairo_new_path(cr);
        cairo_rectangle(cr, 0, 0, W, H);
        tracePolygon(cr, outline);
        cairo_fill(cr);
        cairo_set_fill_rule(cr, CAIRO_FILL_RULE_WINDING);
    }

    // ---- outer hairline -----------------------------------------------------
    if (p.outer > 0 && p.oa > 0) {
        cairo_set_source_rgba(cr, p.or_, p.og, p.ob, p.oa);
        cairo_set_line_width(cr, p.outer);
        cairo_new_path(cr);
        tracePolygon(cr, offsetPolygon(outline, outerInset));
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
    tracePolygon(cr, offsetPolygon(outline, innerInset));
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

    // ---- bottom gauge: slanted bar plus trailing slashes --------------------
    if (p.gauge && p.gaugeHeight > 0 && (p.gaugeFill || p.gaugeLength > 0)) {
        const double h     = p.gaugeHeight;
        const double base  = H - innerInset - p.inner / 2.0 - p.gaugeInset;
        const double x0    = W * p.gaugeStart;
        const int    count = std::max(0, p.gaugeStripes);
        const double tail  = count * (p.gaugeGap + p.gaugeStripeWidth);

        // Where the bottom-right cut's inside edge crosses the gauge's
        // baseline. The cut and the slashes are parallel, so a horizontal gap
        // measured here is the same one the slashes keep between themselves.
        const double br     = std::clamp(p.chamBR, 0.0, std::min(W, H) / 2.0);
        const double cutX   = W + H - br - (innerInset + p.inner / 2.0) * std::sqrt(2.0) - base;
        const double limitX = cutX - p.gaugeGap;

        const double length = p.gaugeFill ? limitX - tail - x0 : p.gaugeLength;

        // Skip on windows too small to hold it clear of the bottom-right cut
        // and above the top edge.
        if (length >= h && x0 + length + tail <= limitX + 0.5 && base - h > innerInset) {
            // Parallelogram leaning like the bottom-right cut: rising h moves
            // right by h.
            auto slant = [&](double x, double w) {
                cairo_new_path(cr);
                cairo_move_to(cr, x, base);
                cairo_line_to(cr, x + w, base);
                cairo_line_to(cr, x + w + h, base - h);
                cairo_line_to(cr, x + h, base - h);
                cairo_close_path(cr);
                cairo_fill(cr);
            };

            slant(x0, length);
            for (int i = 0; i < count; ++i)
                slant(x0 + length + p.gaugeGap + i * (p.gaugeStripeWidth + p.gaugeGap), p.gaugeStripeWidth);
        }
    }

    cairo_destroy(cr);
    cairo_surface_flush(surf);
    return surf;
}
