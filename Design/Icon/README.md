# Layout Toolkit icon redesign

Artwork was edited with the built-in imagegen tool, using the existing ICO frames
as edit targets. `source-*.png` retain the generated high-resolution artwork;
`icon-*.png` are the final, individually resized frames. `icon-original.ico`
preserves the previous icon for comparison or restoration.

The Windows runtime asset is `Assets/icon.ico`. It contains four independent
32-bit RGBA images, not four automatic downscales of the largest design.

## Prompt set

Shared constraints: preserve the original turquoise L, white T, dark blue-charcoal
palette and recognizable LT arrangement. Transparent pixels outside the rounded
tile. No additional lettering, slogans, glow or external shadow.

- **256:** replace the small letters and indistinct blocks with four equal blank
  grey keyboard keys in a 2-by-2 grid. Preserve the silver underline. Add a subtle
  low-relief edge to the rounded background.
- **64:** use the same four-key motif and underline, but keep the rounded
  background simple, without relief or a metallic rim.
- **32:** keep the rounded tile and LT. Remove the underline. Render four flat
  grey keys with clearly separated gaps and no tiny lettering or bevels.
- **16:** retain only large, simple LT and a rounded dark tile. No keys, small
  letters, underline, relief or extra detail.

Packaging removes empty transparent generator padding, preserves aspect ratio,
resizes each independent variant with Lanczos, and encodes them into one ICO.
The ICO roundtrip was checked against all four PNG frames. Windows loaded each
requested size successfully. `icon-preview.png` shows actual sizes and enlarged
nearest-neighbour views for inspection.

## Pixel-aligned 16 px revision

The final 16 px frame now comes directly from `icon-original.ico`, not from a
generated/downscaled variant. `Build-SmallIcon.ps1` preserves its original thick
LT and exact palette, modifying only background pixels at the four corners.
A compact 3 px corner mask adds subtle contour antialiasing without touching
the lettering. Assertions verify that every original non-background pixel
remains identical. There is no resizing, shadow or font substitution.
The generated `source-16.png` is retained only as an earlier design reference.
Running the script replaces only the 16 px ICO payload; larger frames remain
unchanged. `icon-16-preview.png` shows an exact integer zoom on light/dark grounds.
The earlier combined `icon-preview.png` predates this correction.

Do not include this design directory in the Windows user release ZIP.
