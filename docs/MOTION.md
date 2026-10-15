# Copy-to-corner motion

Version 1.0.1 restores the screenshot preview's entrance transition. Copying a
capture creates the preview at the captured selection's global screen frame,
then shrinks and moves it to the lower-right corner of that display. The settled
frame is 150 by 100 points, with a 50-point right and bottom margin.

## Evidence

REA re-analyzed the original iScreen Shoter 3.0.2 build 28 arm64 copy handler at
`0x100043008`. Evidence ID:
`ev_5e5aa7f387b26ea5f8fd65a7200a2b8c86277dbfbd8f7eaf5a2cf4296e0150c9`.
Target SHA-256:
`00f6c39d8a843a62e3e2be201d74ceb9dd68c794e4be7f8b9cfd49042ecf2275`.

The handler sets the source frame from the cut rectangle plus the capture
window's origin, shows the preview, then sends `setFrame:display:animate:` with
both flags enabled. This is a native AppKit window animation. The inspected path
sets no explicit duration or easing curve. The reconstruction uses that same
API rather than a guessed spring or fixed animation duration.

The editor passes the selection frame before closing. AppKit converts view
coordinates to global screen points, preserving Retina scaling and negative
secondary-display origins. Calls without a valid source rectangle retain the
previous behavior of showing the settled preview directly.

## Boundaries

Reduce Motion disables the flight in this implementation. That accessibility
choice is an intentional addition, not recovered original behavior. Preview
hover cancellation, retention after dragging, and the five-second dismissal
interval are preserved. The public build still uses an independent fade for
closing; it does not redistribute the original destruction-animation artwork.
The original first-use paste-guidance presentation is not added in this release.

Verification exercises the real editor completion notification, its source
selection/display payload, invalid-frame handling, and the existing preview
lifetime checks. No desktop automation or CUA was used. This verifies the handoff
and native API wiring, not a recorded pixel-by-pixel comparison of live motion.
