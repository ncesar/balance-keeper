# BalanceKeeper

Small menu bar app for macOS that keeps the audio balance (left/right) always in the center.

Some app on my Mac kept moving the balance to the left and I never found which one. It was really annoying, so I made this. It stays in the menu bar doing nothing, and when something changes the balance it puts it back to the center.

## How it works

- Listens for balance changes on the default output device using CoreAudio. No polling, it only runs when the balance actually changes.
- When the output device changes (bluetooth headphone, HDMI, etc) it starts to listen the new one.
- Every correction goes to `~/Library/Logs/BalanceKeeper.log`, with the app in focus and the apps playing audio at that moment. macOS doesn't say who changed the balance, so this is only a hint to find the culprit.

## Requirements

- macOS 14.4 or newer
- Xcode Command Line Tools (`xcode-select --install`)

## Build and install

```sh
./build.sh
cp -R build/BalanceKeeper.app /Applications/
open /Applications/BalanceKeeper.app
```

A headphone icon will show up in the menu bar. Click on it and check "Abrir no login" if you want it to start with the Mac.

## Menu

The menu is in portuguese:

- **Manter centralizado**: turn it on/off
- **Abrir no login**: start with the Mac
- **Abrir log**: open the log file
- **Sair**: quit

## Testing

With the app running:

```sh
swift check.swift
```

It moves the balance all the way to the left and checks if it is back in the center after 1 second. If the app is not running (or is paused) the balance will stay on the left, so run it only with the app on.

## Notes

- The build shows some deprecation warnings for `AudioHardwareService*`. These functions are deprecated since macOS 10.11 but they still work, and I didn't find other way to change the balance.
- The app is only ad-hoc signed. It's made for personal use, build it on your own machine.
