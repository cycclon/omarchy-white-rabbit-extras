#pragma once

#include <hyprland/src/config/values/types/BoolValue.hpp>
#include <hyprland/src/config/values/types/ColorValue.hpp>
#include <hyprland/src/config/values/types/IntValue.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>

inline HANDLE PHANDLE = nullptr;

struct SHudVars {
    // Ring geometry.
    SP<Config::Values::CIntValue>   outerThickness;
    SP<Config::Values::CIntValue>   gap;
    SP<Config::Values::CIntValue>   innerThickness;

    // Colors.
    SP<Config::Values::CColorValue> colActive;
    SP<Config::Values::CColorValue> colInactive;
    SP<Config::Values::CColorValue> colOuterActive;
    SP<Config::Values::CColorValue> colOuterInactive;

    // Corner masking.
    SP<Config::Values::CBoolValue>  mask;
    SP<Config::Values::CColorValue> colMask;
    SP<Config::Values::CBoolValue>  fitContent;

    // Per-corner chamfer depth. This is what Hyprland's own rounding cannot do.
    SP<Config::Values::CIntValue>   chamferTL;
    SP<Config::Values::CIntValue>   chamferTR;
    SP<Config::Values::CIntValue>   chamferBR;
    SP<Config::Values::CIntValue>   chamferBL;

    // Side-edge notches. Start and length are percentages of the frame height.
    SP<Config::Values::CIntValue>   notchRightStart;
    SP<Config::Values::CIntValue>   notchRightLength;
    SP<Config::Values::CIntValue>   notchRightDepth;
    SP<Config::Values::CIntValue>   notchLeftStart;
    SP<Config::Values::CIntValue>   notchLeftLength;
    SP<Config::Values::CIntValue>   notchLeftDepth;

    // Ornaments.
    SP<Config::Values::CBoolValue>  ticks;
    SP<Config::Values::CIntValue>   tickLength;
    SP<Config::Values::CIntValue>   tickInset;

    SP<Config::Values::CBoolValue>  tab;
    SP<Config::Values::CIntValue>   tabLength;

    SP<Config::Values::CBoolValue>  hatch;
    SP<Config::Values::CIntValue>   hatchCount;
    SP<Config::Values::CIntValue>   hatchSize;

    SP<Config::Values::CBoolValue>  gauge;
    SP<Config::Values::CBoolValue>  gaugeFill;
    SP<Config::Values::CIntValue>   gaugeStart;
    SP<Config::Values::CIntValue>   gaugeHeight;
    SP<Config::Values::CIntValue>   gaugeLength;
    SP<Config::Values::CIntValue>   gaugeInset;
    SP<Config::Values::CIntValue>   gaugeStripes;
    SP<Config::Values::CIntValue>   gaugeStripeWidth;
    SP<Config::Values::CIntValue>   gaugeGap;
};

inline SHudVars hudVars = {};
