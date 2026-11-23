# RIFT Client

The client is an Odin + Karl2D desktop/WebAssembly shell. Its current screen is an offline rendering preview built from deterministic setup data in `logicEngine`; it does not send game actions or claim to hold authoritative state. The player-count menu stays collapsed until opened. Hex details follow the hovered tile; clicking pins the current tile, clicking it again unpins it, and clicking elsewhere clears the pin.

## Commands

- `./check.ps1` generates the mark atlas and runs `odin check . -vet`.
- `./build.ps1` generates the atlas and builds the desktop executable.
- `./run.ps1` generates the atlas and runs the desktop preview.
- `./build_web.ps1` generates the atlas and creates `bin/web` output.
- `python tools/generate_assets.py` regenerates `assets/rift_marks.png` by itself.

The standard-library generator creates a transparent, limited-palette pixel-art atlas for terrain, factions, structures, and relays. Each mark is hand-authored as a small pixel grid; there is no random generation or decorative background art. The interface uses Karl2D's default font for readability, with chunky, muted board and panel shapes rather than thin HUD lines or neon effects.
