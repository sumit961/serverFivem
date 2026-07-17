# cm-house v1.3.2.5

## Garage visibility and true recall hotfix

- Fixed parked cars remaining invisible on clients that streamed them before `cmConditionReady` became true.
- Garage condition finalization is now retried instead of being marked complete after a single unacknowledged event.
- New garage entities apply their real saved condition on the creating/owning client before the server acceptance round-trip.
- A failed condition verification now leaves the car visible but protected/undriveable instead of permanently invisible.
- Repeat Call requests carry the database vehicle ID and recall the same outside entity if the slot was already cleared.
- Added server-side loose vehicle recall without changing garage/database storage state.
- Added NUI action locking to prevent duplicate garage actions.
- Updated the slot action wording to "Call / recall car".
- Recall requests are server-validated against the player's current garage instance.
- Missing outside entities are not recreated in the private garage bucket.
