# Glissando interface

Native macOS utility conventions are the visual authority. This is a narrow operational surface, not a custom visual identity.

- Mode: Operate.
- A standard NSStatusItem and NSMenu are the primary interface.
- A small modeless guide window explains the two gestures, shows actual permission/listener state, and offers a test window.
- Use AppKit system fonts, semantic text colors, standard buttons and separators, and SF Symbols. Support system light/dark appearance without custom surfaces.
- Accessibility setup is explicit and user initiated. Permission status updates automatically after a grant.
- The test window uses real content and reports its live position and size.
- No decoration, custom motion, web views, or modal onboarding.
