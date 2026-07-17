# cm-house v1.7.14 — Recall convergence fallback

- Falls back to confirmed deletion plus one fresh garage entity when cross-bucket migration cannot converge.
- Keeps database vehicle ID authoritative and prevents unusable duplicate entities.
- Updates the recall confirmation text to describe the safe fallback behavior.
