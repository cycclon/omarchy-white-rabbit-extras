#pragma once
#include <hyprland/src/render/pass/PassElement.hpp>

class CHudFrame;

class CHudPassElement : public IPassElement {
  public:
    struct SHudData {
        CHudFrame* deco = nullptr;
        float      a    = 1.F;
    };

    CHudPassElement(const SHudData& data_);
    virtual ~CHudPassElement() = default;

    virtual std::vector<UP<IPassElement>> draw() override;
    virtual bool                          needsLiveBlur() override;
    virtual bool                          needsPrecomputeBlur() override;

    virtual const char*                   passName() override {
        return "CHudPassElement";
    }

    virtual ePassElementType type() override {
        return EK_CUSTOM;
    }

  private:
    SHudData data;
};
