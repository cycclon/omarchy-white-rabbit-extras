#pragma once

#include <cairo/cairo.h>
#include <cstdint>

// Everything the frame artwork needs, in scaled (device) pixels. Kept as a
// plain struct so the decoration can compare two of them to decide whether the
// cached texture is still valid.
struct SFrameParams {
    int    w = 0, h = 0;

    double outer = 1, gap = 3, inner = 2;
    double chamTL = 8, chamTR = 8, chamBR = 8, chamBL = 8;

    bool   ticks = true;
    double tickLength = 14, tickInset = 6;

    bool   tab = true;
    double tabLength = 34;

    bool   hatch = true;
    int    hatchCount = 3;
    double hatchSize = 16;

    // Fills the cut corners so window content does not show through a chamfer
    // deeper than decoration:rounding. Hyprland rounds content uniformly and a
    // decoration cannot clip it, so the corner is painted over instead.
    bool   mask = true;
    double mr = 0, mg = 0, mb = 0, ma = 0;

    // Straight (non-premultiplied) RGBA, 0..1.
    double ir = 0, ig = 0, ib = 0, ia = 1; // inner line
    double or_ = 0, og = 0, ob = 0, oa = 1; // outer line

    bool operator==(const SFrameParams&) const = default;
};

// Renders the HUD frame into a new ARGB32 surface. Caller owns the result and
// must cairo_surface_destroy() it.
cairo_surface_t* renderHudFrame(const SFrameParams& p);
