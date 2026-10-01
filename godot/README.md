# Cartoon Solar System: an interactive tour in Godot 4.7

An interactive version of the Blender scene built by
[`blender/build_solar_system.py`](../blender/build_solar_system.py). It uses the
same sizes, distances, turns per loop (20 s), axial tilts, and colors,
converted from Z-up to Y-up. Everything is generated in code: there are no
binary or imported assets.

All in-game text (interface, labels, and fact cards) is in Colombian Spanish
(es_CO). This documentation is in English; button names below are given as they
appear on screen, with a translation in parentheses.

## How to use it

- **Click a planet, the Moon, or the Sun:** the camera flies to it, follows it
  along its orbit, and shows its fact card with real data.
- **Left/right arrow keys** or the *Anterior* and *Siguiente* (Previous and
  Next) buttons: tour the bodies in order: Sun, Mercury, Venus, Earth, Moon,
  Mars, Jupiter, Saturn, Uranus, and Neptune.
- **Esc** or *Vista general* (Overview): return to the framing of the Blender
  animation.
- **Drag:** orbit the camera. **Mouse wheel:** zoom in or out.
- **Space** or *Pausa* (Pause): stop time. The slider changes the speed. During
  the tour, time runs at x0.25 so each body is easy to see.

## Structure

| File | Contents |
|---|---|
| `scripts/solar_data.gd` | Visual parameters and fact cards for every body |
| `scripts/brand.gd` | OpenSAI identity: palette, Roboto typeface, and an emblem and icons rasterized in code |
| `scripts/main.gd` | Scene construction, tour camera, input, and interface |
| `shaders/toon_planet.gdshader` | Light-free cel shading: the terminator comes from dot(normal, direction to the Sun) |
| `shaders/outline.gdshader` | Inverted-hull outline |
| `shaders/sun.gdshader` | A Sun whose face always looks at the camera and blinks |
| `shaders/sun_corona.gdshader` | Spinning rays with an outline and a halo |
| `shaders/orbit_dashed.gdshader`, `saturn_rings.gdshader`, `starry_sky.gdshader` | Orbits, rings, and sky |
| `tests/tour_test.gd` | Headless test of the tour, clicks, fact cards, and pause |

## Tests

`tests/tour_test.gd` steps through the tour with the keyboard, clicks five
planets through the viewport, and checks the fact cards, pause, and the
*Cerrar* (Close) button. From this folder:

```sh
godot --headless --path . -s tests/tour_test.gd
```

It should end with `SOLAR_TOUR_OK` (23 checks). Headless mode uses a null
renderer, so it does not compile the shaders. Check the visuals with F5 in the
editor or in the web build.

## Branding and license

The interface follows the [OpenSAI](https://opensai.org) identity: brand blue
`#3180c2`, top bar `#1867a9`, orange `#ef6c00` for actions and accents, navy
`#0b2d4a` for panels, the Roboto typeface (falling back to Noto Sans or DejaVu
Sans when it is not installed), and the glider emblem as the icon. Titles sit
between braces, `{ ... }`, as on the website.

The code is MIT, the same license as Godot Engine: it is the most compatible
choice and allows exporting to any platform. See `LICENSE`, which also carries
the Godot notice that must accompany every exported copy. The attribution
caption appears in the bottom-left corner of the game.

## Web export

The "Web" preset in `export_presets.cfg` writes `../docs/index.html` with its
`.js`, `.wasm`, and `.pck` files into the folder that GitHub Pages publishes.
The "Linux" preset produces a single executable in `../build/linux/`, which git
ignores. The web build is the no-threads variant, so it needs no COOP/COEP
headers and works on any static host. It must be served over HTTP; it does not
load from `file://`.

- On the web, Godot always uses the Compatibility renderer (WebGL 2), not
  Forward+. The cel shading does not depend on lights, but the Sun's glow and
  halo may look slightly different than on desktop.
- The *Cerrar* (Close) button is hidden on the web, because `quit()` would only
  freeze the canvas.
- `SystemFont` cannot reach system fonts in the browser, so text uses Godot's
  default font instead of Roboto.
