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

// Space reserved on each edge, in logical px. Normally just the ring. With
// fit_content, also enough to keep the window content out of every cut and
// notch, so those show whatever is behind the window.
static SBoxExtents frameExtents() {
    const double t = ringThickness();
    if (!hudVars.fitContent->value())
        return {{t, t}, {t, t}};

    auto val = [](const SP<Config::Values::CIntValue>& v) { return static_cast<double>(std::max<Config::INTEGER>(0, v->value())); };

    // A notch steps in by its depth, so that edge gives up the same.
    const double L = val(hudVars.notchLeftLength) > 0 ? val(hudVars.notchLeftDepth) : 0.0;
    const double R = val(hudVars.notchRightLength) > 0 ? val(hudVars.notchRightDepth) : 0.0;

    // A 45-degree cut of depth c clears the content corner once the insets on
    // its two edges add up to c, less what the ring already gives: the ring's
    // inner edge sits t in from both edges, which is (2 - sqrt 2) * t further
    // along the cut's normal than the cut itself.
    const double RING = (2.0 - std::sqrt(2.0)) * t;
    auto         need = [RING](double c) { return std::max(0.0, c - RING); };

    double       top = std::max({0.0, need(val(hudVars.chamferTL)) - L, need(val(hudVars.chamferTR)) - R});
    double       bot = std::max({0.0, need(val(hudVars.chamferBL)) - L, need(val(hudVars.chamferBR)) - R});

    // The gauge rides the inside of the bottom line; keep it off the content.
    if (hudVars.gauge->value())
        bot = std::max(bot, val(hudVars.gaugeHeight) + val(hudVars.gaugeInset));

    return {{t + L, t + std::ceil(top)}, {t + R, t + std::ceil(bot)}};
}

static bool sameExtents(const SBoxExtents& a, const SBoxExtents& b) {
    return a.topLeft == b.topLeft && a.bottomRight == b.bottomRight;
}

SDecorationPositioningInfo CHudFrame::getPositioningInfo() {
    SDecorationPositioningInfo info;
    info.policy   = DECORATION_POSITION_STICKY;
    info.reserved = true;
    info.priority = 9990;
    info.edges    = DECORATION_EDGE_BOTTOM | DECORATION_EDGE_LEFT | DECORATION_EDGE_RIGHT | DECORATION_EDGE_TOP;

    if (!m_hasExtents) {
        m_lastExtents = frameExtents();
        m_hasExtents  = true;
    }
    info.desiredExtents = m_lastExtents;

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
    p.notchRStart  = std::clamp<Config::INTEGER>(hudVars.notchRightStart->value(), 0, 100) / 100.0;
    p.notchRLength = std::clamp<Config::INTEGER>(hudVars.notchRightLength->value(), 0, 100) / 100.0;
    p.notchRDepth  = std::max<Config::INTEGER>(0, hudVars.notchRightDepth->value()) * SCALE;
    p.notchLStart  = std::clamp<Config::INTEGER>(hudVars.notchLeftStart->value(), 0, 100) / 100.0;
    p.notchLLength = std::clamp<Config::INTEGER>(hudVars.notchLeftLength->value(), 0, 100) / 100.0;
    p.notchLDepth  = std::max<Config::INTEGER>(0, hudVars.notchLeftDepth->value()) * SCALE;
    p.ticks      = hudVars.ticks->value();
    p.tickLength = std::max<Config::INTEGER>(0, hudVars.tickLength->value()) * SCALE;
    p.tickInset  = std::max<Config::INTEGER>(0, hudVars.tickInset->value()) * SCALE;
    p.tab        = hudVars.tab->value();
    p.tabLength  = std::max<Config::INTEGER>(0, hudVars.tabLength->value()) * SCALE;
    p.hatch      = hudVars.hatch->value();
    p.hatchCount = static_cast<int>(hudVars.hatchCount->value());
    p.hatchSize  = std::max<Config::INTEGER>(0, hudVars.hatchSize->value()) * SCALE;
    p.gauge            = hudVars.gauge->value();
    p.gaugeFill        = hudVars.gaugeFill->value();
    p.gaugeStart       = std::clamp<Config::INTEGER>(hudVars.gaugeStart->value(), 0, 100) / 100.0;
    p.gaugeHeight      = std::max<Config::INTEGER>(0, hudVars.gaugeHeight->value()) * SCALE;
    p.gaugeLength      = std::max<Config::INTEGER>(0, hudVars.gaugeLength->value()) * SCALE;
    p.gaugeInset       = std::max<Config::INTEGER>(0, hudVars.gaugeInset->value()) * SCALE;
    p.gaugeStripes     = static_cast<int>(hudVars.gaugeStripes->value());
    p.gaugeStripeWidth = std::max<Config::INTEGER>(0, hudVars.gaugeStripeWidth->value()) * SCALE;
    p.gaugeGap         = std::max<Config::INTEGER>(0, hudVars.gaugeGap->value()) * SCALE;
    p.mask       = hudVars.mask->value();

    const auto EXTENTS = frameExtents();
    p.fitContent       = hudVars.fitContent->value();
    p.padL             = EXTENTS.topLeft.x * SCALE;
    p.padT             = EXTENTS.topLeft.y * SCALE;
    p.padR             = EXTENTS.bottomRight.x * SCALE;
    p.padB             = EXTENTS.bottomRight.y * SCALE;
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

    m_seExtents        = EXTENTS;
    m_bLastRelativeBox = CBox{0, 0, m_lastWindowSize.x, m_lastWindowSize.y}.addExtents(m_seExtents);

    // A config change that moves the insets has to re-lay-out the window.
    if (!sameExtents(EXTENTS, m_lastExtents)) {
        m_lastExtents = EXTENTS;
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
