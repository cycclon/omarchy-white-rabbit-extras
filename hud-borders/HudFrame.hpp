#pragma once

#define WLR_USE_UNSTABLE

#include <hyprland/src/render/decorations/IHyprWindowDecoration.hpp>
#include <hyprland/src/render/Texture.hpp>

#include "FrameArt.hpp"

class CHudFrame : public IHyprWindowDecoration {
  public:
    CHudFrame(PHLWINDOW);
    virtual ~CHudFrame();

    virtual SDecorationPositioningInfo getPositioningInfo();
    virtual void                       onPositioningReply(const SDecorationPositioningReply& reply);
    virtual void                       draw(PHLMONITOR, float const& a);
    virtual eDecorationType            getDecorationType();
    virtual void                       updateWindow(PHLWINDOW);
    virtual void                       damageEntire();
    virtual uint64_t                   getDecorationFlags();
    virtual eDecorationLayer           getDecorationLayer();
    virtual std::string                getDisplayName();

  private:
    void                 drawPass(PHLMONITOR, float const& a);
    void                 rebuildTexture(const SFrameParams& p);

    SBoxExtents          m_seExtents;
    PHLWINDOWREF         m_pWindow;

    CBox                 m_bLastRelativeBox;
    CBox                 m_bAssignedGeometry;

    Vector2D             m_lastWindowPos;
    Vector2D             m_lastWindowSize;

    SBoxExtents          m_lastExtents = {};
    bool                 m_hasExtents  = false;

    // The rendered frame is cached and only redrawn when something it depends
    // on actually changes -- size, focus, or any config value.
    SP<Render::ITexture> m_tex;
    SFrameParams         m_lastParams;
    bool                 m_hasParams = false;

    friend class CHudPassElement;
};
