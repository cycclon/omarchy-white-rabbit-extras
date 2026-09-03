#include "HudFrame.hpp"

#include <algorithm>
#include <cmath>

#include <libdrm/drm_fourcc.h>

#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/OpenGL.hpp>
#include <hyprland/src/render/gl/GLTexture.hpp>
#include <hyprutils/memory/Casts.hpp>

using namespace Hyprutils::Memory;
using namespace Render::GL;

#include "HudPassElement.hpp"
#include "globals.hpp"

CHudFrame::CHudFrame(PHLWINDOW pWindow) : IHyprWindowDecoration(pWindow), m_pWindow(pWindow) {
    m_lastWindowPos  = pWindow->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
    m_lastWindowSize = pWindow->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
}

CHudFrame::~CHudFrame() {
    damageEntire();
}

static double ringThickness() {
    return std::max<Config::INTEGER>(0, hudVars.outerThickness->value()) + std::max<Config::INTEGER>(0, hudVars.gap->value()) +
        std::max<Config::INTEGER>(0, hudVars.innerThickness->value());
}

SDecorationPositioningInfo CHudFrame::getPositioningInfo() {
    SDecorationPositioningInfo info;
    info.policy   = DECORATION_POSITION_STICKY;
    info.reserved = true;
    info.priority = 9990;
    info.edges    = DECORATION_EDGE_BOTTOM | DECORATION_EDGE_LEFT | DECORATION_EDGE_RIGHT | DECORATION_EDGE_TOP;

    const double size   = m_fLastThickness == 0 ? ringThickness() : m_fLastThickness;
    info.desiredExtents = {{size, size}, {size, size}};
    m_fLastThickness    = size;

    return info;
}

void CHudFrame::onPositioningReply(const SDecorationPositioningReply& reply) {
    m_bAssignedGeometry = reply.assignedGeometry;
}

uint64_t CHudFrame::getDecorationFlags() {
    return DECORATION_PART_OF_MAIN_WINDOW;
}

eDecorationLayer CHudFrame::getDecorationLayer() {
    return DECORATION_LAYER_OVER;
}

std::string CHudFrame::getDisplayName() {
    return "HUD Frame";
}

eDecorationType CHudFrame::getDecorationType() {
    return DECORATION_CUSTOM;
}

void CHudFrame::draw(PHLMONITOR pMonitor, const float& a) {
    if (!validMapped(m_pWindow))
        return;

    const auto PWINDOW = m_pWindow.lock();

    if (!PWINDOW->m_ruleApplicator->decorate().valueOrDefault())
        return;

    CHudPassElement::SHudData data;
    data.deco = this;
    data.a    = a;

    g_pHyprRenderer->m_renderPass.add(makeUnique<CHudPassElement>(data));
}

void CHudFrame::rebuildTexture(const SFrameParams& p) {
    auto* surf = renderHudFrame(p);
    if (!surf) {
        m_tex = nullptr;
        return;
    }

    auto* data   = cairo_image_surface_get_data(surf);
    auto  stride = cairo_image_surface_get_stride(surf);

    // Cairo's ARGB32 is premultiplied BGRA in memory on little-endian, which is
    // exactly DRM_FORMAT_ARGB8888.
    m_tex = makeShared<CGLTexture>(DRM_FORMAT_ARGB8888, data, stride, Vector2D{(double)p.w, (double)p.h});

    cairo_surface_destroy(surf);

    m_lastParams = p;
    m_hasParams  = true;
}

