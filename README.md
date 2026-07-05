# problemscreen

Fix and management tooling for an intermittent **DisplayPort screen freeze** on Linux Mint with an AMD Radeon RX 6700 XT.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash-4EAA25.svg?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Platform: Linux Mint](https://img.shields.io/badge/Platform-Linux%20Mint-87CF3E.svg?logo=linuxmint&logoColor=white)](https://linuxmint.com/)

## The problem

On a dual-monitor setup, the secondary screen connected over **DisplayPort** would **freeze intermittently**. The freeze happened mostly under load — heavy terminal scrolling/output or browsing — and could only be recovered by power-cycling the monitor or switching desktops.

**Environment where this was diagnosed:**

| Component | Value |
|-----------|-------|
| OS | Linux Mint 22.3 |
| GPU | AMD Radeon RX 6700 XT (Navi 22) |
| Driver | `amdgpu` |
| Session | X11 |
| Kernel | 6.17 |
| Monitors | DisplayPort-1 @ 60Hz (primary) + DisplayPort-2 @ 74.97Hz |

## Root cause

The two monitors were running at **mismatched refresh rates**: DisplayPort-1 at **60Hz** and DisplayPort-2 at **74.97Hz**. The `amdgpu` driver could not reliably synchronize page flips across the two unaligned clocks, and under load it failed them. The signature in `Xorg.0.log`:

```
AMDGPU(0): Page flip failed: Invalid argument
drmmode_do_crtc_dpms cannot get last vblank counter
```

**Matching both outputs to 60Hz eliminated the freeze.** This was confirmed live: the frozen screen recovered the instant DisplayPort-2 was set to 60Hz.

### Diagnostic path (for reference)

Before landing on the refresh-rate cause, two earlier factors were investigated and corrected — they were contributing conditions, not the decisive fix:

1. **AMD overdrive** (`ppfeaturemask=0xFFF7FFFF`) plus `amdgpu.lockup_timeout=0`, which disabled the GPU's auto-recovery. These were installed following an incorrect "for LLM performance" recommendation. Overdrive does **not** accelerate LLM inference (Vulkan uses automatic DPM, not manual PowerPlay clocks). Both were reverted.
2. **`CLUTTER_VBLANK=none`** in `/etc/environment` to stop muffin/Clutter from stalling on page flips. It stayed active but was **not sufficient on its own** — the freeze returned with `Page flip failed` reappearing in the log.

The decisive fix was equalizing the refresh rates.

## The fix

Force DisplayPort-2 to 60Hz so both monitors share the same refresh rate:

```bash
xrandr --output DisplayPort-2 --mode 1920x1080 --rate 60.00
```

Because `xrandr` settings are **not persistent** across reboots or monitor hotplug, this project ships a single script that applies the fix, persists it at login, and bundles the recovery/diagnostic helpers.

## Usage

```bash
# Interactive menu
./scripts/pantalla-displayport.sh

# Direct mode (run one option without the menu)
./scripts/pantalla-displayport.sh 1        # options 1-5

# Autostart mode (used by the .desktop entry at login)
./scripts/pantalla-displayport.sh --autostart
```

### Menu options

| Option | Action |
|--------|--------|
| 1 | **Apply 60Hz now** — hot fix, sets DisplayPort-2 to 60Hz immediately |
| 2 | **Unfreeze the screen** — restarts Cinnamon (`cinnamon --replace`) without closing windows |
| 3 | **Show refresh rates** — lists both monitors and their active mode |
| 4 | **Revert the fix** — removes the login autostart entry |
| 5 | **Install/repair autostart** — writes a `.desktop` that applies 60Hz at every login |

### Make it permanent

Run option **5** once. It installs `~/.config/autostart/pantalla-displayport.desktop`, which calls the script in `--autostart` mode at every login (with a short delay so the display is initialized first) and logs to `~/.local/share/pantalla-displayport.log`.

### Emergency recovery

If the screen freezes, from any terminal (or a TTY via `Ctrl+Alt+F2`):

```bash
cinnamon --replace -d :0 &
```

## Testing status

This is a personal, single-developer fix validated on the real hardware above.

- ✅ **Root cause confirmed live** — the frozen screen recovered the exact moment DisplayPort-2 was set to 60Hz.
- ✅ **Autostart verified** — `--autostart` mode runs at login, applies 60Hz, and logs the result (`OK: DisplayPort-2 -> 1920x1080@60.00Hz`).
- ✅ **Script syntax** — passes `bash -n` with no errors.
- 🔲 **Observation phase** — 2–3 days of heavy real-world use (terminal scroll, browsing) without a freeze to consider the case fully closed.

### If the freeze ever returns at 60Hz

Fallback plans, in order (one change at a time):

- **Plan B** — add `amdgpu.dcdebugmask=0x10` to the kernel line in GRUB (more invasive, keeps 74.97Hz).
- **Plan C** — already applied here: force both monitors to 60Hz.

## Adapting to your setup

The script's configuration lives in variables at the top of `scripts/pantalla-displayport.sh`:

```bash
OUTPUT="DisplayPort-2"   # your secondary output name (check with: xrandr --query)
MODE="1920x1080"         # resolution
RATE="60.00"             # target refresh rate to match your primary
```

## License

[MIT](./LICENSE)
