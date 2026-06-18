# Full Transparent Character Selector Fix

This version removes the full-screen selector background from NUI. Only the cards, title, details panel, and music button render. The middle of the screen is transparent so the GTA world camera and selected character ped can be seen.

Changed files:
- ui/index.html
- ui/style.css

If the character still does not show, the issue is no longer the NUI background; check F8 for the `AfterLife preview walk-in` log and inspect the scene/camera coordinates.
