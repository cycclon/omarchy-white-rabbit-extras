#define WLR_USE_UNSTABLE

#include <unistd.h>

#include <any>
#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/config/ConfigManager.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/event/EventBus.hpp>

#include "HudFrame.hpp"
#include "globals.hpp"

// Do NOT change this function.
APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

static void onNewWindow(PHLWINDOW window) {
    if (std::ranges::any_of(window->m_windowDecorations, [](const auto& d) { return d->getDisplayName() == "HUD Frame"; }))
        return;

    HyprlandAPI::addWindowDecoration(PHANDLE, window, makeUnique<CHudFrame>(window));
}

template <typename T, typename... Args>
static void reg(SP<T>& slot, Args&&... args) {
    slot = makeShared<T>(std::forward<Args>(args)...);
    HyprlandAPI::addConfigValueV2(PHANDLE, slot);
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;

    const std::string HASH        = __hyprland_api_get_hash();
    const std::string CLIENT_HASH = __hyprland_api_get_client_hash();

    if (HASH != CLIENT_HASH) {
        HyprlandAPI::addNotification(PHANDLE, "[hud-borders] Failure in initialization: Version mismatch (headers ver is not equal to running hyprland ver)",
                                     CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
        throw std::runtime_error("[hud-borders] Version mismatch");
    }

    using namespace Config::Values;

    reg(hudVars.outerThickness, "plugin:hud-borders:outer_thickness", "Thickness of the outer hairline", 1, SIntValueOptions{.min = 0, .max = 32});
    reg(hudVars.gap, "plugin:hud-borders:gap", "Gap between the outer hairline and the inner line", 3, SIntValueOptions{.min = 0, .max = 64});
    reg(hudVars.innerThickness, "plugin:hud-borders:inner_thickness", "Thickness of the inner line", 2, SIntValueOptions{.min = 0, .max = 32});

    reg(hudVars.colActive, "plugin:hud-borders:col.active", "Inner line colour, focused", 0xff5ce4ff);
    reg(hudVars.colInactive, "plugin:hud-borders:col.inactive", "Inner line colour, unfocused", 0xcc0d3b4a);
    reg(hudVars.colOuterActive, "plugin:hud-borders:col.outer_active", "Outer hairline colour, focused", 0xcc0b86b3);
    reg(hudVars.colOuterInactive, "plugin:hud-borders:col.outer_inactive", "Outer hairline colour, unfocused", 0x660d3b4a);

    reg(hudVars.mask, "plugin:hud-borders:corner_mask", "Paint over window content inside the corner cuts", true);
    reg(hudVars.colMask, "plugin:hud-borders:col.mask", "Colour used to mask the corner cuts", 0xf2020d06);

    reg(hudVars.chamferTL, "plugin:hud-borders:chamfer_top_left", "Corner cut depth, top left", 10, SIntValueOptions{.min = 0, .max = 512});
    reg(hudVars.chamferTR, "plugin:hud-borders:chamfer_top_right", "Corner cut depth, top right", 40, SIntValueOptions{.min = 0, .max = 512});
    reg(hudVars.chamferBR, "plugin:hud-borders:chamfer_bottom_right", "Corner cut depth, bottom right", 24, SIntValueOptions{.min = 0, .max = 512});
    reg(hudVars.chamferBL, "plugin:hud-borders:chamfer_bottom_left", "Corner cut depth, bottom left", 10, SIntValueOptions{.min = 0, .max = 512});

    reg(hudVars.ticks, "plugin:hud-borders:ticks", "Draw short accent ticks near each corner", true);
    reg(hudVars.tickLength, "plugin:hud-borders:tick_length", "Length of the corner ticks", 16, SIntValueOptions{.min = 0, .max = 512});
    reg(hudVars.tickInset, "plugin:hud-borders:tick_inset", "How far ornaments sit inside the inner line", 5, SIntValueOptions{.min = 0, .max = 128});

    reg(hudVars.tab, "plugin:hud-borders:tab", "Draw the heavier bar on the top-right cut", true);
    reg(hudVars.tabLength, "plugin:hud-borders:tab_length", "Length of the top-right bar", 34, SIntValueOptions{.min = 0, .max = 512});

    reg(hudVars.hatch, "plugin:hud-borders:hatch", "Draw the diagonal hatch in the bottom-right corner", true);
    reg(hudVars.hatchCount, "plugin:hud-borders:hatch_count", "Number of hatch strokes", 3, SIntValueOptions{.min = 0, .max = 16});
    reg(hudVars.hatchSize, "plugin:hud-borders:hatch_size", "Length of each hatch stroke", 18, SIntValueOptions{.min = 0, .max = 256});

    HyprlandAPI::reloadConfig();

    static auto P = Event::bus()->m_events.window.open.listen([&](PHLWINDOW w) { onNewWindow(w); });

    for (auto& w : Desktop::windowState()->windows()) {
        if (w->isHidden() || !w->m_isMapped)
            continue;

        HyprlandAPI::addWindowDecoration(PHANDLE, w, makeUnique<CHudFrame>(w));
    }

    HyprlandAPI::addNotification(PHANDLE, "[hud-borders] Initialized successfully!", CHyprColor{0.2, 1.0, 0.2, 1.0}, 4000);

    return {"hud-borders", "Sci-fi HUD window frames with per-corner chamfers and ornaments.", "cycclon", "0.1"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    g_pHyprRenderer->m_renderPass.removeAllOfType("CHudPassElement");
}
