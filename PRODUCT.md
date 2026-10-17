# Product

<!-- impeccable:product-schema 1 -->

## Platform

Native macOS desktop utility.

## Stack

Swift and AppKit, selected for direct access to native macOS window and input APIs. Swift Package Manager; no external dependencies.

## Users

Nicolas, who wants OpenBox-style window manipulation on his Mac.

## Product Purpose

Move a window from anywhere inside it using a modifier and the left mouse button. Resize it using the same modifier and the right mouse button.

## Operating Context

Separate project in `/Users/nicolas/dev/glissando`, with no spaces in the project directory. Runs alongside Walkie Talkie. Interacts with windows under the pointer across multiple monitors.

## Capabilities and Constraints

- Native menu bar controls and Accessibility permission setup.
- No microphone, screenshots, network requests, or third-party dependencies.
- Fixed-size and fullscreen windows may refuse manipulation through Accessibility.
- Factory default is Option. The user selected Control in the running app; Option and Command remain available in the menu. Control overlaps Walkie Talkie’s screenshot gesture while that app is recording.
- Distribution and automatic installation are not requested.

## Product Principles

- Preserve normal mouse interaction when the configured modifier is not held.
- Keep the pointer responsive even if another app does not respond.
- Work on the window under the pointer, rather than assuming the focused window.
- Use native macOS controls, menu conventions, typography, and appearances.

## Brand Commitments

The app is named **Glissando**, chosen by Nicolas. The project directory is `glissando`, without spaces.
