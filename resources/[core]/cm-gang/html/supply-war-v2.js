(() => {
    const E = id => document.getElementById(id);
    const safe = value => String(value ?? '').replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
    const gangs = ['marabunta', 'bloods', 'ballas', 'families', 'vagos'];
    const colors = { marabunta: '#4fa3ff', bloods: '#ff3b4e', ballas: '#a855f7', families: '#3dd68c', vagos: '#ffc93b' };
    const color = (gang, supplied) => /^#[0-9a-f]{6}$/i.test(String(supplied || '')) ? supplied : (colors[gang] || '#dffbff');

    function renderLiveCounts(data) {
        const box = E('ge-live-counts');
        if (!box) return;
        const counts = data.liveInside || {};
        box.innerHTML = gangs.map(gang => { const live=Math.max(0,Number(counts[gang]||0)),gangColor=color(gang,data.gangColors?.[gang]);return `<li class="${live>0?'active':''}" style="--gang-color:${gangColor}"><i></i><span>${safe(gang.toUpperCase())}</span><b>${live}</b></li>` }).join('');
    }

    function renderDeath(data) {
        const feed = E('ge-kill-feed');
        if (!feed || !data.victim) return;
        const row = document.createElement('div');
        row.className = 'ge-death-row';
        if (data.killer) {
            row.innerHTML = `<span style="color:${color(data.killerGang, data.killerColor)}">${safe(data.killer)}</span><em>→</em><span style="color:${color(data.victimGang, data.victimColor)}">${safe(data.victim)}</span>`;
        } else {
            row.innerHTML = `<span style="color:${color(data.victimGang, data.victimColor)}">${safe(data.victim)}</span><em>DIED</em>`;
        }
        feed.prepend(row);
        while (feed.children.length > 4) feed.lastChild.remove();
    }

    window.addEventListener('message', event => {
        const message = event.data || {};
        const data = message.data || {};
        if (message.action === 'gangEventJoined') {
            renderLiveCounts({});
        } else if (message.action === 'gangEventScores') {
            renderLiveCounts(data);
        } else if (message.action === 'gangEventDeathFeed') {
            renderDeath(data);
        } else if (message.action === 'gangEventEnded') {
            if (E('ge-results')) E('ge-results').hidden = true;
        } else if (message.action === 'gangEventClear') {
            if (E('ge-results')) E('ge-results').hidden = true;
            if (E('ge-kill-feed')) E('ge-kill-feed').innerHTML = '';
        }
    });
})();
