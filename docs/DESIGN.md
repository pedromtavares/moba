# BrowserMOBA Design Principles

The redesign gives BrowserMOBA a cinematic dark fantasy identity while keeping repeated play quick and readable. Base is the visual reference for Training, Arena, Community, Tavern, the Game Manual, profiles, and account screens. These principles describe the shipped interface, rather than a future feature plan.

## 1. Give each screen a purpose

Lead with the player's current goal, progress, and next action. A cinematic header should explain the state of play as well as establish atmosphere.

- Base presents account progression and the hero collection.
- Training presents the road to the next league. When turns are exhausted, the league challenge becomes the main content and farming tabs disappear.
- Arena leads with 5v5 entry, daily progress, and its reward; Season Duel is a secondary action below the divider.
- Profiles lead with player identity and a featured hero, then show history, standings, and the collection.

Keep one clear primary action per state. Resume an unfinished battle or match before offering another one.

## 2. Use art as a stage

Use large hero illustrations and environmental scenes, with gradients that protect text contrast. Preserve the subject's face, silhouette, and defining details when cropping or positioning overlays.

Keep loadouts compact and place them near the edge of the artwork. On profiles, the featured loadout sits at the bottom right of the full-width banner and aligns with the collection column below. Avoid covering the illustration with large opaque panels or empty padding.

Preset build artwork describes a playstyle or fantasy, independent of a specific avatar. The same build can appear for different heroes, so its image must work across all of them.

## 3. Keep a restrained visual language

Use near-black page backgrounds, navy surfaces, warm ivory text, and muted gold borders and accents. Cinematic depth comes from artwork, gradients, subtle mist, and sparse embers. Avoid stacking decorative frames around every element.

| Treatment | Purpose |
| --- | --- |
| Warm gold | Progression, ranks, rewards, emphasis |
| Burgundy/red primary button | Major battle or training action |
| Mint/teal | Live availability, success, wins |
| Blue/cyan | XP and energy |
| Rose/red | Health, damage, defeat |

Pair color with words, icons, numbers, or state markers. Live availability and battle outcomes must remain understandable without color alone.

## 4. Make the typography readable

Use the locally bundled Nunito faces for readable headings, controls, names, and numbers. Reserve the decorative `landing-rpg` face for short ceremonial labels or calls to action. Long instructions, small labels, and dense game data need the clearer face. Keep font licensing notices with the files and avoid hosted font kits.

Build hierarchy with size, weight, spacing, and alignment. Keep explanatory copy short. Do not repeat the same status in a title, subtitle, and progress row.

## 5. Celebrate earned progress

Winning should feel rewarding. Give victory and promotion strong typography, generous space, an emblem or trophy, and a clear continuation action.

Distinguish a cleared challenge battle from a league promotion. Show the cleared and upcoming steps compactly; show the old and new league badges and earned rewards on promotion. A completed account rank celebrates the rank actually earned, rather than the next locked rank.

## 6. Summarize first, reveal detail on demand

Keep frequently scanned views concise and provide an obvious way to inspect them.

- The 5v5 match center defaults to thin battle summary rows: hero portraits and health/energy bars for both sides. Names, full battle readouts, and effects belong in Battle details or the battle replay.
- Hero pages show the loadout for inspection, but hide the editing HUD by default. Only owners see Customize hero; closing customization removes the HUD and restores the viewing space.
- Skill and item tooltips explain mechanics. Resource bars remain readable without intrusive hover overlays.

Disclosure should reduce clutter while keeping the next useful action easy to find.

## 7. Give containers a proper ending

On desktop, related columns should end on the same horizontal line above the screen edge or fixed HUD. Keep panel borders and bottom padding visible. Long content scrolls inside its panel, rather than being cut off by the viewport.

Allow each team's hero list to scroll independently in match playback. Keep the central summary legible and visible; do not shrink the whole interface to fit every hero and every battle at once. Measure the available height again when the HUD opens, closes, or changes size.

On smaller screens, stack sections and allow normal page scrolling. Preserve readable controls and content instead of forcing the desktop layout into a narrow viewport.

## 8. Remove redundant interface chrome

Use section identity and aligned rows to explain content before adding more headings or nested containers.

- Omit a lone Battle tab when there are no other tabs to choose.
- Avoid repeated section headings above the same controls.
- Omit visible column headers in compact recent-match and duel-history lists when the rows already explain their contents. Keep replay buttons accessible.
- Use a full-width segmented control for the profile's Matches / Duels switch.
- Use a three-button Plebs / Shadows / Immortals group for Arena standings, rather than a dropdown.

Center scores within the space implied by their header. Align related columns and banner content using shared widths.

## 9. Separate live play from history

Live PvP is its own Arena subsection, distinct from past duels. Its full-width availability switch has a visible ready/off state and explains whether the player is accepting challenges.

Place currently available opponents and Challenge actions within that live section. Put completed duels, results, season points, and replay actions in Duel history. Do not make past opponents look like live targets. Keep Season Duel visibly distinct from a live challenge.

## 10. Let navigation blend into the world

The desktop sidebar is a fixed icon rail with a navy-to-transparent gradient that melds into the page. Active navigation uses a strong warm glow on the icon, without a filled container or edge marker.

Reveal readable titles beneath icons on hover or keyboard focus. Reserve the title space so revealing it never pushes other items down. Do not expand the rail on hover or add a second tooltip with the same title. The rail must fit the viewport without scrolling or overflow; compact its spacing, icons, and labels on short screens. Mobile uses the responsive navigation.

## 11. Teach the action where it happens

The tutorial has two chapters: Training and Base. Keep the guide anchored to the exact target, purchase, transmutation, or control the player needs. Shopping steps prioritize a clear click target over decorative presentation.

Call the place to buy or transmute hero items **Shop** in gameplay and tutorial instructions. Keep account unlocks in the **Tavern**. Evocative terms such as “forge” can appear in marketing copy when they do not obscure an action's location.

Use short, purposeful instructions and consistent action names. The Space shortcut belongs to a ready Claim XP / Claim Gold action in farming tabs, with a visible key hint. It must not trigger while typing, using another control, or interacting with a dialog. Battle Attack has no global Space shortcut.

## 12. Make polish serve interaction

Use subtle hover transitions, clear focus rings, pressed/expanded states, loading feedback, and sufficient hit areas. Prefer semantic buttons and links with accessible names. Give progress and resource bars meaningful labels and values.

Respect reduced-motion preferences. Decorative effects must not intercept clicks, obscure content, or compete with gameplay. Check both populated and empty states, guest and owner views, and layouts with and without the HUD.

## Maintaining the design

Use the existing shared components and page styles before adding another visual pattern. Keep illustration assets local and reusable, and preserve their provenance where supplied. Match the product's names and mechanics to [PRODUCT.md](PRODUCT.md).

Interface symbols use local generated raster pictograms from `assets/static/images/ui`, with PNG alpha masks that inherit the surrounding text color. Preserve familiar silhouettes, semantic stat colors, and loading states. Use the existing `ui-icon` classes or the shared game icon component; do not add hosted icon kits or icon fonts. Sidebar emblems remain the separate full-color raster set in `images/navigation`.

Review a change in the browser at desktop and narrow widths. Verify the action it introduces, its keyboard behavior, and its effect on panel height and scrolling. Keep tests focused on meaningful interaction outcomes.
