// Fixture: NUI browser-side script for cm-fivem-map tests.
// Covers: fetch -> RegisterNUICallback resolution via a templated
// GetParentResourceName() URL, and a fetch with no matching Lua handler.

function askFixture() {
    return fetch(`https://${GetParentResourceName()}/fixtureNuiAction`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify({ ok: true }),
    }).then((resp) => resp.json());
}

function askOrphan() {
    // no matching RegisterNUICallback exists for this request
    return fetch(`https://${GetParentResourceName()}/fixtureOrphanRequest`, {
        method: 'POST',
    }).then((resp) => resp.json());
}
