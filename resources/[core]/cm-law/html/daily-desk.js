(() => {
  'use strict';
  const police = location.pathname.includes('/police/');
  const appNode = document.getElementById('app');
  const content = appNode.querySelector('.content');
  const nav = appNode.querySelector('nav');
  const tab = document.createElement('button');
  tab.className = police ? 'nav' : 'tab';
  tab.dataset[police ? 'page' : 'tab'] = 'daily';
  tab.innerHTML = '<b>✓</b><span>Daily desk<small>Checklist &amp; shift notes</small></span>';
  nav.appendChild(tab);
  const view = document.createElement('section');
  view.id = 'dailyView'; view.className = police ? 'page daily-desk' : 'view daily-desk hidden';
  view.dataset.view = 'daily';
  view.innerHTML = `<div class="desk-hero"><div><small>YOUR WORKDAY</small><h2>Ready for the next call.</h2><p>A personal checklist and notes for a more organised shift.</p></div><span id="deskDate">TODAY</span></div>
    <div class="desk-shortcuts" id="deskShortcuts"></div><article class="desk-card desk-objectives"><div class="desk-heading"><div><small>SERVER VERIFIED</small><h3>Daily objectives</h3></div><span>LIVE ACTIVITY</span></div><p class="desk-help">Progress is recorded automatically from duty time, bookings and dispatch work.</p><div id="deskObjectives" class="desk-objective-list"><p class="desk-help">Open the desk to load objectives.</p></div></article>
    <div class="desk-grid"><article class="desk-card"><div class="desk-heading"><div><small>SHIFT PREPARATION</small><h3>Daily checklist</h3></div><strong id="deskProgress">0 / 7</strong></div><div class="desk-meter"><i id="deskMeter"></i></div><p class="desk-help">Mark these yourself as you work. Resets at midnight UTC.</p><div id="deskTasks"></div></article>
    <article class="desk-card"><div class="desk-heading"><div><small>PERSONAL NOTES</small><h3>Keep track of your shift</h3></div><span id="deskCount">0 / 2000</span></div><label for="deskNotes" class="desk-help">Follow-ups, report references and reminders. Only your character can access these notes.</label><textarea id="deskNotes" maxlength="2000" placeholder="Follow up on…&#10;Report reference…&#10;Remember before ending duty…"></textarea><div class="desk-save"><span id="deskStatus" role="status">Open the desk to load your notes.</span><button id="deskSave" type="button">Save desk</button></div><button id="deskReload" class="desk-secondary" type="button">Reload saved desk</button></article></div>
    <article class="desk-card"><div class="desk-heading"><div><small>LAST SEVEN DAYS</small><h3>Previous shift notes</h3></div></div><div id="deskHistory"><p class="desk-help">Your saved days will appear here.</p></div></article>`;
  content.appendChild(view);
  const $ = id => document.getElementById(id);
  const labels = [['equipment','Check duty equipment','Uniform, protection and approved equipment.'],['radio','Check communications','Radio, callsign and unit status.'],['vehicle','Inspect your vehicle','Fuel, condition and the correct parking space.'],['assignment','Review your assignment','Check dispatch or your organisation’s current work.'],['records','Update your records','Finish relevant reports and follow-up notes.'],['custody','Check custody readiness','Confirm the shared intake, cells and release point are ready.'],['handover','Prepare your handover','Return equipment and leave useful reminders.']];
  $('deskTasks').innerHTML = labels.map(([id,title,description]) => `<label class="desk-task"><input type="checkbox" data-desk-task="${id}"><span><strong>${title}</strong><small>${description}</small></span></label>`).join('');
  let owner = '', loadedOwner = '', snapshot = null, dirty = false, loading = false, saving = false, generation = 0;
  const checked = () => Object.fromEntries([...view.querySelectorAll('[data-desk-task]')].map(n => [n.dataset.deskTask, n.checked]));
  function progress() { const n = Object.values(checked()).filter(Boolean).length; $('deskProgress').textContent = `${n} / ${labels.length}`; $('deskMeter').style.width = `${n / labels.length * 100}%`; $('deskCount').textContent = `${$('deskNotes').value.length} / 2000`; }
  function status(message, error = false) { $('deskStatus').textContent = message; $('deskStatus').classList.toggle('desk-error', error); }
  function lock() { $('deskSave').disabled = !snapshot || saving || loading; $('deskNotes').disabled = !snapshot || saving || loading; view.querySelectorAll('[data-desk-task]').forEach(n => n.disabled = !snapshot || saving || loading); }
  function history(items) {
    const box = $('deskHistory'); box.replaceChildren();
    if (!items.length) { box.textContent = 'No previous days saved yet.'; return; }
    for (const item of items) { const details = document.createElement('details'), summary = document.createElement('summary'), note = document.createElement('p'); summary.textContent = `${item.date} · ${Object.values(item.checked).filter(Boolean).length} / ${labels.length} completed`; note.textContent = item.notes || 'No notes saved.'; details.append(summary,note); box.append(details); }
  }
  function objectives(items) { const box=$('deskObjectives'); box.replaceChildren(); if(!items?.length){box.textContent='No objectives are available.';return;} for(const item of items){const row=document.createElement('div');row.className='desk-objective';const pct=Math.min(100,Math.round(Number(item.today||0)/Math.max(1,Number(item.target||1))*100));row.innerHTML=`<div><strong>${item.label}</strong><small>${item.today} / ${item.target} ${item.unit}${item.today===1&&item.unit==='booking'?'':'s'} today · ${item.weekly||0} this week</small></div><i><b style="width:${pct}%"></b></i>`;box.appendChild(row);} }
  async function load() {
    if (!owner || loading || saving) return;
    if (dirty && !(await showConfirmOverlay('Reload daily desk','Discard your unsaved changes and reload the saved desk?','Reload','Keep editing'))) return;
    loading = true; lock(); status('Loading your desk…'); const token = generation, requestedOwner = owner;
    const result = await post('dailyDesk',{action:'get',organization:requestedOwner.split('|')[0]});
    if (token !== generation) return;
    loading = false;
    if (!result?.ok) { lock(); status(result?.error || 'Could not load your desk.',true); return; }
    snapshot = result; loadedOwner = requestedOwner; dirty = false;
    $('deskDate').textContent = `${result.date} · UTC`; $('deskNotes').value = result.day.notes;
    view.querySelectorAll('[data-desk-task]').forEach(n => n.checked = result.day.checked[n.dataset.deskTask] === true);
    history(result.history || []); objectives(result.objectives || []); progress(); lock(); status('Saved desk loaded.');
  }
  $('deskSave').onclick = async () => {
    if (!snapshot || saving || loadedOwner !== owner) return;
    saving = true; lock(); status('Saving…'); const token = generation;
    const result = await post('dailyDesk',{action:'save',organization:owner.split('|')[0],date:snapshot.date,revision:snapshot.revision,notes:$('deskNotes').value,checked:checked()});
    if (token !== generation) return;
    saving = false; lock();
    if (!result?.ok) return status(result?.error || 'Could not save. Your edits are still here.',true);
    snapshot = result; dirty = false; history(result.history || []); objectives(result.objectives || []); status('Saved for your next visit.');
  };
  $('deskReload').onclick = load;
  view.addEventListener('input', () => { dirty = true; progress(); status('Unsaved changes — save before leaving.'); });
  function shortcuts() {
    const box = $('deskShortcuts'); box.replaceChildren();
    const targets = police ? [['members','Find a colleague'],['fleet','Fleet overview'],['logs','Activity records'],['outfits','Duty outfits']] : [['dispatch','Live dispatch'],['mdt','Search records'],['fleet','Fleet overview'],['logistics','Supply orders']];
    for (const [target,label] of targets) { const original = nav.querySelector(`[data-${police?'page':'tab'}="${target}"]`); if (!original || original.hidden || original.classList.contains('hidden') || getComputedStyle(original).display === 'none') continue; const button = document.createElement('button'); button.textContent = label + ' →'; button.onclick = () => original.click(); box.appendChild(button); }
  }
  tab.onclick = () => {
    if (police) showPage('daily');
    else { nav.querySelectorAll('.tab').forEach(n=>n.classList.toggle('active',n===tab)); content.querySelectorAll('.view').forEach(n=>n.classList.toggle('hidden',n!==view)); }
    $('pageTitle').textContent = 'Daily desk'; shortcuts(); if ((!snapshot || (!dirty && snapshot.date !== new Date().toISOString().slice(0,10))) && !loading) load();
  };
  const overview = document.getElementById('overviewView') || content.querySelector('[data-view="overview"]');
  const banner = document.createElement('button'); banner.className = 'desk-entry'; banner.innerHTML = '<span><small>MAKE THE MOST OF YOUR SHIFT</small><strong>Open your daily desk</strong></span><span>Checklist · Notes · Recent days →</span>'; banner.onclick = () => tab.click(); overview.prepend(banner);
  window.addEventListener('message', event => {
    const payload = event.data || {}; if (!['open','dashboard','refresh'].includes(payload.action) || !payload.data) return;
    const data = payload.data, member = police ? data.self : data.member;
    const next = member?.characterId ? `${police?'police':data.organization?.id}|${member.characterId}` : (!police && data.characterId && data.organization?.id ? `${data.organization.id}|${data.characterId}` : '');
    if (next !== owner) { generation++; owner = next; loadedOwner = ''; snapshot = null; dirty = false; loading = false; saving = false; $('deskNotes').value = ''; view.querySelectorAll('[data-desk-task]').forEach(n=>n.checked=false); history([]); progress(); lock(); status('Open the desk to load your notes.'); }
    tab.hidden = !owner || data.adminMode === true; banner.hidden = tab.hidden;
  });
  lock();
})();
