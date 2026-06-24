# Bag level swap fix

- Clothing use/swap now decodes string metadata safely.
- Bag items are normalised to always include `bagLevel`, `bag_level`, and `level`.
- Returned old bag metadata keeps a bag level instead of returning a level-less bag.
