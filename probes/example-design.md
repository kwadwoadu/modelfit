---
id: example-design
category: design
scoring: screenshot
---

# PROMPT
Build a self-contained HTML pricing section with exactly three tiers shown side by side:
"Starter", "Pro", and "Enterprise".

Requirements:
- Three pricing cards laid out horizontally in one row on a desktop-width viewport.
- The MIDDLE card ("Pro") must be visually emphasized as the "most popular" tier:
  clearly distinguished from the other two (e.g. a badge, a lifted/scaled card, a
  colored border or fill) so it reads as the recommended choice at a glance.
- Each card has a tier name, a price, a short list of 3–4 features, and a call-to-action
  button. The Pro card's primary CTA must be the visually dominant button on the page.
- No external network requests: inline CSS only, no CDN links, web fonts, or remote images.
- Responsive: the layout must not overflow horizontally and should remain usable down to
  a 375px-wide viewport (cards may stack).

Output ONLY the HTML document. No prose, no explanation, no markdown fences.

# RUBRIC
Discriminator: the middle-tier emphasis and CTA hierarchy. A weak answer renders three
identical cards with no visual "most popular" signal, or an overflowing/broken grid, so
the rendered screenshot fails to guide the eye to the recommended tier.

PASS requires ALL of:
- M1 Three distinct pricing cards are visible side by side in a single row (not stacked,
  not overlapping) at desktop width.
- M2 The middle ("Pro") card is visually distinguished from the other two (badge, scale,
  color, or border) so it reads as the emphasized / "most popular" tier.
- M3 A primary call-to-action button is clearly the dominant button in the layout
  (the Pro CTA stands out over the other CTAs).
- M4 No broken or overflowing layout: cards fit the viewport, nothing is clipped, and text
  does not spill outside its card.
- M5 Text is legible with adequate contrast against its background (prices, names, and
  button labels are readable).

FAIL if: only one or two cards render; the three cards are visually identical with no
emphasized middle tier; the layout overflows horizontally or cards overlap; the page
renders blank or broken; or the output is not a self-contained HTML document (external
network requests, or wrapped in prose/markdown against "output ONLY the HTML").

Quality pluses (do not gate): consistent spacing and alignment across cards; a clear
"most popular" badge; balanced typographic hierarchy between price and features;
graceful stacking at 375px.
