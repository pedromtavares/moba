# Interface pictograms

Original raster pictograms generated for BrowserMOBA with the built-in OpenAI
image generation tool. These are not extracted Font Awesome glyphs or font files.

Each asset is a 128 × 128 transparent PNG with a white silhouette, normalized
from the generated alpha mask and downsampled with antialiased edges. The interface uses its alpha channel as a CSS
mask so existing text colors, hover states, and semantic stat colors still work.
The shared mask renders at 120% to fill that safe padding without enlarging the
layout box or moving adjacent labels.
No icon font, hosted kit, account, or third-party request is required.

`manifest.json` records each symbol's generation brief. Source images stay outside
the repository; the exported icons are the files consumed by the application.
