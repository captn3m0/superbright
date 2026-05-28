# superbright

A single-file CLI service that unlocks the increased brightness (1000 nits) of
XDR displays on supported Macs.

This is a minimal fork of [BrightIntosh](https://github.com/niklasr22/BrightIntosh) by
Niklas Rousset (<https://www.brightintosh.de>) that strips out the GUI and
configuration options.

> [!IMPORTANT]
> This tool should not harm your display as it doesn't use any low-level API
> calls and your OS is in full control over the display, but there is no
> warranty.

## Compatible devices

(Same as BrightIntosh)

- MacBook Pro M5 (Mac17,2 / Mac17,6 / Mac17,7 / Mac17,8 / Mac17,9)
- MacBook Pro M4 (Mac16,1 / Mac16,5 / Mac16,6 / Mac16,7 / Mac16,8)
- MacBook Pro M3 (Mac15,3 / Mac15,6 / Mac15,7 / Mac15,8 / Mac15,9 / Mac15,10 / Mac15,11)
- MacBook Pro M2 14"/16" (Mac14,5 / Mac14,6 / Mac14,9 / Mac14,10)
- MacBook Pro M1 14"/16" (MacBookPro18,1 / MacBookPro18,2 / MacBookPro18,3 / MacBookPro18,4)
- Pro Display XDR
- Studio Display XDR (experimental)

## Build

```sh
make
```

Produces a `./superbright` binary. Requires Xcode command-line tools (`swiftc`).

## Install

```sh
make install            # installs to ~/.local/bin/superbright
make uninstall          # removes it
```

Override the install prefix with `PREFIX=...`.

## Usage

```sh
superbright                  # foreground, brightness boosted until Ctrl-C
superbright -d               # detach into background and exit
superbright --help
```

The CLI has no toggle command. To turn brightness off, kill the process
(`Ctrl-C`, `kill <pid>`, `launchctl bootout`, `brew services stop`, …). Gamma
is restored automatically on exit.

## Run as a service

### Homebrew

(WIP)

If installed via a formula that registers a service, use:

```sh
brew services start superbright
brew services stop superbright
```

### LaunchAgent

(Untested)

Drop the following plist at `~/Library/LaunchAgents/superbright.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>superbright</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/bin/superbright</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/tmp/superbright.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/superbright.log</string>
</dict>
</plist>
```

Load and unload it with:

```sh
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/superbright.plist
launchctl bootout   gui/$(id -u)/superbright
```

## How it works

Two things happen on supported displays:

1. A 1×1, transparent, always-on-top Metal window is opened with
   `wantsExtendedDynamicRangeContent = true` to engage the display's HDR mode.
2. Once HDR is engaged, the display's gamma table is captured as a baseline and
   re-uploaded with each value scaled by a per-display factor derived from
   `NSScreen.maximumExtendedDynamicRangeColorComponentValue`.

Both effects are tied to the running process. macOS restores the original gamma
when the process exits, and the overlay window vanishes with it.

## Known issues

(Same as Brightintosh)

- Conflicts with apps that also drive the gamma table (f.lux, Lunar, Vivid,
  MonitorControl, BetterDisplay, Iris, …).
- HDR videos will clip while superbright is active.

## Credits

If you want a polished GUI app with a menu bar item, hotkeys, settings, and an
App Store build, use the upstream project:

- Source: <https://github.com/niklasr22/BrightIntosh>
- Website: <https://www.brightintosh.de>

If you'd like to support this work, please [purchase BrightIntosh](https://apple.co/3r0Ghqm) or 
[sponsor Niklas](https://github.com/sponsors/niklasr22).

## License

GNU GPL 3. See `LICENSE` file for details.
