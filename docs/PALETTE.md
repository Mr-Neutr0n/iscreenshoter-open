# Palette appearance correction in 1.0.2

The color/width strip previously used a native vibrant-dark NSPopover around a
custom view. This added a material frame, border, and arrow that were not part of
the recovered configuration view. The palette now renders directly in the editor
as a plain rounded view and follows toolbar movement.

Retained REA interface evidence `ev_771604a3b97db83dd0d4c1ecc0968d42776483bc0aa72c575b31988ea648d3d0`
identifies the configuration NSBox as 460 by 48 points, radius 10, with device RGB
65/255. The toolbar is a separate archived fill: sRGB 54/255, radius 8. These are
intentionally different colors. Making both fills identical would lose that
source distinction.

The retained native load and tool-selection analyses (`0x100038fa0` and
`0x10003be28`) attach the configuration controller as a child and toggle its view
visibility. They do not establish the native popover shell used by the previous
rebuild. Palette placement/clamping in the reconstruction remains an implementation
choice rather than a verified original pixel match.

Verification instantiates the production tool-options path, checks that the strip
belongs to the editor instead of a popover, and renders the actual palette view
for inspection. No CUA or live desktop capture is used.

![Plain editor palette](media/editor-palette.png)
