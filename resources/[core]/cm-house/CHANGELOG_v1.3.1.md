> Historical note: v1.3.2 supersedes the v1.3.1 zero-health fallback. Numeric zero is now preserved as genuine destroyed condition.

# cm-house v1.3.1

- Strict garage health normalization: invalid/zero health becomes 1000.0.
- Guarded affected-row SQL for store, release, assignment, replacement, removal and rollback paths.
- Synchronous central entity deletion before new entity creation.
- Exterior return-zone parking now moves the player into the garage bucket and completes entry from a trusted server snapshot.
- Standalone `/cmadminhouse` interior/garage creation with world or IPL source.
- Universal standalone interiors now appear during property creation.
- Disabled templates can be enabled, re-walked, previewed, renamed or deleted.
- Template parent/slot writes are transactional.
- Re-walking preserves stash labels and capacities.
