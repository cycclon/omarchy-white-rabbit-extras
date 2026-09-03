#include "HudPassElement.hpp"
#include <hyprland/src/render/OpenGL.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include "HudFrame.hpp"

CHudPassElement::CHudPassElement(const CHudPassElement::SHudData& data_) : data(data_) {
    ;
}

std::vector<UP<IPassElement>> CHudPassElement::draw() {
    data.deco->drawPass(g_pHyprRenderer->m_renderData.pMonitor.lock(), data.a);
    return {};
}

bool CHudPassElement::needsLiveBlur() {
    return false;
}

bool CHudPassElement::needsPrecomputeBlur() {
    return false;
}
