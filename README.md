# gg.saver

A macOS screensaver in ggplot2's visual language. It has two scenes.

- **Shape fall.** The 26 `pch` shapes tumble into the panel and pile up, and then the floor opens so they drain away. Physics runs on SpriteKit (`SKPhysicsWorld`), with a body for each shape that matches its outline.
- **Warning rain.** ggplot2's exported functions, or its warnings and errors, run down a `theme_grey()` panel in columns, like the rain in The Matrix. A glowing head of scrambling glyphs slides down each column, and the message decodes just behind it. Columns sit at random depths, so far ones are smaller, fainter and slower.

## Options

Below Scene, the sheet shows only the selected scene's options.

- **Scene.** Shape fall or Warning rain.
- **Shape fall**
  - **Theme.** The panel of any ggplot2 complete theme, from `theme_grey()` to `theme_void()`.
  - **Colour.** Black shapes, or a random colour from `hue_pal()` for each shape.
  - **Fill time.** How long the pile takes to fill: 15 s, 30 s, 1 min or 2 min.
- **Warning rain**
  - **Text.** Functions (dark green by default) or Warnings and errors (dark red by default).
  - **Colour.** The text's default colour, or a random colour from `hue_pal()` for each column.

## Build

Needs macOS 14 or later and the Xcode command line tools.

```sh
./build.sh            # builds build/gg.saver.saver
./build.sh --install  # also installs it for the current user
```

After a reinstall, close and reopen System Settings if it still shows the old version.

## Messages

`GGSaver/Resources/functions.txt` and `messages.txt` are generated from ggplot2's sources. The functions come from `NAMESPACE`. The messages cover the `cli_warn()`, `cli_inform()`, `cli_abort()` and `deprecate()` calls with literal text, plus a few warnings that ggplot2 builds with `paste0()`. Sample values for the inline `{expressions}` live in `VALUES` in the script. To refresh both files:

```sh
git clone --depth 1 https://github.com/tidyverse/ggplot2.git /tmp/ggplot2
python3 tools/extract_messages.py /tmp/ggplot2 GGSaver/Resources
```
