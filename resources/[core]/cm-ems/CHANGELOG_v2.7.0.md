# v2.7.0

- Government EMS now targets arrival two minutes after the original ambulance call.
- An active AI response is registered independently of its first dispatch, so it remains available after that patient is patched.
- Any new valid call within 40 metres and the same routing bucket is immediately claimed by the nearby AI response.
- AI-claimed calls are locked to the government doctor and cannot be accepted by player EMS.
- The doctor waits at the scene for 30 seconds after its queue becomes empty; new nearby calls reopen the queue immediately.
- The doctor patches every queued, still-downed caller before closing the response and returning to the ambulance.
- The requested two-minute timing is no longer shortened by the patient's remaining bleed-out timer.
