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

    // Notches in the side edges: the line steps inward at 45 degrees, runs
    // straight at the given depth, and steps back out. Start and length are
    // fractions of the frame height, measured from the top; the length
    // includes both slopes.
    double notchRStart = 0.4, notchRLength = 0.2, notchRDepth = 0;
    double notchLStart = 0.7, notchLLength = 0.15, notchLDepth = 0;

    bool   ticks = true;
    double tickLength = 14, tickInset = 6;

    bool   tab = true;
    double tabLength = 34;

    bool   hatch = true;
    int    hatchCount = 3;
    double hatchSize = 16;

    // Gauge on the inside of the bottom line: a long slanted bar followed by
    // short slashes, all at the 45 degrees of the bottom-right cut. Start is a
    // fraction of the frame width; the rest are pixels. With gaugeFill the
    // bar stretches so the last slash stops one gap short of that cut, and
    // gaugeLength is ignored.
    bool   gauge = false, gaugeFill = false;
    double gaugeStart = 0.6, gaugeHeight = 12, gaugeLength = 72, gaugeInset = 2;
    int    gaugeStripes = 3;
    double gaugeStripeWidth = 10, gaugeGap = 4;

    // Fills the cut corners so window content does not show through a chamfer
    // deeper than decoration:rounding. Hyprland rounds content uniformly and a
    // decoration cannot clip it, so the corner is painted over instead.
    bool   mask = true;

    // Fit-content mode: the window content sits this far in from each edge of
    // the box, clear of every cut and notch. The band between the content and
    // the outline is filled with the mask colour so the window still reads as
    // one panel, and the cuts and notches themselves are left empty.
    bool   fitContent = false;
    double padL = 0, padT = 0, padR = 0, padB = 0;
    double mr = 0, mg = 0, mb = 0, ma = 0;

    // Straight (non-premultiplied) RGBA, 0..1.
    double ir = 0, ig = 0, ib = 0, ia = 1; // inner line
    double or_ = 0, og = 0, ob = 0, oa = 1; // outer line

    bool operator==(const SFrameParams&) const = default;
};

// Renders the HUD frame into a new ARGB32 surface. Caller owns the result and
// must cairo_surface_destroy() it.
cairo_surface_t* renderHudFrame(const SFrameParams& p);
