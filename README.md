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

**Matching both outputs to 60Hz was the decisive fix.** This was confirmed live: the frozen screen recovered the instant DisplayPort-2 was set to 60Hz. It reduced the failures dramatically — from **16 `Page flip failed` events per boot down to a single isolated one**.

A residual freeze can still happen at 60Hz (one isolated event after ~43 min of uptime in testing). `dmesg` showed **no GPU reset, ring timeout, or fence error** — only the display-layer flip failure — which points at an `amdgpu` display presentation issue rather than the GPU itself locking up. A second, driver-level layer (see [Layered fix](#layered-fix)) addresses that residual.

### Diagnostic path (for reference)

Before landing on the refresh-rate cause, two earlier factors were investigated and corrected — they were contributing conditions, not the decisive fix:

1. **AMD overdrive** (`ppfeaturemask=0xFFF7FFFF`) plus `amdgpu.lockup_timeout=0`, which disabled the GPU's auto-recovery. These were installed following an incorrect "for LLM performance" recommendation. Overdrive does **not** accelerate LLM inference (Vulkan uses automatic DPM, not manual PowerPlay clocks). Both were reverted.
2. **`CLUTTER_VBLANK=none`** in `/etc/environment` to stop muffin/Clutter from stalling on page flips. It stayed active but was **not sufficient on its own** — the freeze returned with `Page flip failed` reappearing in the log.

The decisive fix was equalizing the refresh rates, backed by a driver-level parameter for the residual case.

## Diagnosis timeline

> This section is an honest log of how the diagnosis evolved. The `Page flip failed` symptom had **several layered causes**, and the investigation moved from software toward hardware as evidence accumulated. It is documented here because the same symptom can have very different root causes.

| Stage | Hypothesis | Action | Result |
|-------|-----------|--------|--------|
| 1 | AMD overdrive / disabled GPU auto-recovery | Reverted `ppfeaturemask` + `amdgpu.lockup_timeout=0` | Contributing factor, not decisive |
| 2 | Compositor stalling on page flips | `CLUTTER_VBLANK=none` | Active but insufficient — freeze returned |
| 3 | Mismatched refresh rates (60 vs 74.97Hz) | Force both outputs to 60Hz | **Big win** — `Page flip failed` 16 → 1 per boot |
| 4 | Driver-level flip presentation | `amdgpu.dcdebugmask=0x10` in GRUB | Applied; residual event still occurred |
| 5 | Unstable physical DisplayPort link | Unplugged the DP cable of the affected monitor | **Screen unfroze instantly** — points at the link |
| 6 | Bad cable/port vs. bad monitor | Moved the affected monitor from DP to **HDMI** | Problem persisted **and worsened** (`Page flip failed` climbed; see below) |

### Key evidence: corrupted EDID reads

The strongest clue came from repeated EDID re-detections in `Xorg.0.log`. A healthy monitor reports a **stable** EDID. This one did not:

```
AMDGPU(0): EDID vendor "GSM", prod id 23349
AMDGPU(0): EDID vendor "GSM", prod id 23348
AMDGPU(0): EDID vendor "GSM", prod id 23411
```

The **product id changes on each read** (23349 / 23348 / 23411), meaning the EDID bytes are arriving corrupted. This happened over **both** the DisplayPort and HDMI inputs, which shifts the prime suspect away from a single cable or GPU port and toward the **monitor itself** (its input/EDID circuitry or power delivery).

**Current working hypothesis:** the affected monitor (an LG / "GSM" panel) has a failing video input or unstable power, corrupting link negotiation regardless of the input used. The software layers below **mitigate** the symptom but do not cure it. Investigation is ongoing — see [Testing status](#testing-status).

## The fix

Force DisplayPort-2 to 60Hz so both monitors share the same refresh rate:

```bash
xrandr --output DisplayPort-2 --mode 1920x1080 --rate 60.00
```

Because `xrandr` settings are **not persistent** across reboots or monitor hotplug, this project ships a single script that applies the fix, persists it at login, and bundles the recovery/diagnostic helpers.

## Layered fix

The freeze is addressed in two complementary layers. Apply them in order, one at a time, verifying each before moving on.

### Layer 1 — Equal refresh rates (primary fix)

Force both monitors to 60Hz. This is what the bundled script automates and what removed the vast majority of the failures. See [Usage](#usage) and [Make it permanent](#make-it-permanent).

### Layer 2 — Driver parameter for the residual (GRUB)

For the isolated event that can still occur at 60Hz, add an `amdgpu` debug mask to the kernel command line. This stabilizes display page flips at the driver level.

```bash
# 1. Back up the current GRUB config
sudo cp /etc/default/grub ~/grub-backup-$(date +%Y%m%d-%H%M%S).bak

# 2. Add amdgpu.dcdebugmask=0x10 to GRUB_CMDLINE_LINUX_DEFAULT, keeping amdgpu.dc=1
#    Target line should read:
#    GRUB_CMDLINE_LINUX_DEFAULT="quiet splash amdgpu.dc=1 amdgpu.dcdebugmask=0x10"
sudoedit /etc/default/grub

# 3. Regenerate GRUB and reboot
sudo update-grub
sudo reboot

# 4. After reboot, verify the parameter is active
cat /proc/cmdline   # should contain amdgpu.dcdebugmask=0x10
```

To roll back, restore the backup and run `sudo update-grub`.

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
| 2 | **Unfreeze the screen** — restarts Cinnamon (detached) without closing windows, then exits the script |
| 3 | **Show refresh rates** — lists both monitors and their active mode |
| 4 | **Revert the fix** — removes the login autostart entry |
| 5 | **Install/repair autostart** — writes a `.desktop` that applies 60Hz at every login |

### Make it permanent

Run option **5** once. It installs `~/.config/autostart/pantalla-displayport.desktop`, which calls the script in `--autostart` mode at every login (with a short delay so the display is initialized first) and logs to `~/.local/share/pantalla-displayport.log`.

### Emergency recovery

If the screen freezes, use the script's unfreeze option — it restarts Cinnamon fully detached from the terminal and exits cleanly, so it won't hang:

```bash
./scripts/pantalla-displayport.sh 2
```

Or, from any terminal (or a TTY via `Ctrl+Alt+F2`), the equivalent one-liner:

```bash
setsid nohup cinnamon --replace -d :0 >/dev/null 2>&1 &
```

> **Note:** `cinnamon --replace` restarts the compositor, which kills the Cinnamon instance that owns your terminal. Detaching it (`setsid nohup ... &`) is required — a bare `cinnamon --replace &` leaves the calling shell/menu hanging when the parent desktop dies. The desktop will flicker; that's expected.

## Testing status

This is a personal, single-developer fix validated on the real hardware above.

- ✅ **Root cause confirmed live** — the frozen screen recovered the exact moment DisplayPort-2 was set to 60Hz.
- ✅ **Layer 1 effective** — reduced `Page flip failed` from 16 per boot to a single isolated event.
- ✅ **Autostart verified** — `--autostart` mode runs at login, applies 60Hz, and logs the result (`OK: DisplayPort-2 -> 1920x1080@60.00Hz`).
- ✅ **Unfreeze fixed** — option 2 now detaches Cinnamon and exits, resolving a hang where the interactive menu looped after the desktop restarted.
- ✅ **Script syntax** — passes `bash -n` with no errors.
- ✅ **Physical link implicated** — unplugging the affected monitor's cable unfroze the screen instantly.
- ⚠️ **Not fully solved** — the software layers mitigate but do not cure it. Switching the monitor from DisplayPort to HDMI did **not** help (it got worse), and EDID reads are corrupted on both inputs — the current suspect is the monitor itself.
- 🔲 **Hardware isolation pending** — test the suspect monitor on another machine (or swap the two monitors' ports) to confirm monitor vs. GPU, and check the monitor's power supply.

### Hardware troubleshooting (current focus)

The evidence now points at the physical link / monitor rather than software. Work through these, cheapest first:

1. **Reseat the cable** firmly at both ends.
2. **Swap cables and ports** — if the fault follows the monitor, it's the monitor; if it stays on the port, it's the GPU/cable.
3. **Test the suspect monitor on another computer** — the definitive isolation test.
4. **Check the monitor's power supply** — a monitor that resets under unstable power produces exactly this corrupted-EDID / re-detection pattern.

Keep the software layers (60Hz + `dcdebugmask`) in place meanwhile — they reduce the symptom's frequency and cause no harm.

## Adapting to your setup

The script's configuration lives in variables at the top of `scripts/pantalla-displayport.sh`:

```bash
OUTPUT="DisplayPort-2"   # your secondary output name (check with: xrandr --query)
MODE="1920x1080"         # resolution
RATE="60.00"             # target refresh rate to match your primary
```

## License

[MIT](./LICENSE)
