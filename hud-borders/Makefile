ifeq ($(CXX),g++)
    EXTRA_FLAGS = --no-gnu-unique
else
    EXTRA_FLAGS =
endif

CXXFLAGS ?= -O2
CXXFLAGS += -shared -fPIC -std=c++2b

PKGS = pixman-1 libdrm hyprland pangocairo cairo libinput libudev wayland-server xkbcommon

all:
	$(CXX) $(CXXFLAGS) $(LDFLAGS) $(EXTRA_FLAGS) main.cpp HudFrame.cpp HudPassElement.cpp FrameArt.cpp -o hud-borders.so `pkg-config --cflags --libs $(PKGS)`

clean:
	rm -f ./hud-borders.so
