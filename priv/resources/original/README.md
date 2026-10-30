# Original seed artwork

This pack supplies the repository's fresh-install artwork: 25 hero backgrounds
(including the boss), 25 square portraits, 52 skill icons, 30 item icons, and
48 separate Master/Grandmaster backgrounds for the 24 playable heroes.

All illustrations were generated with the built-in OpenAI image generation tool.
No downloaded game artwork, development uploads, or existing character images
were used as image inputs. The characters, silhouettes, equipment, palettes and
compositions are original designs. Internal resource codes and gameplay names
remain compatible with the existing engine.

The common lighting direction is a warm key from the upper left, a cooler rim
from the lower right, dark edges, and a bright readable focal point. Master
outfits have refined materials and detail; Grandmaster outfits have more
elaborate original regalia and controlled magical effects.

`manifest.json` records the generation prompt for each illustration. Portraits
are cropped from the matching default background. Final files are compressed
WebP: 256 × 256 for icons/portraits and 960 × 640 for backgrounds. Generated
source images stay outside the repository.

`../../repo/seed_catalog.json` contains the canonical gameplay snapshot from the
development database on 2026-10-27, including every rank's actual values. Disabled
historical content is omitted; the boss and its four effects remain included.
Skins use league tiers 5 and 6 and credit `AI` at `https://chat.com`.

Run `mix ecto.setup` for a new database, or `mix run --no-start priv/repo/seeds.exs` after
creating and migrating an empty database. Seeding also publishes resources and
generates bots, as before. It is not an update script for an existing database.
Do not reset a database with player data to preview this pack. Production updates
continue to use the separate expansion importer and admin artwork uploads.

The seed script resolves source images relative to its own location and copies
them through the normal uploaders. It does not need the ignored `uploads/`
directory to be present in a checkout. As before, GitHub Actions skips attachment
uploads while still creating all resource and skin records.
