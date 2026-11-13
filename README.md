# gg.saver

A macOS screensaver in ggplot2's visual language. It has two scenes.

- **Shape fall.** The 26 `pch` shapes tumble into the panel and pile up, and then the floor opens so they drain away. Physics runs on SpriteKit (`SKPhysicsWorld`), with a body for each shape that matches its outline. The panel sits inside a white plot margin, as in a saved ggplot.
- **Lava lamp.** A `geom_density_2d_filled()` of a few blobs of wax on a `theme_grey()` panel. Blobs warm at the bottom, rise, cool at the top and sink, and the density bands merge and split as they pass each other. The lowest band is left clear so the panel shows through. A shader draws the density on the GPU.

## Options

Below Scene, the sheet shows only the selected scene's options.

- **Scene.** Shape fall or Lava lamp.
- **Shape fall**
  - **Theme.** The panel of `theme_grey()`, `theme_bw()` or `theme_classic()`.
  - **Colour.** Black shapes, or a random colour from `hue_pal()` for each shape.
  - **Fill time.** How long the pile takes to fill: 15 s, 30 s, 1 min or 2 min.
- **Lava lamp**
  - **Palette.** viridis, magma, plasma, mako or turbo, as `viridisLite::viridis(8, option = …)` gives them.

## Build

Needs macOS 14 or later and the Xcode command line tools.

```sh
./build.sh            # builds build/gg.saver.saver
./build.sh --install  # also installs it for the current user
```

After a reinstall, close and reopen System Settings if it still shows the old version.