void CHudFrame::drawPass(PHLMONITOR pMonitor, const float& a) {
    const auto PWINDOW = m_pWindow.lock();
    if (!PWINDOW || !pMonitor)
        return;

    const double thickness = ringThickness();
    if (thickness <= 0)
        return;

    const auto PWORKSPACE      = PWINDOW->m_workspace;
    const auto WORKSPACEOFFSET = PWORKSPACE && !PWINDOW->m_pinned ? PWORKSPACE->m_renderOffset->value() : Vector2D();

    CBox       fullBox = m_bAssignedGeometry;
    fullBox.translate(g_pDecorationPositioner->getEdgeDefinedPoint(DECORATION_EDGE_BOTTOM | DECORATION_EDGE_LEFT | DECORATION_EDGE_RIGHT | DECORATION_EDGE_TOP, PWINDOW));
    fullBox.translate(PWINDOW->m_floatingOffset - pMonitor->m_position + WORKSPACEOFFSET);

    if (fullBox.width < 1 || fullBox.height < 1)
        return;

    fullBox.scale(pMonitor->m_scale).round();

    const double SCALE   = pMonitor->m_scale;
    const bool   FOCUSED = Desktop::focusState()->window() == PWINDOW;

    const CHyprColor INNERCOL{static_cast<uint64_t>(FOCUSED ? hudVars.colActive->value() : hudVars.colInactive->value())};
    const CHyprColor OUTERCOL{static_cast<uint64_t>(FOCUSED ? hudVars.colOuterActive->value() : hudVars.colOuterInactive->value())};
    const CHyprColor MASKCOL{static_cast<uint64_t>(hudVars.colMask->value())};

    SFrameParams p;
    p.w          = static_cast<int>(fullBox.width);
    p.h          = static_cast<int>(fullBox.height);
    p.outer      = std::max<Config::INTEGER>(0, hudVars.outerThickness->value()) * SCALE;
    p.gap        = std::max<Config::INTEGER>(0, hudVars.gap->value()) * SCALE;
    p.inner      = std::max<Config::INTEGER>(0, hudVars.innerThickness->value()) * SCALE;
    p.chamTL     = std::max<Config::INTEGER>(0, hudVars.chamferTL->value()) * SCALE;
    p.chamTR     = std::max<Config::INTEGER>(0, hudVars.chamferTR->value()) * SCALE;
    p.chamBR     = std::max<Config::INTEGER>(0, hudVars.chamferBR->value()) * SCALE;
    p.chamBL     = std::max<Config::INTEGER>(0, hudVars.chamferBL->value()) * SCALE;
    p.ticks      = hudVars.ticks->value();
    p.tickLength = std::max<Config::INTEGER>(0, hudVars.tickLength->value()) * SCALE;
    p.tickInset  = std::max<Config::INTEGER>(0, hudVars.tickInset->value()) * SCALE;
    p.tab        = hudVars.tab->value();
    p.tabLength  = std::max<Config::INTEGER>(0, hudVars.tabLength->value()) * SCALE;
    p.hatch      = hudVars.hatch->value();
    p.hatchCount = static_cast<int>(hudVars.hatchCount->value());
    p.hatchSize  = std::max<Config::INTEGER>(0, hudVars.hatchSize->value()) * SCALE;
    p.mask       = hudVars.mask->value();
    p.mr         = MASKCOL.r;
    p.mg         = MASKCOL.g;
    p.mb         = MASKCOL.b;
    p.ma         = MASKCOL.a;
    p.ir         = INNERCOL.r;
    p.ig         = INNERCOL.g;
    p.ib         = INNERCOL.b;
    p.ia         = INNERCOL.a;
    p.or_        = OUTERCOL.r;
    p.og         = OUTERCOL.g;
    p.ob         = OUTERCOL.b;
    p.oa         = OUTERCOL.a;

    if (p.w < 2 || p.h < 2)
        return;

    if (!m_hasParams || !(p == m_lastParams) || !m_tex || m_tex->m_texID == 0)
        rebuildTexture(p);

    if (!m_tex)
        return;

    g_pHyprOpenGL->scissor(nullptr);
    g_pHyprOpenGL->renderTexture(m_tex, fullBox, {.a = a});

    m_seExtents        = {{thickness, thickness}, {thickness, thickness}};
    m_bLastRelativeBox = CBox{0, 0, m_lastWindowSize.x, m_lastWindowSize.y}.addExtents(m_seExtents);

    if (thickness != m_fLastThickness) {
        m_fLastThickness = thickness;
        g_pDecorationPositioner->repositionDeco(this);
    }
}

void CHudFrame::updateWindow(PHLWINDOW pWindow) {
    m_lastWindowPos  = pWindow->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
    m_lastWindowSize = pWindow->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT);

    damageEntire();
}

void CHudFrame::damageEntire() {
    CBox dm = m_bLastRelativeBox.copy().translate(m_lastWindowPos).expand(2);
    g_pHyprRenderer->damageBox(dm);
}
