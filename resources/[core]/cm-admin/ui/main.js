const app = document.getElementById('app');
const nav = document.getElementById('nav');
const page = document.getElementById('page');
const pageTitle = document.getElementById('pageTitle');
const pageKicker = document.getElementById('pageKicker');
const serverName = document.getElementById('serverName');
const adminName = document.getElementById('adminName');
const adminRank = document.getElementById('adminRank');

const state = {
  open: false,
  tab: 'dashboard',
  selectedPlayer: null,
  data: { me: {}, players: [], admins: [], ranks: [], logs: [], logCategories: [], permissions: [], server: {}, orgs: { list: [], policy: {} }, gangs: { gangs: [] } },
  offline: { query: '', results: [] },
  map: { players: [], vehicles: [], showVehicles: true, showAdmins: true, cam: { x: 0, y: -800, zoom: 0.34 }, timer: null, drag: null, moved: false, cursor: null, resizeBound: false, selected: null, calibrating: false, calibration: null },
  rankEditor: { name: '', label: '', level: 20, permissions: [] },
  logFilter: 'all',
  detail: null,
};

function resourceName() {
  try { return GetParentResourceName(); } catch (e) { return 'cm-admin'; }
}

function post(name, payload) {
  return fetch(`https://${resourceName()}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(payload || {})
  }).catch(() => null);
}

function action(actionName, data) {
  return post('adminAction', { action: actionName, data: data || {} });
}
function sendAction(actionName, data) { return action(actionName, data); }

function closeUi() { post('close', {}); }

document.getElementById('closeBtn').addEventListener('click', closeUi);
document.getElementById('refreshBtn').addEventListener('click', () => action('refresh'));
document.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeUi(); });

function esc(value) {
  if (value === null || value === undefined) return '';
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

function hasPerm(permission) {
  const perms = (state.data.me && state.data.me.permissions) || [];
  return perms.includes('*') || perms.includes(permission);
}

function gangAdminAction(operation, gangId, extra) {
  action('gangAdminAction', Object.assign({ operation, gangId }, extra || {}));
}
window.cmGangIdentity = function(id) {
  gangAdminAction('identity', id, { displayName: document.getElementById(`gangName_${id}`).value,
    shortTag: document.getElementById(`gangTag_${id}`).value, color: document.getElementById(`gangColor_${id}`).value,
    logoAsset: document.getElementById(`gangLogo_${id}`).value, artAsset: document.getElementById(`gangArt_${id}`).value,
    enabled: document.getElementById(`gangEnabled_${id}`).checked });
};
window.cmGangLeader = function(id, remove) {
  if (remove) {
    if (!confirm('Remove the current gang leader and their gang membership? The gang will remain enabled without a leader.')) return;
    return gangAdminAction('removeLeader', id, {});
  }
  return gangAdminAction('assignLeader', id, { characterId: document.getElementById(`gangLeader_${id}`).value });
};
window.cmGangFacility = function(id, type, reset) {
  const suffix=type==='headquarters'?'':`_${type}`;
  gangAdminAction('facility', id, { facilityType:type, reset:reset===true, enabled:!reset,
    npcModel:document.getElementById(`gangNpcModel_${id}${suffix}`)?.value||'',
    displayName:document.getElementById(`gangNpcName_${id}${suffix}`)?.value||'',
    roleLabel:document.getElementById(`gangNpcRole_${id}${suffix}`)?.value||'' });
};
window.cmGangRank = function(id, rankId) {
  const prefix=`gangRank_${id}_${rankId}`; const permissions=Array.from(document.querySelectorAll(`[data-gang-rank="${id}:${rankId}"]:checked`)).map(x=>x.value);
  gangAdminAction('rank',id,{rankId,name:document.getElementById(`${prefix}_name`).value,tier:Number(document.getElementById(`${prefix}_tier`).value),permissions});
};
window.cmGangRecover = (id, operation) => gangAdminAction('recover',id,{operation});
window.cmGangLegacyMigrate = id => gangAdminAction('legacyMigrate',id,{legacyGangId:document.getElementById(`gangLegacy_${id}`).value});
window.cmGangArmory = function(id) { gangAdminAction('armory',id,{itemId:document.getElementById(`gangArmItem_${id}`).value,
  enabled:document.getElementById(`gangArmEnabled_${id}`).checked,minimumTier:Number(document.getElementById(`gangArmTier_${id}`).value),
  issueQuantity:Number(document.getElementById(`gangArmQty_${id}`).value),issueLimit:Number(document.getElementById(`gangArmLimit_${id}`).value)}); };
window.cmGangArmoryStock = id => gangAdminAction('armoryStock',id,{itemId:document.getElementById(`gangArmItem_${id}`).value,delta:Number(document.getElementById(`gangArmStock_${id}`).value)});
window.cmGangArmoryToggle=(gangId,itemId,enabled)=>{const tier=Number(document.getElementById(`gangArmTier_${gangId}_${itemId}`)?.value||1);gangAdminAction('armory',gangId,{itemId,enabled,minimumTier:tier,issueQuantity:1,issueLimit:0})};
window.cmGangArmoryBundleStock=(gangId,itemId)=>gangAdminAction('armoryBundleStock',gangId,{itemId});
function renderGangWeaponCatalog(){const payload=state.data.gangs||{},gangs=payload.gangs||[],catalog=payload.weaponCatalog||[],cards=page.querySelectorAll(':scope > .card'),can=hasPerm('gang.admin.manage');gangs.forEach((g,index)=>{const card=cards[index+1];if(!card)return;const heading=Array.from(card.querySelectorAll('h4')).find(x=>x.textContent.trim()==='Armory');if(!heading)return;const oldForm=heading.nextElementSibling,oldTable=oldForm?.nextElementSibling;heading.textContent='Gang Armory Weapon Catalog';const wrap=document.createElement('div');wrap.innerHTML=`<p class="mini-label">Enable weapons from cm-weapons for this gang. Linked ammunition is enabled automatically. Add Stock supplies exactly 5 weapons and 1,000 linked rounds.</p><div class="table-wrap"><table><thead><tr><th>Weapon</th><th>Ammo</th><th>Minimum tier</th><th>Stock</th><th>Controls</th></tr></thead><tbody>${catalog.map(w=>{const configured=(g.armory||[]).find(i=>i.item_id===w.itemName)||{},ammo=(g.armory||[]).find(i=>i.item_id===w.ammoItem)||{};return `<tr><td><strong>${esc(w.label)}</strong><br><small>${esc(w.itemName)}</small></td><td>${esc(w.ammoItem||'No linked ammo')}<br><small>${Number(ammo.stock_quantity||0).toLocaleString()} rounds</small></td><td><input id="gangArmTier_${g.gang_id}_${w.itemName}" class="input" type="number" min="1" max="100" value="${Number(configured.minimum_tier||1)}"></td><td>${Number(configured.stock_quantity||0).toLocaleString()} guns</td><td><button class="btn small ${configured.enabled?'danger':'primary'}" ${can?'':'disabled'} onclick="cmGangArmoryToggle('${g.gang_id}','${esc(w.itemName)}',${configured.enabled?'false':'true'})">${configured.enabled?'Disable':'Enable'}</button><button class="btn small" ${can&&configured.enabled?'':'disabled'} onclick="cmGangArmoryBundleStock('${g.gang_id}','${esc(w.itemName)}')">+5 guns / +1000 ammo</button></td></tr>`}).join('')||'<tr><td colspan="5">cm-weapons catalog unavailable.</td></tr>'}</tbody></table></div>`;heading.after(wrap);oldForm?.remove();oldTable?.remove()})}
const renderGangAdminCatalogBase=renderGangWeaponCatalog;
renderGangWeaponCatalog=function(){renderGangAdminCatalogBase();page.querySelectorAll('[onclick^="cmGangFleetSave"]').forEach(save=>{const match=save.getAttribute('onclick').match(/cmGangFleetSave\('([^']+)','([^']+)'\)/);if(!match||save.parentElement.querySelector('[onclick^="cmGangFleetBegin"]'))return;const button=document.createElement('button');button.className='btn small';button.dataset.setGangSpawn=match[2];button.textContent='Set Spawn Location';button.disabled=!hasPerm('gang.admin.manage');button.onclick=()=>cmGangFleetBegin(match[1],match[2]);save.parentElement.appendChild(button)})};
window.cmGangFleetBegin = (id,model) => gangAdminAction('fleetBegin',id,{model:model||document.getElementById(`gangFleetModel_${id}`).value});
window.cmGangFleetSave = function(id, model) { const key=`gangFleet_${id}_${model}`; gangAdminAction('fleet',id,{model,enabled:document.getElementById(`${key}_enabled`).checked}); };
window.cmGangFleetReset = (id, model) => gangAdminAction('fleetReset',id,{model});
window.cmGangFleetDelete = (id, model, vehicleId) => { if(confirm(`Delete vehicle_id ${vehicleId} (${model}) permanently?`)) gangAdminAction('fleetDelete',id,{model}); };

function gangsPage() {
  const payload=state.data.gangs||{}, gangs=payload.gangs||[], can=hasPerm('gang.admin.manage');
  if(payload.ok!==true) return `<div class="empty">${esc(payload.error||'Gang management is unavailable.')}</div>`;
  return `<div class="card"><h3>Five Fixed Gangs</h3><p class="mini-label">Marabunta, Bloods, Ballas, Families and Vagos are the complete gang set. There is no create or delete action.</p></div>`+
  gangs.map(g=>{ const facilities=g.facilities||[], perms=(payload.permissions||[]).map(p=>p.key); const hq=facilities.find(f=>f.facility_type==='headquarters')||{}, fleetNpc=facilities.find(f=>f.facility_type==='fleet')||{}, profitNpc=facilities.find(f=>f.facility_type==='profit')||{}; const recovery=g.recovery||{};
    return `<div class="card"><h3>${esc(g.display_name)} <small>${esc(g.gang_id)}</small></h3>
      <div class="form"><input id="gangName_${g.gang_id}" class="input" value="${esc(g.display_name)}" placeholder="Display name"><input id="gangTag_${g.gang_id}" class="input" value="${esc(g.short_tag)}" placeholder="Tag"><input id="gangColor_${g.gang_id}" class="input" value="${esc(g.color)}" placeholder="#67e8f9"><input id="gangLogo_${g.gang_id}" class="input" value="${esc(g.logo_asset||'')}" placeholder="Allowlisted logo key"><input id="gangArt_${g.gang_id}" class="input" value="${esc(g.art_asset||'')}" placeholder="Allowlisted art key"><label><input id="gangEnabled_${g.gang_id}" type="checkbox" ${g.enabled?'checked':''}> Enabled</label><button class="btn primary" ${can?'':'disabled'} onclick="cmGangIdentity('${g.gang_id}')">Save identity</button></div>
      <h4>Leader & members</h4><p>${g.leader_character_id?`Leader CID ${esc(g.leader_character_id)}`:'Leader not assigned'} · ${Number(g.memberCount||0)} members</p><div class="form"><input id="gangLeader_${g.gang_id}" class="input" placeholder="Authoritative character ID"><button class="btn primary" ${can?'':'disabled'} onclick="cmGangLeader('${g.gang_id}',false)">Assign / replace</button><button class="btn danger" ${can?'':'disabled'} onclick="cmGangLeader('${g.gang_id}',true)">Remove leader</button></div>
      <h4>Main Gang NPC</h4><p class="mini-label">Warehouse, common fund deposits and armory services.</p><div class="form"><input id="gangNpcModel_${g.gang_id}" class="input" value="${esc(hq.npc_model||'')}" placeholder="Optional allowlisted model"><input id="gangNpcName_${g.gang_id}" class="input" value="${esc(hq.display_name||'')}" placeholder="NPC name"><input id="gangNpcRole_${g.gang_id}" class="input" value="${esc(hq.role_label||'')}" placeholder="Gang Contact"><button class="btn primary" ${can?'':'disabled'} onclick="cmGangFacility('${g.gang_id}','headquarters',false)">Set Main NPC Here</button><button class="btn danger" ${can?'':'disabled'} onclick="cmGangFacility('${g.gang_id}','headquarters',true)">Disable</button></div>
      <h4>Vehicle NPC</h4><div class="form"><input id="gangNpcModel_${g.gang_id}_fleet" class="input" value="${esc(fleetNpc.npc_model||'')}" placeholder="Optional allowlisted model"><input id="gangNpcName_${g.gang_id}_fleet" class="input" value="${esc(fleetNpc.display_name||'')}" placeholder="NPC name"><input id="gangNpcRole_${g.gang_id}_fleet" class="input" value="${esc(fleetNpc.role_label||'Vehicle Coordinator')}" placeholder="Vehicle Coordinator"><button class="btn primary" ${can?'':'disabled'} onclick="cmGangFacility('${g.gang_id}','fleet',false)">Set Vehicle NPC Here</button><button class="btn danger" ${can?'':'disabled'} onclick="cmGangFacility('${g.gang_id}','fleet',true)">Disable</button></div>
      <h4>Profit NPC</h4><div class="form"><input id="gangNpcModel_${g.gang_id}_profit" class="input" value="${esc(profitNpc.npc_model||'')}" placeholder="Optional allowlisted model"><input id="gangNpcName_${g.gang_id}_profit" class="input" value="${esc(profitNpc.display_name||'')}" placeholder="NPC name"><input id="gangNpcRole_${g.gang_id}_profit" class="input" value="${esc(profitNpc.role_label||'Profit Manager')}" placeholder="Profit Manager"><button class="btn primary" ${can?'':'disabled'} onclick="cmGangFacility('${g.gang_id}','profit',false)">Set Profit NPC Here</button><button class="btn danger" ${can?'':'disabled'} onclick="cmGangFacility('${g.gang_id}','profit',true)">Disable</button></div>
      <h4>Ranks & access</h4>${(g.ranks||[]).map(r=>`<details><summary>${esc(r.name)} · Tier ${Number(r.tier)}</summary><div class="form"><input id="gangRank_${g.gang_id}_${r.id}_name" class="input" value="${esc(r.name)}"><input id="gangRank_${g.gang_id}_${r.id}_tier" class="input" type="number" min="1" max="100" value="${Number(r.tier)}" ${r.isLeaderRank?'readonly':''}></div><div class="permission-builder">${perms.map(p=>`<label><input data-gang-rank="${g.gang_id}:${r.id}" type="checkbox" value="${esc(p)}" ${r.permissions&&r.permissions[p]?'checked':''} ${r.isLeaderRank?'disabled':''}> ${esc(p)}</label>`).join('')}</div><button class="btn primary" ${can?'':'disabled'} onclick="cmGangRank('${g.gang_id}',${Number(r.id)})">Save rank</button></details>`).join('')}
      <h4>Armory</h4><div class="form"><input id="gangArmItem_${g.gang_id}" class="input" placeholder="cm-weapons item ID"><label><input id="gangArmEnabled_${g.gang_id}" type="checkbox"> Enabled</label><input id="gangArmTier_${g.gang_id}" class="input" type="number" min="1" max="100" value="1" placeholder="Minimum tier"><input id="gangArmQty_${g.gang_id}" class="input" type="number" min="1" value="1" placeholder="Issue quantity"><input id="gangArmLimit_${g.gang_id}" class="input" type="number" min="0" value="0" placeholder="Issue limit"><button class="btn primary" ${can?'':'disabled'} onclick="cmGangArmory('${g.gang_id}')">Save armory item</button><input id="gangArmStock_${g.gang_id}" class="input" type="number" value="0" placeholder="Stock adjustment"><button class="btn" ${can?'':'disabled'} onclick="cmGangArmoryStock('${g.gang_id}')">Adjust stock</button></div><div class="table-wrap"><table><tbody>${(g.armory||[]).map(i=>`<tr><td>${esc(i.item_id)}</td><td>${i.enabled?'Enabled':'Disabled'}</td><td>Tier ${Number(i.minimum_tier||1)}</td><td>Stock ${Number(i.stock_quantity||0)} · issue ${Number(i.issue_quantity||1)} / limit ${Number(i.issue_limit||0)}</td></tr>`).join('')||'<tr><td>No configured armory items</td></tr>'}</tbody></table></div>
      <h4>Vehicles</h4><p class="mini-label">Vehicle access ranks and trunk settings come from Vehicle Admin. Set Location spawns the selected car; drive it into position and press H to save.</p><div class="form"><input id="gangFleetModel_${g.gang_id}" class="input" placeholder="rn-vehicleshop model"><button class="btn primary" ${can?'':'disabled'} onclick="cmGangFleetBegin('${g.gang_id}')">Set Location</button></div><div class="table-wrap"><table><tbody>${(g.fleet||[]).map(v=>{const key=`gangFleet_${g.gang_id}_${v.catalog_id}`;return `<tr><td>${esc(v.catalog_id)}</td><td>vehicle_id ${esc(v.vehicle_id||'not assigned')}</td><td><label><input id="${key}_enabled" type="checkbox" ${v.enabled?'checked':''}> Enabled</label></td><td>Drive tier ${Number(v.minimum_tier||1)}</td><td>Trunk tier ${Number(v.trunk_minimum_tier||1)}</td><td><button class="btn small primary" ${can?'':'disabled'} onclick="cmGangFleetSave('${g.gang_id}','${esc(v.catalog_id)}')">Save</button><button class="btn small" ${can?'':'disabled'} onclick="cmGangFleetBegin('${g.gang_id}','${esc(v.catalog_id)}')">Set Location</button><button class="btn small danger" ${can?'':'disabled'} onclick="cmGangFleetReset('${g.gang_id}','${esc(v.catalog_id)}')">Reset location</button><button class="btn small danger" ${can&&v.vehicle_id?'':'disabled'} onclick="cmGangFleetDelete('${g.gang_id}','${esc(v.catalog_id)}','${esc(v.vehicle_id||'')}')">Delete vehicle</button></td></tr>`}).join('')||'<tr><td>No configured fleet vehicles</td></tr>'}</tbody></table></div>
      <h4>Stash</h4><p>Owner: <code>gang_stash:${esc(g.gang_id)}</code>. Access and every movement are revalidated by cm-inventory.</p>
      <h4>Wardrobe</h4><p>${(g.wardrobe||[]).map(x=>`${esc(x.name)} (${esc(x.sex)}, tier ${Number(x.minimum_tier||1)})`).join(' · ')||'No outfits configured.'}</p>
      <h4>Profit</h4><p>$${Number(g.profit?.pending_amount||0).toLocaleString()} pending · ${Number(g.profit?.activity_score||0)} activity score · last tick ${esc(g.profit?.last_tick_at||'never')}</p>
      <h4>Blacklist</h4><p>${(g.blacklist||[]).map(x=>`${esc(x.character_name_snapshot||'CID '+x.character_id)} — ${esc(x.reason||'No reason')}`).join('<br>')||'No blacklisted characters.'}</p>
      <h4>Recent activity</h4><div class="table-wrap"><table><tbody>${(g.activity||[]).map(a=>`<tr><td>${esc(a.created_at)}</td><td>${esc(a.action)}</td><td>${esc(a.actor_character_id||'system')}</td><td>${esc(a.target_character_id||'')}</td></tr>`).join('')||'<tr><td>No activity</td></tr>'}</tbody></table></div>
      <h4>Recovery</h4><p>${Number(recovery.leaderMembers||0)} leader membership row(s) · ${Number(recovery.staleInvites||0)} expired pending invite(s)</p><div class="actions"><button class="btn" ${can?'':'disabled'} onclick="cmGangRecover('${g.gang_id}','expire_invites')">Expire stale invites</button><button class="btn" ${can?'':'disabled'} onclick="cmGangRecover('${g.gang_id}','reload_cache')">Reload owner cache</button></div>
      <h4>Legacy Gang Migration</h4><p class="mini-label">Explicitly move one legacy slot into this empty canonical gang. No mapping is guessed.</p><div class="form"><select id="gangLegacy_${g.gang_id}" class="input">${(payload.legacyGangIds||[]).map(x=>`<option value="${esc(x)}">${esc(x)}</option>`).join('')}</select><button class="btn danger" ${can?'':'disabled'} onclick="cmGangLegacyMigrate('${g.gang_id}')">Migrate transactionally</button></div>
    </div>`; }).join('');
}

window.cmGangGraffitiPlacement=function(mode,id){const key=id||'new';gangAdminAction('graffitiPlacement','',{mode,id:id||null,name:document.getElementById(`graffitiName_${key}`).value,gangId:document.getElementById(`graffitiGang_${key}`).value||null,width:Number(document.getElementById(`graffitiWidth_${key}`)?.value||2),height:Number(document.getElementById(`graffitiHeight_${key}`)?.value||1.2),enabled:document.getElementById(`graffitiEnabled_${key}`)?.checked!==false})};
window.cmGangGraffitiSaveMetadata=function(id){gangAdminAction('graffiti','',{id,name:document.getElementById(`graffitiName_${id}`).value,gangId:document.getElementById(`graffitiGang_${id}`).value||null,enabled:document.getElementById(`graffitiEnabled_${id}`).checked})};
window.cmGangGraffitiRemove=id=>{if(confirm(`Delete graffiti #${id}? This removes the location immediately.`))gangAdminAction('graffiti','',{id,remove:true})};
window.cmGangForceSnapshot=()=>gangAdminAction('forceTurfSnapshot','',{});
window.cmGangEventAction=(operation,eventAction,extra={})=>gangAdminAction(operation,'',Object.assign({eventAction},extra));
function supplyWarAdmin(){const e=(state.data.gangs||{}).events||{},c=e.config||{},drops=e.dropLocations||[],entries=e.entryPoints||[],rewards=e.rewards||[],history=e.history||[],can=hasPerm('gang.admin.manage');const ep=id=>entries.find(x=>x.gang_id===id);return `<div class="card"><div class="section-head"><div><small>GANGS · EVENTS · SUPPLY WAR</small><h3>Supply War Event Manager</h3><p>State: ${esc(e.state?.state||'IDLE')} · ${esc(e.state?.eventId||'No active instance')}</p></div><div class="actions"><button class="btn primary" ${can?'':'disabled'} onclick="cmGangEventAction('eventConfig','configBegin')">ENTER CONFIG MODE</button><button class="btn primary" ${can?'':'disabled'} onclick="cmGangEventAction('eventStart')">START</button><button class="btn" ${can?'':'disabled'} onclick="cmGangEventAction('eventStop')">STOP</button><button class="btn danger" ${can?'':'disabled'} onclick="cmGangEventAction('eventCancel')">CANCEL</button></div></div><div class="card"><strong>CONFIG MODE</strong><p>1. Select event center → 2. Preview/change circle size → 3. Add drop locations with world previews → 4. Configure rewards/timing → 5. Preview complete event → 6. Save.</p></div>
<details open><summary>Overview / Timing / Scoring / Combat</summary><div class="form"><label><input id="swEnabled" type="checkbox" ${c.enabled?'checked':''}> Enabled</label><input id="swName" class="input" value="${esc(c.event_name||'Gang Supply War')}" placeholder="Event name"><input id="swAnn" type="number" value="${Number(c.announcement_seconds||60)}" placeholder="Announcement seconds"><input id="swDuration" type="number" value="${Number(c.duration_seconds||1500)}" placeholder="Duration seconds"><input id="swBucket" type="number" value="${Number(c.routing_bucket||7100)}" placeholder="Reserved bucket"><input id="swMaxDrops" type="number" value="${Number(c.max_active_drops||2)}" placeholder="Max active drops"><input id="swCapture" type="number" value="${Number(c.capture_seconds||4)}" placeholder="Capture seconds"><input id="swContested" type="number" value="${Number(c.contested_capture_seconds||7)}" placeholder="Contested seconds"><input id="swContestRadius" type="number" value="${Number(c.contest_radius||20)}" placeholder="Contest radius"><input id="swKillPoints" type="number" value="${Number(c.kill_points||1)}" placeholder="Kill points"><input id="swAntiFarm" type="number" value="${Number(c.anti_farm_seconds||90)}" placeholder="Anti-farm seconds"><input id="swCombat" type="number" value="${Number(c.combat_tag_seconds||15)}" placeholder="Combat tag seconds"><input id="swReentry" type="number" value="${Number(c.reentry_cooldown_seconds||40)}" placeholder="Re-entry seconds"><button class="btn primary" ${can?'':'disabled'} onclick="cmGangEventAction('eventConfig','settings',{enabled:swEnabled.checked,name:swName.value,announcement:+swAnn.value,duration:+swDuration.value,bucket:+swBucket.value,maxDrops:+swMaxDrops.value,capture:+swCapture.value,contested:+swContested.value,contestRadius:+swContestRadius.value,killPoints:+swKillPoints.value,antiFarm:+swAntiFarm.value,combatTag:+swCombat.value,reentry:+swReentry.value})">SAVE SETTINGS</button></div></details>
<details><summary>Zone</summary><p>${c.zone_x==null?'Not configured':`${Number(c.zone_x).toFixed(1)}, ${Number(c.zone_y).toFixed(1)}, ${Number(c.zone_z).toFixed(1)} · radius ${Number(c.zone_radius)}m`}</p><div class="form"><input id="swZoneLabel" class="input" value="${esc(c.area_name||'')}" placeholder="Display name"><input id="swRadius" type="number" min="50" max="1000" value="${Number(c.zone_radius||250)}"><button class="btn primary" ${can?'':'disabled'} onclick="cmGangEventAction('eventConfig','zoneHere',{label:swZoneLabel.value,radius:+swRadius.value})">SET CURRENT LOCATION</button></div></details>
<details><summary>Drop Locations</summary><div class="form"><input id="swDropLabel" class="input" placeholder="Location label"><button class="btn primary" ${can?'':'disabled'} onclick="cmGangEventAction('eventConfig','dropHere',{label:swDropLabel.value})">ADD CURRENT LOCATION</button></div><div class="table-wrap"><table><tbody>${drops.map(x=>`<tr><td>#${x.id} ${esc(x.label)}</td><td>${Number(x.x).toFixed(1)}, ${Number(x.y).toFixed(1)}</td><td><button class="btn small" ${can?'':'disabled'} onclick="cmGangEventAction('eventConfig','dropToggle',{id:${x.id},enabled:${x.enabled?false:true}})">${x.enabled?'DISABLE':'ENABLE'}</button><button class="btn small danger" ${can?'':'disabled'} onclick="cmGangEventAction('eventConfig','dropDelete',{id:${x.id}})">DELETE</button></td></tr>`).join('')||'<tr><td>No drop locations configured.</td></tr>'}</tbody></table></div></details>
<details><summary>Rewards</summary><div class="form"><select id="swTier"><option>BASIC</option><option>IMPROVED</option><option>HIGH_VALUE</option></select><input id="swItem" class="input" placeholder="Authoritative item ID"><input id="swMin" type="number" value="1" min="1"><input id="swMax" type="number" value="1" min="1"><input id="swWeight" type="number" value="1" min="1"><button class="btn primary" ${can?'':'disabled'} onclick="cmGangEventAction('eventConfig','rewardSave',{tier:swTier.value,itemId:swItem.value,min:+swMin.value,max:+swMax.value,weight:+swWeight.value})">SAVE REWARD</button></div><p>${rewards.map(x=>`${esc(x.tier)}: ${esc(x.item_id)} (${x.min_quantity}-${x.max_quantity})`).join(' · ')||'No rewards configured.'}</p></details>
<details><summary>History</summary><div class="table-wrap"><table><tbody>${history.map(x=>`<tr><td>${esc(x.event_id)}</td><td>${esc(x.status)}</td><td>${esc(x.winning_gang_id||'—')}</td><td>${esc(x.end_reason||'—')}</td></tr>`).join('')||'<tr><td>No event history.</td></tr>'}</tbody></table></div></details>
<button class="btn danger" ${can?'':'disabled'} onclick="confirm('Reset Supply War settings?')&&cmGangEventAction('eventConfig','reset',{confirm:true})">RESET CONFIG</button></div>`}
supplyWarAdmin=function(){const e=(state.data.gangs||{}).events||{},c=e.config||{},x=e.extra||{},s=x.schedule||{},vp=x.vehiclePolicy||{allowVehicles:false,allowedClasses:[]},wb=x.worldBoundary||{enabled:true,renderDistance:150},pkg=x.rewardPackage||[{item:'weapon_smg',amount:1},{item:'weapon_assaultrifle',amount:1},{item:'ammo_9x19_smg',amount:100},{item:'ammo_556nato',amount:120}],drops=e.dropLocations||[],history=e.history||[],can=hasPerm('gang.admin.manage'),next=Number(e.schedule?.nextAt||0),warmupAt=next-Math.max(0,Number(s.warmupMinutes??5))*60,auto=e.schedule?.enabled??s.autoStart??true,stateLabel=e.state?.state==='ANNOUNCED'?'WARMUP':e.state?.state||'IDLE',deadline=stateLabel==='LIVE'?Number(e.state?.endsAt||0):stateLabel==='WARMUP'?Number(e.state?.liveAt||0):0,remaining=deadline?Math.max(0,deadline-Math.floor(Date.now()/1000)):0,remainingText=`${Math.floor(remaining/60)}:${String(Math.floor(remaining%60)).padStart(2,'0')}`;return `<div class="card"><div class="section-head"><div><small>GANGS · EVENTS</small><h3>Supply War</h3></div><div class="actions"><button class="btn primary" ${can?'':'disabled'} onclick="cmGangEventAction('eventStart')">START NOW</button><button class="btn danger" ${can?'':'disabled'} onclick="cmGangEventAction('eventStop')">STOP</button></div></div><div class="quick-stats"><div class="stat"><small>STATE</small><strong>${esc(stateLabel)}</strong></div><div class="stat"><small>${stateLabel==='LIVE'?'ENDS IN':'STARTS IN'}</small><strong>${deadline?remainingText:'—'}</strong></div><div class="stat"><small>AUTO START</small><strong>${auto?'ON':'OFF'}</strong></div><div class="stat"><small>NEXT EVENT</small><strong>${next?new Date(next*1000).toLocaleString():'CALCULATING'}</strong></div><div class="stat"><small>WARMUP</small><strong>${next?new Date(warmupAt*1000).toLocaleString():'—'}</strong></div><div class="stat"><small>DURATION</small><strong>${Math.round(Number(c.duration_seconds||1200)/60)} MINUTES</strong></div></div>
<details open><summary>Main Event & Automatic Schedule</summary><div class="form"><label><input id="swEnabled" type="checkbox" ${c.enabled?'checked':''}> Event enabled</label><label><input id="swAuto" type="checkbox" ${(s.autoStart??true)?'checked':''}> Automatic Supply War</label><input id="swDuration" type="number" min="5" max="120" value="${Number(c.duration_seconds||1200)/60}" placeholder="Duration minutes"><input id="swInterval" type="number" min="1" max="24" value="${Number(s.intervalHours||2)}" placeholder="Interval hours"><input id="swAnchorHour" type="number" min="0" max="23" value="${Number(s.anchorHour||0)}" placeholder="Anchor hour"><input id="swAnchorMinute" type="number" min="0" max="59" value="${Number(s.anchorMinute||0)}" placeholder="Anchor minute"><input id="swGrace" type="number" min="0" max="30" value="${Number(s.graceMinutes||5)}" placeholder="Restart grace minutes"><input id="swWarmup" type="number" min="0" max="60" value="${Number(s.warmupMinutes||5)}" placeholder="Warmup minutes"><input id="swBoundaryWarning" type="number" min="1" max="30" value="${Number(c.boundary_grace_seconds||5)}" placeholder="Boundary warning seconds"><input id="swBoundaryCooldown" type="number" min="0" max="3600" value="${Number(x.boundaryCooldownSeconds||120)}" placeholder="Boundary penalty seconds"><input id="swKillPoints" type="number" min="0" max="20" value="${Number(c.kill_points||1)}" placeholder="Kill points"><input id="swSupplyPoints" type="number" min="0" max="100" value="${Number(x.supplyPoints||5)}" placeholder="Supply points"><input id="swCapture" type="number" min="2" max="30" value="${Number(c.capture_seconds||4)}" placeholder="Capture seconds"><button class="btn primary" ${can?'':'disabled'} onclick="cmGangEventAction('eventConfig','settings',{enabled:swEnabled.checked,autoStart:swAuto.checked,duration:+swDuration.value*60,intervalHours:+swInterval.value,anchorHour:+swAnchorHour.value,anchorMinute:+swAnchorMinute.value,graceMinutes:+swGrace.value,warmupMinutes:+swWarmup.value,joinRing:+swRuleJoinRing.value,deathReentry:+swRuleDeathReentry.value,boundaryWarning:+swBoundaryWarning.value,boundaryCooldown:+swBoundaryCooldown.value,killPoints:+swKillPoints.value,supplyPoints:+swSupplyPoints.value,capture:+swCapture.value,allowVehicles:swRuleVehicles.checked,allowedVehicleClasses:swRuleVehicleClasses.value.split(',').map(Number),worldBoundaryEnabled:swRuleWorldBoundary.checked,worldBoundaryRenderDistance:+swRuleBoundaryRange.value,supplyNotificationEnabled:swRuleSupplyNotify.checked,warmupAreaMessageEnabled:swRuleWarmupMessage.checked})">SAVE SETTINGS</button></div></details>
<details open><summary>Gameplay Rules</summary><div class="form"><input id="swRuleJoinRing" type="number" min="1" max="50" value="${Number(x.joinRingWidth||8)}" placeholder="Join ring width metres"><input id="swRuleDeathReentry" type="number" min="0" max="3600" value="${Number(x.deathReentryCooldownSeconds||120)}" placeholder="Death re-entry seconds"><label><input id="swRuleVehicles" type="checkbox" ${vp.allowVehicles?'checked':''}> Allow vehicles (default off)</label><input id="swRuleVehicleClasses" class="input" value="${esc((vp.allowedClasses||[]).join(','))}" placeholder="Optional GTA classes, e.g. 8,9"><label><input id="swRuleWorldBoundary" type="checkbox" ${wb.enabled!==false?'checked':''}> World boundary visible</label><input id="swRuleBoundaryRange" type="number" min="25" max="500" value="${Number(wb.renderDistance||150)}" placeholder="Boundary render range metres"><label><input id="swRuleSupplyNotify" type="checkbox" ${x.supplyNotificationEnabled!==false?'checked':''}> Supply notification</label><label><input id="swRuleWarmupMessage" type="checkbox" ${x.warmupAreaMessageEnabled!==false?'checked':''}> Warmup area message</label></div></details>
<details><summary>Event Circle</summary><p>${c.zone_x==null?'Not configured':`${Number(c.zone_x).toFixed(1)}, ${Number(c.zone_y).toFixed(1)}, ${Number(c.zone_z).toFixed(1)} · radius ${Number(c.zone_radius)}m`}</p><div class="form"><input id="swZoneLabel" class="input" value="${esc(c.area_name||'')}" placeholder="Area name"><input id="swRadius" type="number" min="25" max="1000" value="${Number(c.zone_radius||150)}"><button class="btn primary" ${can?'':'disabled'} onclick="cmGangEventAction('eventConfig','zoneHere',{label:swZoneLabel.value,radius:+swRadius.value})">SET EVENT CENTER TO MY POSITION</button><button class="btn" ${can?'':'disabled'} onclick="cmGangEventAction('eventConfig','configBegin')">WORLD CONFIG MODE</button></div></details>
<details><summary>Supply Drop Locations & Timing</summary><div class="form"><input id="swDropLabel" class="input" placeholder="Drop label"><button class="btn primary" ${can?'':'disabled'} onclick="cmGangEventAction('eventConfig','dropHere',{label:swDropLabel.value})">+ ADD SUPPLY DROP AT MY POSITION</button></div><div class="table-wrap"><table><thead><tr><th>Location</th><th>Spawn after</th><th>Points</th><th>Final</th><th></th></tr></thead><tbody>${drops.map((d,i)=>{const timing=(x.drops||[])[i]||{at:i*300,points:5,final:false};return `<tr><td>Drop #${i+1} · ${esc(d.label)}<br><small>${Number(d.x).toFixed(1)}, ${Number(d.y).toFixed(1)}, ${Number(d.z).toFixed(1)}</small></td><td><input id="swDropAt_${i}" type="number" min="0" max="7200" value="${Number(timing.at??timing.land??0)}"> sec</td><td><input id="swDropPoints_${i}" type="number" min="0" max="100" value="${Number(timing.points??5)}"></td><td><input id="swDropFinal_${i}" type="checkbox" ${timing.final?'checked':''}></td><td><button class="btn small primary" ${can?'':'disabled'} onclick="cmGangEventAction('eventConfig','dropMoveHere',{id:${Number(d.id)}})">SET TO MY POSITION</button><button class="btn small primary" ${can?'':'disabled'} onclick="cmGangEventAction('eventConfig','dropScheduleSave',{index:${i+1},at:+document.getElementById('swDropAt_${i}').value,points:+document.getElementById('swDropPoints_${i}').value,final:document.getElementById('swDropFinal_${i}').checked})">SAVE</button><button class="btn small danger" ${can?'':'disabled'} onclick="cmGangEventAction('eventConfig','dropDelete',{id:${Number(d.id)}})">DELETE</button></td></tr>`}).join('')||'<tr><td colspan="5">No drop locations configured.</td></tr>'}</tbody></table></div></details>
<details open><summary>Supply Reward Package</summary><div class="form"><input id="swRewardItem" class="input" placeholder="Registered item ID"><input id="swRewardAmount" type="number" min="1" max="10000" value="1"><button class="btn primary" ${can?'':'disabled'} onclick="cmGangEventAction('eventConfig','rewardPackageAdd',{itemId:swRewardItem.value,amount:+swRewardAmount.value})">+ ADD / UPDATE ITEM</button></div><div class="table-wrap"><table><thead><tr><th>Item</th><th>Amount</th><th></th></tr></thead><tbody>${pkg.map(r=>`<tr><td>${esc(r.item)}</td><td>${Number(r.amount)}</td><td><button class="btn small danger" ${can?'':'disabled'} onclick="cmGangEventAction('eventConfig','rewardPackageRemove',{itemId:'${esc(r.item)}'})">REMOVE</button></td></tr>`).join('')}</tbody></table></div></details>
<details><summary>Event History</summary><div class="table-wrap"><table><tbody>${history.map(row=>`<tr><td>${esc(row.event_id)}</td><td>${esc(row.status)}</td><td>${esc(row.winning_gang_id||'—')}</td><td>${esc(row.end_reason||'—')}</td></tr>`).join('')||'<tr><td>No event history.</td></tr>'}</tbody></table></div></details></div>`};
const gangsPageSupplyWarBase=gangsPage;gangsPage=function(){return supplyWarAdmin()+gangsPageSupplyWarBase()};
const graffitiRenderBase=renderGangWeaponCatalog;
renderGangWeaponCatalog=function(){graffitiRenderBase();const payload=state.data.gangs||{},can=hasPerm('gang.admin.manage'),rows=Object.values(payload.graffiti||{}).sort((a,b)=>Number(a.id)-Number(b.id)),gangs=payload.gangs||[],gangOptions=(selected='')=>gangs.map(g=>`<option value="${esc(g.gang_id)}" ${g.gang_id===selected?'selected':''}>${esc(g.display_name)}</option>`).join('');const card=document.createElement('div');card.className='card';card.innerHTML=`<div class="section-head"><div><h3>GRAFFITI LOCATIONS</h3><p class="mini-label">Admin wall placement only. Gang members can repaint saved walls but cannot create them.</p></div><button class="btn" ${can?'':'disabled'} onclick="cmGangForceSnapshot()">Force Turf Snapshot</button></div><div class="quick-stats"><div class="stat"><small>TOTAL TAGS</small><strong>${rows.length}</strong></div><div class="stat"><small>ENABLED</small><strong>${rows.filter(x=>x.enabled).length}</strong></div></div><h4>+ CREATE GRAFFITI</h4><div class="form"><input id="graffitiName_new" class="input" placeholder="Forum Drive Alley"><select id="graffitiGang_new" class="input">${gangOptions()}</select><input id="graffitiWidth_new" class="input" type="number" min=".5" max="10" step=".1" value="2"><input id="graffitiHeight_new" class="input" type="number" min=".25" max="6" step=".1" value="1.2"><label><input id="graffitiEnabled_new" type="checkbox" checked> Enabled</label><button class="btn primary" ${can?'':'disabled'} onclick="cmGangGraffitiPlacement('create',null)">Start Placement</button></div><div class="table-wrap"><table><thead><tr><th>Location</th><th>Owner</th><th>Status</th><th>Controls</th></tr></thead><tbody>${rows.map(x=>`<tr><td><strong>#${Number(x.id)} · ${esc(x.name)}</strong><br><small>${x.placementReady?'Wall transform saved':'Needs placement upgrade'} · ${Number(x.width).toFixed(2)} × ${Number(x.height).toFixed(2)} m</small><input id="graffitiName_${x.id}" class="input" value="${esc(x.name)}"><input id="graffitiWidth_${x.id}" type="hidden" value="${Number(x.width)}"><input id="graffitiHeight_${x.id}" type="hidden" value="${Number(x.height)}"></td><td><select id="graffitiGang_${x.id}" class="input">${gangOptions(x.gangId)}</select></td><td><label><input id="graffitiEnabled_${x.id}" type="checkbox" ${x.enabled?'checked':''}> Enabled</label></td><td><button class="btn small primary" ${can?'':'disabled'} onclick="cmGangGraffitiPlacement('edit',${x.id})">Edit Placement</button><button class="btn small" ${can?'':'disabled'} onclick="cmGangGraffitiPlacement('duplicate',${x.id})">Duplicate</button><button class="btn small" ${can?'':'disabled'} onclick="cmGangGraffitiSaveMetadata(${x.id})">Save Details</button><button class="btn small danger" ${can?'':'disabled'} onclick="cmGangGraffitiRemove(${x.id})">Delete</button></td></tr>`).join('')||'<tr><td colspan="4">No graffiti locations configured.</td></tr>'}</tbody></table></div>`;page.appendChild(card)};

function rankOptions(selected) {
  return (state.data.ranks || []).map(r => `<option value="${esc(r.name)}" ${r.name === selected ? 'selected' : ''}>${esc(r.label)} (${esc(r.name)})</option>`).join('');
}

const tabs = [
  { id: 'dashboard', label: 'Dashboard', hint: 'Overview', perm: null },
  { id: 'players', label: 'Players', hint: 'Online', perm: 'players.view' },
  { id: 'offline', label: 'Offline', hint: 'Search DB', perm: 'players.view' },
  { id: 'map', label: 'Map', hint: 'Live', perm: 'players.view' },
  { id: 'developer', label: 'Developer', hint: 'Tools', perm: 'dev.view' },
  { id: 'inventory', label: 'Inventory', hint: 'Items', perm: 'inventory.view' },
  { id: 'vehicles', label: 'Vehicles', hint: 'Cars', perm: 'vehicles.view' },
  { id: 'orgs', label: 'Organizations', hint: 'Leadership', perm: 'orgs.view' },
  { id: 'gangs', label: 'Gangs', hint: 'Five fixed gangs', perm: 'gang.admin.view' },
  { id: 'admins', label: 'Admins', hint: 'Staff', perm: 'admins.view' },
  { id: 'ranks', label: 'Ranks', hint: 'Perms', perm: 'ranks.view' },
  { id: 'logs', label: 'Logs', hint: 'Audit', perm: 'logs.view' },
];

function renderNav() {
  nav.innerHTML = tabs
    .filter(t => !t.perm || hasPerm(t.perm))
    .map(t => `<button class="${state.tab === t.id ? 'active' : ''}" onclick="cmSetTab('${t.id}')"><b>${t.label}</b><span>${t.hint}</span></button>`)
    .join('');
}

window.cmSetTab = function(tab) {
  state.tab = tab;
  state.detail = null;
  render();
};

function selectedPlayer() {
  const players = state.data.players || [];
  return players.find(p => Number(p.id) === Number(state.selectedPlayer)) || players[0] || null;
}

window.cmSelectPlayer = function(id) {
  state.selectedPlayer = Number(id);
  state.detail = null;
  render();
};

function formatCoords(p) {
  if (!p || !p.coords) return '-';
  return `${p.coords.x}, ${p.coords.y}, ${p.coords.z}`;
}

function money(value) {
  if (value === null || value === undefined || value === '') return '-';
  const n = Number(value);
  if (!Number.isFinite(n)) return '-';
  return '$' + n.toLocaleString();
}

function dashboard() {
  const players = state.data.players || [];
  const admins = state.data.admins || [];
  const ranks = state.data.ranks || [];
  const logs = state.data.logs || [];
  return `
    <div class="grid cols-4">
      <div class="card stat"><small>Online players</small><strong>${players.length}</strong><span>Live server</span></div>
      <div class="card stat"><small>Admins online</small><strong>${players.filter(p => p.adminMode).length}</strong><span>/admin mode</span></div>
      <div class="card stat"><small>Ranks</small><strong>${ranks.length}</strong><span>Permission groups</span></div>
      <div class="card stat"><small>Recent logs</small><strong>${logs.length}</strong><span>Audit trail</span></div>
    </div>
    <div class="grid cols-3" style="margin-top:16px">
      <div class="card">
        <h3>How this works</h3>
        <div class="detail-grid">
          <div class="kv"><small>Join game</small><strong>Normal player</strong></div>
          <div class="kv"><small>Enable admin</small><strong>/admin</strong></div>
          <div class="kv"><small>Open menu</small><strong>F11</strong></div>
          <div class="kv"><small>Noclip</small><strong>F2 / noclip</strong></div>
        </div>
      </div>
      <div class="card">
        <h3>Your admin profile</h3>
        <div class="detail-grid">
          <div class="kv"><small>Name</small><strong>${esc(state.data.me.name)}</strong></div>
          <div class="kv"><small>Rank</small><strong>${esc(state.data.me.rankLabel || state.data.me.rank)}</strong></div>
          <div class="kv"><small>Level</small><strong>${esc(state.data.me.level)}</strong></div>
          <div class="kv"><small>Character ID</small><strong>${esc(state.data.me.characterId || '-')}</strong></div><div class="kv"><small>Admin Key</small><strong>${esc(state.data.me.identifier)}</strong></div>
        </div>
      </div>
      <div class="card">
        <h3>Quick Tools</h3>
        <div class="actions vertical">
          ${(hasPerm('gps.teleport') || hasPerm('teleport') || hasPerm('players.teleport')) ? `<button class="btn primary" onclick="action('gpsTeleport')">GPS Teleport</button>` : ''}
          ${hasPerm('map.view') || hasPerm('players.view') ? `<button class="btn" onclick="cmSetTab('map')">Open Live Map</button>` : ''}
          ${hasPerm('ems.admin.manage') ? `<button class="btn" onclick="action('openEmsManagement')">Open EMS Management</button>` : ''}
          ${hasPerm('dev.view') ? `<button class="btn" onclick="cmSetTab('developer')">Open Developer Launchers</button>` : ''}
        </div>
      </div>
    </div>`;
}

function playersPage() {
  const players = state.data.players || [];
  const selected = selectedPlayer();
  if (selected && !state.selectedPlayer) state.selectedPlayer = selected.id;

  const distLabel = (p) => {
    if (p.isSelf) return 'YOU';
    if (p.distance === undefined || p.distance === null) return '';
    if (p.distance < 50) return `NEARBY · ${p.distance}m`;
    if (p.distance < 1000) return `${p.distance}m`;
    return `${(p.distance / 1000).toFixed(1)}km`;
  };

  const list = players.map(p => `
    <button class="item ${selected && Number(selected.id) === Number(p.id) ? 'active' : ''}" onclick="cmSelectPlayer(${Number(p.id)})">
      <div class="avatar">${esc(p.characterId || '?')}</div>
      <div><strong>${esc(p.name)}</strong><small>Char ${esc(p.characterId || '-')} · Ping ${esc(p.ping)}${p.cash !== undefined && p.cash !== null ? ` · $${Number(p.cash).toLocaleString()} / $${Number(p.bank || 0).toLocaleString()}` : ''}${distLabel(p) ? ' · ' + distLabel(p) : ''}</small></div>
      <span class="badge ${p.distance !== undefined && p.distance < 50 && !p.isSelf ? 'near' : (p.adminMode ? '' : 'off')}">${p.isSelf ? 'You' : (p.distance !== undefined && p.distance < 50 ? 'Nearby' : (p.adminMode ? 'Admin' : 'Player'))}</span>
    </button>`).join('');

  return `
    <div class="player-list">
      <div class="card">
        <h3>Online Players</h3>
        <div class="list">${list || '<div class="empty">No players online</div>'}</div>
      </div>
      <div>${selected ? playerDetail(selected) : '<div class="empty">Select a player</div>'}</div>
    </div>`;
}

function playerDetail(p) {
  return `
    <div class="card">
      <h3>${esc(p.name)} <span class="badge">Char ${esc(p.characterId || '-')}</span></h3>
      <div class="detail-grid">
        <div class="kv"><small>Character ID</small><strong>${esc(p.characterId || '-')}</strong></div>
        <div class="kv"><small>Character name</small><strong>${esc(p.characterName || '-')}</strong></div>
        <div class="kv"><small>Session source</small><strong>${esc(p.id || '-')}</strong></div>
        <div class="kv"><small>Identifier</small><strong>${esc(p.identifier || '-')}</strong></div>
        <div class="kv"><small>Cash / Bank</small><strong>${esc(money(p.cash))} / ${esc(money(p.bank))}</strong></div>
        <div class="kv"><small>Coords</small><strong>${esc(formatCoords(p))}</strong></div>
      </div>
      <div class="actions">
        ${hasPerm('players.teleport') ? `<button class="btn small primary" onclick="cmPlayerAction(${p.id}, 'goto')">Go To</button><button class="btn small primary" onclick="cmPlayerAction(${p.id}, 'bring')">Bring</button>` : ''}
        ${hasPerm('players.freeze') ? `<button class="btn small" onclick="cmPlayerAction(${p.id}, 'freeze')">Freeze</button><button class="btn small" onclick="cmPlayerAction(${p.id}, 'unfreeze')">Unfreeze</button>` : ''}
        ${hasPerm('tools.heal') ? `<button class="btn small success" onclick="cmPlayerAction(${p.id}, 'heal')">Heal</button><button class="btn small success" onclick="cmPlayerAction(${p.id}, 'armor')">Armor</button>` : ''}
        ${(hasPerm('money.manage') || hasPerm('players.manage')) ? `<button class="btn small success" onclick="cmGiveCash(${p.id})">Give Cash</button>` : ''}
        ${hasPerm('inventory.view') ? `<button class="btn small" onclick="cmViewInventory(${p.id})">View Inventory</button>` : ''}
        ${hasPerm('vehicles.view') ? `<button class="btn small" onclick="cmViewVehicles(${p.id})">View Cars</button>` : ''}
        ${hasPerm('vehicles.manage') ? `<button class="btn small" onclick="cmPlayerAction(${p.id}, 'repair_vehicle')">Repair Vehicle</button><button class="btn small danger" onclick="cmPlayerAction(${p.id}, 'delete_vehicle')">Delete Vehicle</button>` : ''}
        ${hasPerm('players.kick') ? `<button class="btn small danger" onclick="cmKick(${p.id})">Kick</button>` : ''}
      </div>
    </div>
    ${detailBlock()}`;
}

window.cmPlayerAction = function(target, playerAction) {
  action('playerAction', { target, playerAction });
};

window.cmGiveCash = function(target) {
  const raw = prompt('Cash amount to give?', '1000');
  if (raw === null) return;
  const amount = Math.floor(Number(String(raw).replace(/[^0-9.]/g, '')));
  if (!Number.isFinite(amount) || amount < 1) {
    alert('Enter a valid cash amount.');
    return;
  }
  const reason = prompt('Reason for audit log?', 'Admin cash grant');
  if (reason === null) return;
  action('playerAction', { target, playerAction: 'give_cash', amount, reason });
};

window.cmKick = function(target) {
  const reason = prompt('Kick reason?', 'Kicked by admin');
  if (reason === null) return;
  action('playerAction', { target, playerAction: 'kick', reason });
};

window.cmViewInventory = function(target) {
  state.tab = 'inventory';
  state.selectedPlayer = Number(target);
  state.detail = null;
  render();
  action('viewInventory', { target });
};

window.cmViewVehicles = function(target) {
  state.tab = 'vehicles';
  state.selectedPlayer = Number(target);
  state.detail = null;
  render();
  action('viewVehicles', { target });
};

function inventoryPage() {
  const p = selectedPlayer();
  return `
    <div class="grid cols-2">
      <div class="card">
        <h3>Player Inventory</h3>
        ${p ? `<p class="mini-label">Selected player</p><div class="kv"><small>${esc(p.name)}</small><strong>ID ${esc(p.id)} · Char ${esc(p.characterId || '-')}</strong></div><br><button class="btn primary" onclick="cmViewInventory(${p.id})">Load Inventory</button>` : '<div class="empty">Select a player from Players tab first</div>'}
      </div>
      <div class="card">
        <h3>Bridge Info</h3>
        <p class="mini-label">The script safely tries your configured CM inventory SQL tables. Missing tables do not crash the server.</p>
      </div>
    </div>
    ${detailBlock()}`;
}

function vehiclesPage() {
  const p = selectedPlayer();
  return `
    <div class="grid cols-2">
      <div class="card">
        <h3>Player Cars</h3>
        ${p ? `<div class="kv"><small>${esc(p.name)}</small><strong>ID ${esc(p.id)} · Char ${esc(p.characterId || '-')}</strong></div><br><button class="btn primary" onclick="cmViewVehicles(${p.id})">Load Player Cars</button>` : '<div class="empty">Select a player from Players tab first</div>'}
      </div>
      <div class="card">
        <h3>Car Inventory</h3>
        <div class="form">
          <div class="field"><label>Plate</label><input id="plateInput" class="input" placeholder="ABC123" /></div>
          <button class="btn primary" onclick="cmViewVehicleInventory()">Load Trunk / Vehicle Inventory</button>
        </div>
      </div>
    </div>
    ${detailBlock()}`;
}

window.cmViewVehicleInventory = function() {
  const plate = document.getElementById('plateInput').value;
  action('viewVehicleInventory', { plate });
};

function orgsPage() {
  const orgs = state.data.orgs || { list: [], policy: {} };
  const list = orgs.list || [];
  const policy = orgs.policy || {};
  const canManage = hasPerm('orgs.manage');
  return `
    <div class="card">
      <h3>Organizations</h3>
      <p class="mini-label">Every self-registered organization (EMS, Police, and any future ones) in one place. Assigning a leader here calls that organization's own leader-assignment logic directly -- it's the same action as using its own dashboard's Admin tab.</p>
      <div class="table-wrap">
        <table><thead><tr><th>Organization</th><th>Status</th><th>Leader</th><th>Members</th><th>On duty</th><th>Leadership</th><th>Facilities</th></tr></thead><tbody>
          ${list.map(o => `<tr>
            <td>${esc(o.label)}</td>
            <td><span class="badge ${o.running ? '' : 'off'}">${o.running ? 'Running' : 'Stopped'}</span></td>
            <td>${o.leaderCid ? `${esc(o.leaderName || 'Unknown')} (CID ${esc(o.leaderCid)})` : 'Not assigned'}</td>
            <td>${Number(o.memberCount || 0)}</td>
            <td>${Number(o.onDutyCount || 0)}</td>
            <td>${canManage && o.running ? `<div class="form" style="gap:8px"><input id="orgLeaderCid_${esc(o.id)}" class="input" placeholder="Character ID" style="width:120px" /><button class="btn small primary" onclick="cmAssignOrgLeader('${esc(o.id)}')">Assign</button>${o.leaderCid && o.canRemoveLeader ? `<button class="btn small danger" onclick="cmRemoveOrgLeader('${esc(o.id)}')">Remove current</button>` : ''}</div>` : '-'}</td>
            <td>${canManage&&o.running?`<div class="form" style="gap:8px">${o.canManageFacilities&&Array.isArray(o.facilityTypes)&&o.facilityTypes.length?`<select id="orgFacility_${esc(o.id)}" class="select">${o.facilityTypes.map(f=>`<option value="${esc(f.id)}">${esc(f.label)}</option>`).join('')}</select><button class="btn small primary" onclick="cmSetOrgFacility('${esc(o.id)}',false)">Set here</button><button class="btn small danger" onclick="cmSetOrgFacility('${esc(o.id)}',true)">Reset</button>`:''}${o.canManageNpcs?`<button class="btn small" onclick="cmOpenOrgNpcs('${esc(o.id)}')">NPCs</button>`:''}${o.canManageAlpr?`<button class="btn small" onclick="cmOpenOrgAlpr('${esc(o.id)}')">ALPR</button>`:''}${o.canManageBarricades?`<button class="btn small" onclick="cmOpenOrgBarricades('${esc(o.id)}')">Barricades</button>`:''}${o.canManageArmory?`<button class="btn small" onclick="cmOpenOrgArmory('${esc(o.id)}')">Equipment</button>`:''}${o.canManageCapabilities?`<button class="btn small" onclick="cmOpenOrgCapabilities('${esc(o.id)}')">Capabilities</button>`:''}${o.canManageFleet?`<button class="btn small" onclick="cmOpenOrgFleet('${esc(o.id)}')">Fleet</button>`:''}</div>`:'-'}</td>
          </tr>`).join('') || `<tr><td colspan="7">No organizations have registered yet.</td></tr>`}
        </tbody></table>
      </div>
    </div>
    <div class="card" style="margin-top:16px">
      <h3>Cross-Org Policy</h3>
      <p class="mini-label">Applies to every registered organization, not just a specific pair. Both default off (a character can belong to at most one organization, and cannot lead two at once).</p>
      <div class="form">
        <div class="field full"><label><input type="checkbox" id="orgPolicyMulti" ${policy.allowMultiOrgMembership ? 'checked' : ''} ${canManage ? '' : 'disabled'} /> Allow a player to be a member of more than one organization at the same time</label></div>
        <div class="field full"><label><input type="checkbox" id="orgPolicySameLeader" ${policy.allowSameLeaderAcrossOrgs ? 'checked' : ''} ${canManage ? '' : 'disabled'} /> Allow the same character to be leader of more than one organization at the same time</label></div>
        ${canManage ? `<button class="btn primary" onclick="cmSaveOrgPolicy()">Save policy</button>` : ''}
      </div>
    </div>`;
}

window.cmAssignOrgLeader = function(orgId) {
  const input = document.getElementById(`orgLeaderCid_${orgId}`);
  const characterId = input ? input.value : '';
  if (!characterId) return;
  action('orgsAssignLeader', { orgId, characterId });
};
window.cmRemoveOrgLeader = function(orgId) {
  if (confirm('Remove the current organization leader? Their organization membership will also be removed and the organization will remain without a leader.')) {
    action('orgsRemoveLeader', { orgId });
  }
};
window.cmSetOrgFacility = function(orgId, reset) {
  const select = document.getElementById(`orgFacility_${orgId}`);
  if (!select) return;
  if (reset && !confirm(`Reset the selected ${select.options[select.selectedIndex].text} location?`)) return;
  action('orgsSetFacility', { orgId, facilityType: select.value, reset: reset === true });
};
window.cmOpenOrgArmory = function(orgId) {
  action('orgsGetArmory', { orgId });
};
window.cmOpenOrgCapabilities = function(orgId) {
  action('orgsGetCapabilities', { orgId });
};
window.cmOpenOrgFleet = orgId => action('orgsGetFleet', {orgId});
window.cmOpenOrgNpcs = orgId => action('orgsGetNpcs', {orgId});
window.cmOpenOrgAlpr = orgId => action('orgsGetAlpr',{orgId});
window.cmOpenOrgBarricades = orgId => action('orgsGetBarricades',{orgId});
window.cmAddOrgBarricade = orgId => { const input=document.getElementById(`orgBarricadeModel_${orgId}`); action('orgsConfigureBarricade',{orgId,operation:'add',modelName:input&&input.value}); };
window.cmRemoveOrgBarricade = (orgId,catalogId) => { if(confirm('Remove this barricade model?')) action('orgsConfigureBarricade',{orgId,operation:'remove',catalogId}); };
window.cmAddOrgAlpr = orgId => action('orgsConfigureAlpr',{orgId,operation:'add'});
window.cmRemoveOrgAlpr = (orgId,cameraId) => { if(confirm('Remove this ALPR camera?')) action('orgsConfigureAlpr',{orgId,operation:'remove',cameraId}); };
window.cmBeginOrgFleet = (orgId,model) => action('orgsBeginFleetPlacement',{orgId,model});
window.cmSaveOrgFleet = function(orgId, model) { const k=`${orgId}_${model}`.replace(/[^a-zA-Z0-9_]/g,'_'); action('orgsConfigureFleet',{orgId,model,enabled:document.getElementById(`orgFleetEnabled_${k}`).checked,minTier:Number(document.getElementById(`orgFleetTier_${k}`).value||0)}); };
window.cmResetOrgFleet = (orgId,model) => { if(confirm('Reset this saved fleet location?')) action('orgsResetFleet',{orgId,model}); };
window.cmSaveOrgNpc = function(orgId,npcId,operation) { const k=`${orgId}_${npcId}`.replace(/[^a-zA-Z0-9_]/g,'_'); action('orgsConfigureNpc',{orgId,npcId,operation,enabled:document.getElementById(`orgNpcEnabled_${k}`).checked,model:document.getElementById(`orgNpcModel_${k}`).value,name:document.getElementById(`orgNpcName_${k}`).value,role:document.getElementById(`orgNpcRole_${k}`).value}); };
window.cmSaveOrgCapability = function(orgId, capability) {
  const key = `${orgId}_${capability}`.replace(/[^a-zA-Z0-9_]/g, '_');
  action('orgsConfigureCapability', {
    orgId, capability, enabled: document.getElementById(`orgCap_${key}`).checked,
  });
};
window.cmSaveOrgArmoryItem = function(orgId, itemName) {
  const key = `${orgId}_${itemName}`.replace(/[^a-zA-Z0-9_]/g, '_');
  action('orgsConfigureArmory', {
    orgId, itemName,
    enabled: document.getElementById(`orgArmEnabled_${key}`).checked,
    minTier: Number(document.getElementById(`orgArmTier_${key}`).value || 0),
    issueAmount: Number(document.getElementById(`orgArmIssue_${key}`).value || 1),
  });
};
window.cmSaveOrgPolicy = function() {
  action('orgsSavePolicy', {
    allowMultiOrgMembership: document.getElementById('orgPolicyMulti').checked,
    allowSameLeaderAcrossOrgs: document.getElementById('orgPolicySameLeader').checked,
  });
};

function adminsPage() {
  const admins = state.data.admins || [];
  return `
    <div class="grid cols-2">
      <div class="card">
        <h3>Add / Update Admin</h3>
        <div class="form">
          <div class="field full"><label>Character ID</label><input id="newAdminCharacterId" class="input" placeholder="Example: 12" /></div>
          <div class="field"><label>Name</label><input id="newAdminName" class="input" placeholder="Admin name" /></div>
          <div class="field"><label>Rank</label><select id="newAdminRank" class="select">${rankOptions('moderator')}</select></div>
          <button class="btn primary" onclick="cmAddAdmin()">Save Admin</button>
        </div>
      </div>
      <div class="card">
        <h3>Important</h3>
        <p class="mini-label">Admin access is saved by character ID only. Same account can have another character with no admin power. Staff still type /admin every session, then F11 opens this menu.</p>
      </div>
    </div>
    <div class="card" style="margin-top:16px">
      <h3>Saved Admins</h3>
      <div class="table-wrap">
        <table><thead><tr><th>Name</th><th>Character ID</th><th>Admin Key</th><th>Rank</th><th>Status</th><th>Actions</th></tr></thead><tbody>
          ${admins.map(a => `<tr>
            <td>${esc(a.name || '-')}</td>
            <td>${esc(a.characterId || '-')}</td>
            <td>${esc(a.identifier)}</td>
            <td><select class="select" style="min-height:34px" onchange="cmSetAdminRank('${esc(a.identifier)}', this.value)">${rankOptions(a.rank)}</select></td>
            <td><span class="badge ${a.active ? '' : 'off'}">${a.active ? 'Active' : 'Disabled'}</span></td>
            <td><button class="btn small danger" onclick="cmRemoveAdmin('${esc(a.identifier)}')">Disable</button></td>
          </tr>`).join('')}
        </tbody></table>
      </div>
    </div>`;
}

window.cmAddAdmin = function() {
  action('addAdmin', {
    characterId: document.getElementById('newAdminCharacterId').value,
    name: document.getElementById('newAdminName').value,
    rank: document.getElementById('newAdminRank').value
  });
};
window.cmRemoveAdmin = function(identifier) { if (confirm('Disable this admin?')) action('removeAdmin', { identifier }); };
window.cmSetAdminRank = function(identifier, rank) { action('setAdminRank', { identifier, rank }); };

function permissionLabel(permission) {
  return String(permission || '').replace(/\./g, ' / ');
}

function ensureRankEditor() {
  if (!state.rankEditor) state.rankEditor = { name: '', label: '', level: 20, permissions: [] };
  if (!state.rankEditor.name) {
    const first = (state.data.ranks || [])[0];
    if (first) {
      state.rankEditor = {
        name: first.name,
        label: first.label,
        level: Number(first.level || 0),
        permissions: Array.from(new Set(first.permissions || []))
      };
    }
  }
}

function ranksPage() {
  ensureRankEditor();
  const ranks = state.data.ranks || [];
  const allPerms = ['*'].concat(state.data.permissions || []);
  const assigned = Array.from(new Set(state.rankEditor.permissions || []));
  const available = allPerms.filter(p => !assigned.includes(p));

  const assignedHtml = assigned.map(p => `
    <button class="perm-pill assigned" draggable="true" ondragstart="cmDragPerm(event, '${esc(p)}')">
      <span>${esc(permissionLabel(p))}</span><b onclick="event.stopPropagation(); cmRemovePerm('${esc(p)}')">×</b>
    </button>`).join('');

  const availableHtml = available.map(p => `
    <button class="perm-pill" draggable="true" ondragstart="cmDragPerm(event, '${esc(p)}')" onclick="cmAddPerm('${esc(p)}')">
      ${esc(permissionLabel(p))}
    </button>`).join('');

  return `
    <div class="rank-layout">
      <div class="card rank-editor">
        <h3>Rank Permission Builder</h3>
        <div class="form">
          <div class="field"><label>Rank Name</label><input id="rankName" class="input" placeholder="senioradmin" value="${esc(state.rankEditor.name)}" /></div>
          <div class="field"><label>Label</label><input id="rankLabel" class="input" placeholder="Senior Admin" value="${esc(state.rankEditor.label)}" /></div>
          <div class="field"><label>Level</label><input id="rankLevel" class="input" type="number" value="${esc(state.rankEditor.level)}" /></div>
          <div class="actions"><button class="btn primary" onclick="cmSaveRank()">Save Rank</button><button class="btn danger" onclick="cmDeleteRank()">Delete Rank</button></div>
        </div>
        <div class="permission-builder">
          <div class="perm-box" ondragover="event.preventDefault()" ondrop="cmDropPerm(event, true)">
            <div class="perm-box-head"><strong>Assigned permissions</strong><small>Drag here to add · press × to remove</small></div>
            <div class="perm-list assigned-list">${assignedHtml || '<span class="empty-inline">No permissions assigned</span>'}</div>
          </div>
          <div class="perm-box" ondragover="event.preventDefault()" ondrop="cmDropPerm(event, false)">
            <div class="perm-box-head"><strong>Available permissions</strong><small>Click or drag into assigned</small></div>
            <div class="perm-list">${availableHtml || '<span class="empty-inline">All permissions assigned</span>'}</div>
          </div>
        </div>
      </div>
      <div class="card rank-list-card">
        <h3>Ranks</h3>
        <div class="rank-list">
          ${ranks.map(r => `<button class="rank-row ${state.rankEditor.name === r.name ? 'active' : ''}" onclick="cmLoadRank('${esc(r.name)}')">
            <strong>${esc(r.label)}</strong><small>${esc(r.name)} · Level ${esc(r.level)} · ${(r.permissions || []).length} permissions</small>
          </button>`).join('')}
        </div>
      </div>
    </div>`;
}

window.cmLoadRank = function(name) {
  const r = (state.data.ranks || []).find(x => x.name === name);
  if (!r) return;
  state.rankEditor = {
    name: r.name,
    label: r.label,
    level: Number(r.level || 0),
    permissions: Array.from(new Set(r.permissions || []))
  };
  render();
};

window.cmDragPerm = function(event, permission) {
  event.dataTransfer.setData('text/plain', permission);
  event.dataTransfer.effectAllowed = 'move';
};

window.cmDropPerm = function(event, assign) {
  event.preventDefault();
  const permission = event.dataTransfer.getData('text/plain');
  if (!permission) return;
  if (assign) cmAddPerm(permission);
  else cmRemovePerm(permission);
};

window.cmAddPerm = function(permission) {
  permission = String(permission || '');
  if (!permission) return;
  const set = new Set(state.rankEditor.permissions || []);
  set.add(permission);
  state.rankEditor.permissions = Array.from(set);
  render();
};

window.cmRemovePerm = function(permission) {
  state.rankEditor.permissions = (state.rankEditor.permissions || []).filter(p => p !== permission);
  render();
};

window.cmSaveRank = function() {
  const nameEl = document.getElementById('rankName');
  const labelEl = document.getElementById('rankLabel');
  const levelEl = document.getElementById('rankLevel');
  state.rankEditor.name = nameEl ? nameEl.value : state.rankEditor.name;
  state.rankEditor.label = labelEl ? labelEl.value : state.rankEditor.label;
  state.rankEditor.level = Number(levelEl ? levelEl.value : state.rankEditor.level || 0);
  action('saveRank', {
    name: state.rankEditor.name,
    label: state.rankEditor.label,
    level: state.rankEditor.level,
    permissions: Array.from(new Set(state.rankEditor.permissions || []))
  });
};

window.cmDeleteRank = function() {
  const nameEl = document.getElementById('rankName');
  const name = nameEl ? nameEl.value : state.rankEditor.name;
  if (!name) return;
  if (confirm(`Delete rank ${name}?`)) action('deleteRank', { name });
};

function logsPage() {
  const rawLogs = state.detail && state.detail.type === 'logs' ? state.detail.data.logs : (state.data.logs || []);
  const categories = (state.detail && state.detail.data && state.detail.data.categories) || state.data.logCategories || [];
  const logs = state.logFilter === 'all' ? rawLogs : rawLogs.filter(l => (l.category || 'system') === state.logFilter);
  const catButtons = [{ id: 'all', label: 'All' }].concat(categories).map(c =>
    `<button class="btn small ${state.logFilter === c.id ? 'primary' : ''}" onclick="cmLogFilter('${esc(c.id)}')">${esc(c.label || c.id)}</button>`
  ).join('');
  return `
    <div class="card">
      <div class="actions" style="justify-content:space-between; margin-bottom:12px">
        <h3 style="margin:0">Role-Based Audit Logs</h3>
        <button class="btn primary" onclick="action('viewLogs')">Load More</button>
      </div>
      <div class="actions log-filters">${catButtons}</div>
      <div class="table-wrap">
        <table><thead><tr><th>ID</th><th>Category</th><th>Admin</th><th>Action</th><th>Target</th><th>Details</th><th>Time</th></tr></thead><tbody>
          ${logs.map(l => `<tr><td>${esc(l.id)}</td><td><span class="badge">${esc(l.category || 'system')}</span></td><td>${esc(l.adminName || l.identifier || '-')}<br><small>${esc(l.source || '')}</small></td><td><span class="badge">${esc(l.action)}</span></td><td>${esc(l.targetName || '-')}<br><small>${esc(l.targetIdentifier || '')}</small></td><td><div class="json">${esc(JSON.stringify(l.details || {}, null, 2))}</div></td><td>${esc(l.createdAt || '-')}</td></tr>`).join('') || '<tr><td colspan="7" class="empty-cell">No logs available for your role/filter.</td></tr>'}
        </tbody></table>
      </div>
    </div>`;
}

window.cmLogFilter = function(category) {
  state.logFilter = category || 'all';
  render();
};

function tableFromRows(rows) {
  rows = rows || [];
  if (!rows.length) return '<div class="empty">No rows found from this bridge query.</div>';
  const keys = Array.from(rows.reduce((set, row) => { Object.keys(row || {}).slice(0, 12).forEach(k => set.add(k)); return set; }, new Set()));
  return `<div class="table-wrap"><table><thead><tr>${keys.map(k => `<th>${esc(k)}</th>`).join('')}<th>Raw</th></tr></thead><tbody>
    ${rows.map(row => `<tr>${keys.map(k => `<td>${esc(shortValue(row[k]))}</td>`).join('')}<td><div class="json">${esc(JSON.stringify(row, null, 2))}</div></td></tr>`).join('')}
  </tbody></table></div>`;
}

function shortValue(v) {
  if (v === null || v === undefined) return '';
  if (typeof v === 'object') return JSON.stringify(v).slice(0, 120);
  const s = String(v);
  return s.length > 120 ? s.slice(0, 120) + '…' : s;
}

function detailBlock() {
  if (!state.detail) return '';
  const d = state.detail.data || {};
  if (state.detail.type === 'inventory') {
    return `<div class="card" style="margin-top:16px"><h3>Inventory Result</h3>${bridgeHeader(d.result)}${tableFromRows(d.result && d.result.rows)}</div>`;
  }
  if (state.detail.type === 'vehicles') {
    return `<div class="card" style="margin-top:16px"><h3>Vehicle Result</h3>${bridgeHeader(d.result)}${tableFromRows(d.result && d.result.rows)}</div>`;
  }
  if (state.detail.type === 'vehicleInventory') {
    return `<div class="card" style="margin-top:16px"><h3>Vehicle Inventory: ${esc(d.plate)}</h3>${bridgeHeader(d.result)}${tableFromRows(d.result && d.result.rows)}</div>`;
  }
  return '';
}

function bridgeHeader(result) {
  result = result || {};
  return `<div class="detail-grid">
    <div class="kv"><small>Source</small><strong>${esc(result.source || 'No matching table')}</strong></div>
    <div class="kv"><small>Rows</small><strong>${esc((result.rows || []).length)}</strong></div>
  </div>`;
}

function render() {
  const data = state.data;
  serverName.textContent = data.server && data.server.name ? data.server.name : 'CM Server';
  adminName.textContent = data.me && data.me.name ? data.me.name : '-';
  adminRank.textContent = data.me ? `${data.me.rankLabel || data.me.rank || '-'} · Level ${data.me.level || 0}` : '-';

  renderNav();
  const current = tabs.find(t => t.id === state.tab) || tabs[0];
  pageTitle.textContent = current.label;
  pageKicker.textContent = current.hint;

  if (state.tab === 'dashboard') page.innerHTML = dashboard();
  else if (state.tab === 'players') page.innerHTML = playersPage();
  else if (state.tab === 'inventory') page.innerHTML = inventoryPage();
  else if (state.tab === 'vehicles') page.innerHTML = vehiclesPage();
  else if (state.tab === 'orgs') page.innerHTML = orgsPage();
  else if (state.tab === 'gangs') { page.innerHTML = gangsPage(); setTimeout(renderGangWeaponCatalog, 0); }
  else if (state.tab === 'admins') page.innerHTML = adminsPage();
  else if (state.tab === 'ranks') page.innerHTML = ranksPage();
  else if (state.tab === 'offline') page.innerHTML = offlinePage();
  else if (state.tab === 'map') { page.innerHTML = mapPage(); setTimeout(initMap, 0); }
  else if (state.tab === 'developer') page.innerHTML = developerPage();
  else if (state.tab === 'logs') page.innerHTML = logsPage();
  else page.innerHTML = '<div class="empty">Page not found</div>';
}

window.addEventListener('message', (event) => {
  const msg = event.data || {};
  if (msg.action === 'open') {
    state.open = true;
    state.data = msg.data || state.data;
    state.detail = null;
    app.classList.remove('hidden');
    render();
  }
  if (msg.action === 'update') {
    state.data = msg.data || state.data;
    render();
  }
  if (msg.action === 'mapData') {
    state.map.players = (msg.data && msg.data.players) || [];
    state.map.vehicles = (msg.data && msg.data.vehicles) || [];
    if (state.tab === 'map') scheduleMapDraw();
    return;
  }
  if (msg.action === 'detailResult') {
    state.detail = msg.data || null;
    if (state.detail && state.detail.type === 'offlineSearch') {
      state.offline.results = (state.detail.data && state.detail.data.results) || [];
      state.detail = null;
      state.tab = 'offline';
      render();
      return;
    }
    if (state.detail && state.detail.type === 'orgArmory') {
      const result = state.detail.data || {};
      const orgId = state.detail.orgId;
      const items = result.items || [];
      state.detail = null;
      if (result.ok !== true) return;
      const card = document.createElement('div');
      card.className = 'card';
      card.innerHTML = `<h3>${esc(orgId)} Armory Equipment</h3><div class="table-wrap"><table><thead><tr><th>Equipment</th><th>Type</th><th>Enabled</th><th>Minimum tier</th><th>Issue amount</th><th></th></tr></thead><tbody>${items.map(item => { const key=`${orgId}_${item.itemName}`.replace(/[^a-zA-Z0-9_]/g,'_'); return `<tr><td>${esc(item.label)}</td><td>${esc(item.itemType)}</td><td><input id="orgArmEnabled_${key}" type="checkbox" ${item.enabled?'checked':''}></td><td><input id="orgArmTier_${key}" class="input" type="number" min="0" value="${Number(item.minTier||0)}"></td><td><input id="orgArmIssue_${key}" class="input" type="number" min="1" value="${Number(item.issueAmount||1)}"></td><td><button class="btn small primary" onclick="cmSaveOrgArmoryItem('${esc(orgId)}','${esc(item.itemName)}')">Save</button></td></tr>`; }).join('')}</tbody></table></div>`;
      page.prepend(card);
      return;
    }
    if (state.detail && state.detail.type === 'orgCapabilities') {
      const result = state.detail.data || {};
      const orgId = state.detail.orgId;
      const items = result.items || [];
      state.detail = null;
      if (result.ok !== true) return;
      const card = document.createElement('div');
      card.className = 'card';
      card.innerHTML = `<h3>${esc(orgId)} Capabilities</h3><p class="mini-label">Capability enables the organization feature; rank permissions still gate each member.</p><div class="table-wrap"><table><thead><tr><th>Capability</th><th>Enabled</th><th></th></tr></thead><tbody>${items.map(item => { const key=`${orgId}_${item.id}`.replace(/[^a-zA-Z0-9_]/g,'_'); return `<tr><td>${esc(item.id)}</td><td><input id="orgCap_${key}" type="checkbox" ${item.enabled?'checked':''}></td><td><button class="btn small primary" onclick="cmSaveOrgCapability('${esc(orgId)}','${esc(item.id)}')">Save</button></td></tr>`; }).join('')}</tbody></table></div>`;
      page.prepend(card);
      return;
    }
    if (state.detail && state.detail.type === 'orgFleet') {
      const result=state.detail.data||{},orgId=state.detail.orgId,items=result.vehicles||[]; state.detail=null;
      if(result.ok!==true)return; const card=document.createElement('div'); card.className='card';
      card.innerHTML=`<h3>${esc(orgId)} Fleet</h3><div class="table-wrap"><table><thead><tr><th>Vehicle</th><th>Configured</th><th>Enabled</th><th>Tier</th><th></th></tr></thead><tbody>${items.map(v=>{const k=`${orgId}_${v.model}`.replace(/[^a-zA-Z0-9_]/g,'_');return `<tr><td>${esc(v.label||v.model)}</td><td>${v.configured?'Yes':'No'}</td><td><input id="orgFleetEnabled_${k}" type="checkbox" ${v.enabled?'checked':''}></td><td><input id="orgFleetTier_${k}" class="input" type="number" min="0" value="${Number(v.minTier||0)}"></td><td><button class="btn small primary" onclick="cmSaveOrgFleet('${esc(orgId)}','${esc(v.model)}')">Save</button><button class="btn small" onclick="cmBeginOrgFleet('${esc(orgId)}','${esc(v.model)}')">Set / update location</button><button class="btn small danger" onclick="cmResetOrgFleet('${esc(orgId)}','${esc(v.model)}')">Reset location</button></td></tr>`}).join('')}</tbody></table></div>`; page.prepend(card); return;
    }
    if (state.detail && state.detail.type === 'orgNpcs') {
      const result=state.detail.data||{},orgId=state.detail.orgId,items=result.items||[]; state.detail=null;
      if(result.ok!==true)return; const card=document.createElement('div'); card.className='card';
      card.innerHTML=`<h3>${esc(orgId)} Managed NPCs</h3><p class="mini-label">Location is captured from your current server-side position and heading. Reset restores config.lua defaults.</p><div class="table-wrap"><table><thead><tr><th>NPC</th><th>Enabled</th><th>Model</th><th>Name</th><th>Role</th><th>Location</th><th></th></tr></thead><tbody>${items.map(n=>{const k=`${orgId}_${n.id}`.replace(/[^a-zA-Z0-9_]/g,'_');return `<tr><td>${esc(n.label||n.id)}</td><td><input id="orgNpcEnabled_${k}" type="checkbox" ${n.enabled?'checked':''}></td><td><input id="orgNpcModel_${k}" class="input" value="${esc(n.model||'')}"></td><td><input id="orgNpcName_${k}" class="input" value="${esc(n.name||'')}"></td><td><input id="orgNpcRole_${k}" class="input" value="${esc(n.role||'')}"></td><td>${n.configured?'Custom':'Default'}</td><td><button class="btn small primary" onclick="cmSaveOrgNpc('${esc(orgId)}','${esc(n.id)}','save')">Save</button><button class="btn small" onclick="cmSaveOrgNpc('${esc(orgId)}','${esc(n.id)}','set_location')">Set here</button><button class="btn small danger" onclick="cmSaveOrgNpc('${esc(orgId)}','${esc(n.id)}','reset')">Reset</button></td></tr>`}).join('')}</tbody></table></div>`; page.prepend(card); return;
    }
    if (state.detail && state.detail.type === 'orgAlpr') {
      const result=state.detail.data||{},orgId=state.detail.orgId,items=result.items||[]; state.detail=null;
      if(result.ok!==true)return; const card=document.createElement('div'); card.className='card';
      card.innerHTML=`<h3>${esc(orgId)} ALPR Cameras</h3><button class="btn primary" onclick="cmAddOrgAlpr('${esc(orgId)}')">Add camera at current location</button><div class="table-wrap"><table><thead><tr><th>ID</th><th>Label</th><th>Coordinates</th><th></th></tr></thead><tbody>${items.map(c=>`<tr><td>${Number(c.id||0)}</td><td>${esc(c.label||'ALPR Camera')}</td><td>${Number(c.x||0).toFixed(2)}, ${Number(c.y||0).toFixed(2)}, ${Number(c.z||0).toFixed(2)}</td><td><button class="btn small danger" onclick="cmRemoveOrgAlpr('${esc(orgId)}',${Number(c.id||0)})">Remove</button></td></tr>`).join('')}</tbody></table></div>`; page.prepend(card); return;
    }
    if (state.detail && state.detail.type === 'orgBarricades') {
      const result=state.detail.data||{},orgId=state.detail.orgId,items=result.items||[]; state.detail=null;
      if(result.ok!==true)return; const card=document.createElement('div'); card.className='card';
      card.innerHTML=`<h3>${esc(orgId)} Barricade Catalog</h3><div class="form"><input id="orgBarricadeModel_${esc(orgId)}" class="input" placeholder="prop_barrier_work05"><button class="btn primary" onclick="cmAddOrgBarricade('${esc(orgId)}')">Add model</button></div><div class="table-wrap"><table><thead><tr><th>ID</th><th>Model</th><th></th></tr></thead><tbody>${items.map(item=>`<tr><td>${Number(item.id||0)}</td><td>${esc(item.modelName||'')}</td><td><button class="btn small danger" onclick="cmRemoveOrgBarricade('${esc(orgId)}',${Number(item.id||0)})">Remove</button></td></tr>`).join('')}</tbody></table></div>`; page.prepend(card); return;
    }
    if (state.detail && state.detail.type === 'logs') state.tab = 'logs';
    if (state.detail && state.detail.type === 'inventory') state.tab = 'inventory';
    if (state.detail && (state.detail.type === 'vehicles' || state.detail.type === 'vehicleInventory')) state.tab = 'vehicles';
    render();
  }
  if (msg.action === 'close') {
    state.open = false;
    app.classList.add('hidden');
    stopMapTimer();
  }
});


// ---------------------------------------------------------------------------
// Offline characters
// ---------------------------------------------------------------------------
function offlinePage() {
  const rows = state.offline.results.map(r => `
    <tr>
      <td><strong>${esc(r.name)}</strong><small style="display:block;opacity:.6">${esc(r.dob || '')}</small></td>
      <td>${esc(r.characterId)}</td>
      <td>${r.cash !== undefined && r.cash !== null ? '$' + Number(r.cash).toLocaleString() : '-'}<small style="display:block;opacity:.6">${r.bank !== undefined && r.bank !== null ? 'Bank $' + Number(r.bank).toLocaleString() : ''}</small></td>
      <td class="actions">
        ${hasPerm('inventory.view') ? `<button class="btn small" onclick="cmOffline('offlineInventory', '${esc(r.characterId)}', '')">Inventory</button>` : ''}
        ${hasPerm('vehicles.view') ? `<button class="btn small" onclick="cmOffline('offlineVehicles', '${esc(r.characterId)}', '')">Vehicles</button>` : ''}
      </td>
    </tr>`).join('');

  return `
    <div class="card">
      <h3>Offline Character Search</h3>
      <div class="row">
        <input id="offlineQuery" placeholder="Character ID or name..." value="${esc(state.offline.query)}" />
        <button class="btn" onclick="cmOfflineSearch()">Search</button>
      </div>
      <table class="table">
        <thead><tr><th>Name</th><th>Char ID</th><th>Money</th><th></th></tr></thead>
        <tbody>${rows || '<tr><td colspan="4" class="empty">Search the characters database. Works while the player is offline.</td></tr>'}</tbody>
      </table>
    </div>`;
}

function cmOfflineSearch() {
  const el = document.getElementById('offlineQuery');
  state.offline.query = el ? el.value : '';
  sendAction('offlineSearch', { query: state.offline.query });
}

function cmOffline(action, characterId, identifier) {
  sendAction(action, { characterId, identifier });
}

// ---------------------------------------------------------------------------
// Live map (calibrated GTA atlas: pan = drag, zoom = wheel, click = select).
// Uses the same stitched 6-tile atlas style as cm-climatime, but with admin
// selection/action panels for players and vehicles.
// ---------------------------------------------------------------------------
const MAP_DEFAULT_BOUNDS = { minX: -4000, maxX: 4500, minY: -4300, maxY: 8000 };
let mapImg = null, mapImgTried = false, mapDrawQueued = false;

function cleanBounds(input) {
  const b = input || {};
  const out = {
    minX: Number(b.minX ?? MAP_DEFAULT_BOUNDS.minX),
    maxX: Number(b.maxX ?? MAP_DEFAULT_BOUNDS.maxX),
    minY: Number(b.minY ?? MAP_DEFAULT_BOUNDS.minY),
    maxY: Number(b.maxY ?? MAP_DEFAULT_BOUNDS.maxY),
  };
  if (!Number.isFinite(out.minX)) out.minX = MAP_DEFAULT_BOUNDS.minX;
  if (!Number.isFinite(out.maxX)) out.maxX = MAP_DEFAULT_BOUNDS.maxX;
  if (!Number.isFinite(out.minY)) out.minY = MAP_DEFAULT_BOUNDS.minY;
  if (!Number.isFinite(out.maxY)) out.maxY = MAP_DEFAULT_BOUNDS.maxY;
  if (out.maxX <= out.minX) out.maxX = out.minX + 1000;
  if (out.maxY <= out.minY) out.maxY = out.minY + 1000;
  return out;
}

function serverMapBounds() {
  return cleanBounds((state.data && state.data.server && state.data.server.mapBounds) || MAP_DEFAULT_BOUNDS);
}

function mapBounds() {
  if (state.map.calibrating && state.map.calibration && state.map.calibration.bounds) {
    return cleanBounds(state.map.calibration.bounds);
  }
  return serverMapBounds();
}

function canCalibrateMap() {
  const srv = (state.data && state.data.server) || {};
  return srv.mapAllowUiSave !== false && (hasPerm('map.calibrate') || hasPerm('ranks.manage') || hasPerm('dev.tools'));
}

function mapPage() {
  return `
    <div class="map-layout">
      <div class="card map-card">
        <div class="zoneMapHeader admin-map-head">
          <div>
            <span class="mapTag">GTA Live Staff Map</span>
            <p class="muted">Calibrated stitched 6-tile GTA atlas. Drag to pan, wheel to zoom, click player/vehicle blips for actions.</p>
          </div>
          <strong id="mapCoordsHint">X 0 Y 0</strong>
        </div>
        <div class="zoneMapToolbar admin-map-toolbar">
          <button class="btn small ghost" type="button" onclick="cmMapZoom(1)">＋ Zoom</button>
          <button class="btn small ghost" type="button" onclick="cmMapZoom(-1)">－ Zoom</button>
          <button class="btn small ghost" type="button" onclick="cmMapFocusSelf()">⌖ Focus Self</button>
          <button class="btn small ghost" type="button" onclick="cmMapClearSelection()">Clear Select</button>
          ${canCalibrateMap() ? `<button class="btn small warn" type="button" onclick="cmMapToggleCalibration()">${state.map.calibrating ? 'Close Calibration' : 'Calibrate Map'}</button>` : ''}
          ${(hasPerm('gps.teleport') || hasPerm('teleport') || hasPerm('players.teleport')) ? `<button class="btn small primary" type="button" onclick="action('gpsTeleport')">GPS TP</button>` : ''}
          <label class="check map-toggle"><input type="checkbox" id="mapVehToggle" ${state.map.showVehicles ? 'checked' : ''} onchange="cmMapVehToggle(this.checked)" /> Vehicles</label>
          <label class="check map-toggle"><input type="checkbox" id="mapAdminToggle" ${state.map.showAdmins ? 'checked' : ''} onchange="cmMapAdminToggle(this.checked)" /> Admins</label>
        </div>
        <div class="admin-map-wrap"><canvas id="mapCanvas"></canvas></div>
        <div class="map-legend"><span class="dot player"></span> Player <span class="dot admin"></span> Logged-in admin <span class="dot self"></span> You <span class="dot vehicle"></span> Vehicle <span class="dot selected"></span> Selected</div>
      </div>
      <div id="mapSelection" class="map-selection">${mapSidePanel()}</div>
    </div>`;
}

function mapSidePanel() {
  return `${mapCalibrationPanel()}${mapSelectionPanel()}`;
}

function mapCalibrationPanel() {
  if (!state.map.calibrating) return '';
  const b = mapBounds();
  const source = esc(((state.data && state.data.server && state.data.server.mapBoundsSource) || 'config'));
  const configText = `Config.Map.Bounds = {\n    minX = ${Math.round(b.minX)},\n    maxX = ${Math.round(b.maxX)},\n    minY = ${Math.round(b.minY)},\n    maxY = ${Math.round(b.maxY)}\n}`;
  return `<div class="card map-side-card map-cal-card">
    <h3>Map Calibration <span class="badge">${source}</span></h3>
    <p class="muted tiny">Tune the atlas once, preview live, then save. Saved values load every restart from <code>data/map_bounds.json</code>.</p>
    <div class="bounds-grid">
      ${['minX','maxX','minY','maxY'].map(k => `<label><span>${k}</span><input id="cal_${k}" type="number" value="${Math.round(b[k])}" onchange="cmMapCalSet('${k}', this.value)" /></label>`).join('')}
    </div>
    <div class="cal-nudge-grid">
      <button class="btn xsmall" onclick="cmMapCalShift('x', -100)">Map Left</button>
      <button class="btn xsmall" onclick="cmMapCalShift('x', 100)">Map Right</button>
      <button class="btn xsmall" onclick="cmMapCalShift('y', 100)">Map Up</button>
      <button class="btn xsmall" onclick="cmMapCalShift('y', -100)">Map Down</button>
      <button class="btn xsmall ghost" onclick="cmMapCalScale('x', 100)">Wider X</button>
      <button class="btn xsmall ghost" onclick="cmMapCalScale('x', -100)">Narrower X</button>
      <button class="btn xsmall ghost" onclick="cmMapCalScale('y', 100)">Taller Y</button>
      <button class="btn xsmall ghost" onclick="cmMapCalScale('y', -100)">Shorter Y</button>
    </div>
    <textarea id="mapBoundsConfig" class="config-copy" readonly>${esc(configText)}</textarea>
    <div class="actions">
      <button class="btn small primary" onclick="cmMapCalSave()">Save For Every Restart</button>
      <button class="btn small" onclick="cmMapCalCopy()">Copy Config</button>
      <button class="btn small ghost" onclick="cmMapCalReset()">Reset Config Bounds</button>
    </div>
  </div>`;
}

function mapSelectionPanel() {
  const sel = state.map.selected;
  if (!sel) {
    return `<div class="card map-side-card"><h3>Map Selection</h3><p class="empty">Click a player or vehicle blip on the map.</p><p class="muted tiny">Player actions are permission based. Vehicle actions use network entity/plate when available.</p></div>`;
  }
  if (sel.type === 'world') {
    const w = sel.data || {};
    return `<div class="card map-side-card"><h3>Map Point</h3>
      <div class="detail-grid compact"><div class="kv"><small>X</small><strong>${Math.round(w.x || 0)}</strong></div><div class="kv"><small>Y</small><strong>${Math.round(w.y || 0)}</strong></div><div class="kv"><small>Z</small><strong>${Math.round(w.z || 40)}</strong></div></div>
      <div class="actions">${hasPerm('map.teleport') || hasPerm('gps.teleport') || hasPerm('players.teleport') || hasPerm('teleport') ? `<button class="btn small primary" onclick="cmMapTeleport(${Number(w.x || 0)}, ${Number(w.y || 0)}, ${Number(w.z || 40)})">Teleport Here</button>` : ''}</div>
    </div>`;
  }
  if (sel.type === 'vehicle') {
    const v = sel.data || {};
    const plate = esc(v.plate || 'UNKNOWN');
    return `<div class="card map-side-card selected-vehicle"><h3>Vehicle <span class="badge">${plate}</span></h3>
      <div class="detail-grid compact">
        <div class="kv"><small>Plate</small><strong>${plate}</strong></div>
        <div class="kv"><small>Model Hash</small><strong>${esc(v.model || '-')}</strong></div>
        <div class="kv"><small>Net ID</small><strong>${esc(v.netId || '-')}</strong></div>
        <div class="kv"><small>Coords</small><strong>${esc(formatCoords(v))}</strong></div>
      </div>
      <div class="actions">
        ${(hasPerm('map.teleport') || hasPerm('players.teleport') || hasPerm('teleport') || hasPerm('vehicles.view')) ? `<button class="btn small primary" onclick="cmMapVehicleAction('${escJs(v.netId || 0)}','${escJs(v.plate || '')}','goto')">Go To Vehicle</button>` : ''}
        ${hasPerm('vehicles.manage') ? `<button class="btn small success" onclick="cmMapVehicleAction('${escJs(v.netId || 0)}','${escJs(v.plate || '')}','repair')">Repair</button><button class="btn small danger" onclick="cmMapVehicleAction('${escJs(v.netId || 0)}','${escJs(v.plate || '')}','delete')">Delete</button>` : ''}
      </div>
    </div>`;
  }
  const p = sel.data || {};
  return `<div class="card map-side-card selected-player"><h3>${esc(p.name || 'Player')} <span class="badge">Char ${esc(p.characterId || '-')}</span></h3>
    <div class="detail-grid compact">
      <div class="kv"><small>Status</small><strong>${p.self ? 'You' : (p.adminMode ? 'Admin' : 'Player')}</strong></div>
      <div class="kv"><small>Character ID</small><strong>${esc(p.characterId || '-')}</strong></div>
      <div class="kv"><small>Character name</small><strong>${esc(p.characterName || '-')}</strong></div>
      <div class="kv"><small>Coords</small><strong>${esc(formatCoords(p))}</strong></div>
    </div>
    <div class="actions">
      ${hasPerm('players.view') ? `<button class="btn small" onclick="cmMapInspectPlayer(${Number(p.id || 0)})">Inspect</button>` : ''}
      ${hasPerm('players.teleport') ? `<button class="btn small primary" onclick="cmPlayerAction(${Number(p.id || 0)}, 'goto')">Go To</button><button class="btn small primary" onclick="cmPlayerAction(${Number(p.id || 0)}, 'bring')">Bring</button>` : ''}
      ${hasPerm('players.freeze') ? `<button class="btn small" onclick="cmPlayerAction(${Number(p.id || 0)}, 'freeze')">Freeze</button><button class="btn small" onclick="cmPlayerAction(${Number(p.id || 0)}, 'unfreeze')">Unfreeze</button>` : ''}
      ${hasPerm('tools.heal') ? `<button class="btn small success" onclick="cmPlayerAction(${Number(p.id || 0)}, 'heal')">Heal</button><button class="btn small success" onclick="cmPlayerAction(${Number(p.id || 0)}, 'armor')">Armor</button>` : ''}
      ${hasPerm('inventory.view') ? `<button class="btn small" onclick="cmViewInventory(${Number(p.id || 0)})">Inventory</button>` : ''}
      ${hasPerm('vehicles.view') ? `<button class="btn small" onclick="cmViewVehicles(${Number(p.id || 0)})">Cars</button>` : ''}
      ${hasPerm('players.kick') ? `<button class="btn small danger" onclick="cmKick(${Number(p.id || 0)})">Kick</button>` : ''}
    </div>
  </div>`;
}

function escJs(value) {
  return String(value === null || value === undefined ? '' : value).replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\n/g, ' ');
}

function updateMapSelection() {
  const el = document.getElementById('mapSelection');
  if (el) el.innerHTML = mapSidePanel();
  scheduleMapDraw();
}

function cmMapVehToggle(v) { state.map.showVehicles = v; requestMapData(); }
function cmMapAdminToggle(v) { state.map.showAdmins = v; scheduleMapDraw(); }
function cmMapZoom(dir) {
  const cam = state.map.cam;
  cam.zoom = Math.min(1.65, Math.max(0.035, cam.zoom * (dir > 0 ? 1.22 : 0.82)));
  scheduleMapDraw();
}
function cmMapFocusSelf() {
  const self = (state.map.players || []).find(p => p.self);
  if (self) {
    state.map.cam.x = Number(self.x) || 0;
    state.map.cam.y = Number(self.y) || 0;
    state.map.selected = { type: 'player', data: self };
    updateMapSelection();
  } else {
    requestMapData();
  }
}
function cmMapClearSelection() { state.map.selected = null; updateMapSelection(); }
function ensureMapCalibration() {
  if (!state.map.calibration || !state.map.calibration.bounds) {
    state.map.calibration = { bounds: cleanBounds(serverMapBounds()) };
  }
  return state.map.calibration.bounds;
}
function cmMapToggleCalibration() {
  state.map.calibrating = !state.map.calibrating;
  if (state.map.calibrating) ensureMapCalibration();
  render();
}
function cmMapCalSet(key, value) {
  const b = ensureMapCalibration();
  if (!Object.prototype.hasOwnProperty.call(b, key)) return;
  const n = Number(value);
  if (!Number.isFinite(n)) return;
  b[key] = Math.round(n);
  state.map.calibration.bounds = cleanBounds(b);
  updateMapSelection();
}
function cmMapCalShift(axis, amount) {
  const b = ensureMapCalibration();
  amount = Number(amount || 0);
  if (axis === 'x') { b.minX += amount; b.maxX += amount; }
  if (axis === 'y') { b.minY += amount; b.maxY += amount; }
  state.map.calibration.bounds = cleanBounds(b);
  updateMapSelection();
}
function cmMapCalScale(axis, amount) {
  const b = ensureMapCalibration();
  amount = Number(amount || 0);
  if (axis === 'x') { b.minX -= amount; b.maxX += amount; }
  if (axis === 'y') { b.minY -= amount; b.maxY += amount; }
  state.map.calibration.bounds = cleanBounds(b);
  updateMapSelection();
}
function cmMapCalSave() {
  const b = cleanBounds(ensureMapCalibration());
  state.data.server = state.data.server || {};
  state.data.server.mapBounds = b;
  state.data.server.mapBoundsSource = 'saved';
  sendAction('saveMapBounds', { bounds: b });
  updateMapSelection();
}
function cmMapCalReset() {
  const b = cleanBounds((state.data && state.data.server && state.data.server.mapConfigBounds) || MAP_DEFAULT_BOUNDS);
  state.map.calibration = { bounds: b };
  state.data.server = state.data.server || {};
  state.data.server.mapBounds = b;
  sendAction('resetMapBounds', {});
  updateMapSelection();
}
function cmMapCalCopy() {
  const ta = document.getElementById('mapBoundsConfig');
  if (!ta) return;
  ta.focus();
  ta.select();
  try { document.execCommand('copy'); } catch (e) {}
}
function cmMapInspectPlayer(id) {
  state.selectedPlayer = Number(id || 0);
  state.tab = 'players';
  stopMapTimer();
  sendAction('refresh', {});
  render();
}
function cmMapTeleport(x, y, z) { sendAction('mapTeleportToCoords', { x, y, z }); }
function cmMapVehicleAction(netId, plate, vehicleAction) { sendAction('vehicleMapAction', { netId: Number(netId || 0), plate: plate || '', vehicleAction }); }

function requestMapData() {
  sendAction('mapData', { vehicles: state.map.showVehicles, admins: state.map.showAdmins });
}

function stopMapTimer() {
  if (state.map.timer) { clearInterval(state.map.timer); state.map.timer = null; }
}

function initMap() {
  const canvas = document.getElementById('mapCanvas');
  if (!canvas) return;

  if (!mapImgTried) {
    mapImgTried = true;
    const img = new Image();
    img.onload = () => { mapImg = img; scheduleMapDraw(); };
    img.onerror = () => { mapImg = null; scheduleMapDraw(); };
    img.src = 'assets/gta-map-local.png';
  }

  resizeMapCanvas(canvas);
  if (!state.map.resizeBound) {
    state.map.resizeBound = true;
    window.addEventListener('resize', () => {
      if (state.tab === 'map' && state.open) {
        const c = document.getElementById('mapCanvas');
        if (c) resizeMapCanvas(c);
        scheduleMapDraw();
      }
    }, { passive: true });
  }

  canvas.onmousedown = (e) => { state.map.drag = { x: e.clientX, y: e.clientY }; state.map.moved = false; };
  window.onmouseup = () => { state.map.drag = null; };
  canvas.onmousemove = (e) => {
    const rect = canvas.getBoundingClientRect();
    const mx = e.clientX - rect.left, my = e.clientY - rect.top;
    const w = screenToWorld(canvas, mx, my);
    state.map.cursor = w;
    const hint = document.getElementById('mapCoordsHint');
    if (hint) hint.textContent = `X ${Math.round(w.x)} Y ${Math.round(w.y)}`;

    if (!state.map.drag) return;
    const cam = state.map.cam;
    const dx = e.clientX - state.map.drag.x;
    const dy = e.clientY - state.map.drag.y;
    if (Math.abs(dx) + Math.abs(dy) > 3) state.map.moved = true;
    cam.x -= dx / cam.zoom;
    cam.y += dy / cam.zoom;
    state.map.drag = { x: e.clientX, y: e.clientY };
    scheduleMapDraw();
  };
  canvas.onwheel = (e) => {
    e.preventDefault();
    const before = screenToWorld(canvas, e.offsetX, e.offsetY);
    const cam = state.map.cam;
    cam.zoom = Math.min(1.65, Math.max(0.035, cam.zoom * (e.deltaY < 0 ? 1.18 : 0.85)));
    const after = screenToWorld(canvas, e.offsetX, e.offsetY);
    cam.x += before.x - after.x;
    cam.y += before.y - after.y;
    scheduleMapDraw();
  };
  canvas.onclick = (e) => {
    if (state.map.moved) return;
    const rect = canvas.getBoundingClientRect();
    const mx = e.clientX - rect.left, my = e.clientY - rect.top;

    let best = null;
    for (const p of state.map.players || []) {
      const s = worldToScreen(canvas, p.x, p.y);
      const d = Math.hypot(s.x - mx, s.y - my);
      if (d < 18 && (!best || d < best.d)) best = { d, type: 'player', data: p };
    }
    if (state.map.showVehicles) {
      for (const v of state.map.vehicles || []) {
        const s = worldToScreen(canvas, v.x, v.y);
        const d = Math.hypot(s.x - mx, s.y - my);
        if (d < 16 && (!best || d < best.d)) best = { d, type: 'vehicle', data: v };
      }
    }
    state.map.selected = best ? { type: best.type, data: best.data } : { type: 'world', data: screenToWorld(canvas, mx, my) };
    updateMapSelection();
  };

  stopMapTimer();
  requestMapData();
  state.map.timer = setInterval(() => {
    if (state.tab === 'map' && state.open) requestMapData();
    else stopMapTimer();
  }, 1500);

  scheduleMapDraw();
}

function resizeMapCanvas(canvas) {
  const rect = canvas.getBoundingClientRect();
  const dpr = Math.max(1, Math.min(2, window.devicePixelRatio || 1));
  canvas.width = Math.max(300, Math.floor(rect.width * dpr));
  canvas.height = Math.max(260, Math.floor(rect.height * dpr));
  const ctx = canvas.getContext('2d');
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  canvas._cmWidth = rect.width;
  canvas._cmHeight = rect.height;
}

function canvasW(canvas) { return canvas._cmWidth || canvas.clientWidth || canvas.width; }
function canvasH(canvas) { return canvas._cmHeight || canvas.clientHeight || canvas.height; }

function worldToScreen(canvas, wx, wy) {
  const cam = state.map.cam;
  return {
    x: (Number(wx || 0) - cam.x) * cam.zoom + canvasW(canvas) / 2,
    y: -(Number(wy || 0) - cam.y) * cam.zoom + canvasH(canvas) / 2
  };
}

function screenToWorld(canvas, sx, sy) {
  const cam = state.map.cam;
  return {
    x: ((sx - canvasW(canvas) / 2) / cam.zoom) + cam.x,
    y: -((sy - canvasH(canvas) / 2) / cam.zoom) + cam.y,
    z: 40
  };
}

function scheduleMapDraw() {
  if (mapDrawQueued) return;
  mapDrawQueued = true;
  requestAnimationFrame(() => { mapDrawQueued = false; drawMap(); });
}

function drawMap() {
  const canvas = document.getElementById('mapCanvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  const w = canvasW(canvas), h = canvasH(canvas);
  const cam = state.map.cam;
  const bounds = mapBounds();

  ctx.clearRect(0, 0, w, h);
  ctx.fillStyle = '#07131b';
  ctx.fillRect(0, 0, w, h);

  if (mapImg) {
    const tl = worldToScreen(canvas, bounds.minX, bounds.maxY);
    const iw = (bounds.maxX - bounds.minX) * cam.zoom;
    const ih = (bounds.maxY - bounds.minY) * cam.zoom;
    ctx.globalAlpha = 0.92;
    ctx.drawImage(mapImg, tl.x, tl.y, iw, ih);
    ctx.globalAlpha = 1;
  } else {
    ctx.strokeStyle = 'rgba(140, 230, 255, 0.08)';
    ctx.lineWidth = 1;
    for (let gx = bounds.minX; gx <= bounds.maxX; gx += 500) {
      const a = worldToScreen(canvas, gx, bounds.minY), b = worldToScreen(canvas, gx, bounds.maxY);
      ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y); ctx.stroke();
    }
    for (let gy = bounds.minY; gy <= bounds.maxY; gy += 500) {
      const a = worldToScreen(canvas, bounds.minX, gy), b = worldToScreen(canvas, bounds.maxX, gy);
      ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y); ctx.stroke();
    }
  }

  const selected = state.map.selected;

  if (state.map.showVehicles) {
    for (const v of state.map.vehicles || []) {
      const s = worldToScreen(canvas, v.x, v.y);
      if (s.x < -20 || s.y < -20 || s.x > w + 20 || s.y > h + 20) continue;
      const isSel = selected && selected.type === 'vehicle' && ((selected.data.netId && selected.data.netId === v.netId) || (selected.data.plate && selected.data.plate === v.plate));
      ctx.save();
      ctx.translate(s.x, s.y);
      ctx.fillStyle = isSel ? '#ffffff' : 'rgba(255, 195, 72, 0.95)';
      ctx.strokeStyle = isSel ? '#ffd25a' : 'rgba(0,0,0,0.75)';
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.rect(-4.5, -4.5, 9, 9);
      ctx.fill();
      ctx.stroke();
      ctx.restore();
    }
  }

  for (const p of state.map.players || []) {
    const isAdmin = p.adminMode && state.map.showAdmins;
    const isSel = selected && selected.type === 'player' && Number(selected.data.id) === Number(p.id);
    const s = worldToScreen(canvas, p.x, p.y);
    if (s.x < -100 || s.y < -40 || s.x > w + 140 || s.y > h + 40) continue;
    ctx.beginPath();
    ctx.arc(s.x, s.y, isSel ? 9 : (p.self ? 8 : (isAdmin ? 7 : 5.5)), 0, Math.PI * 2);
    ctx.fillStyle = isSel ? '#ffffff' : (p.self ? '#52ffa9' : (isAdmin ? '#ff2d3d' : '#45e0ff'));
    ctx.fill();
    ctx.lineWidth = isSel ? 3 : 2;
    ctx.strokeStyle = isSel ? '#45e0ff' : 'rgba(0,0,0,0.72)';
    ctx.stroke();
    ctx.fillStyle = isAdmin ? '#ff2d3d' : 'rgba(235, 252, 255, 0.95)';
    ctx.font = isSel ? '800 11px Arial, sans-serif' : '700 11px Arial, sans-serif';
    const idText = p.characterId ? `#${p.characterId}` : 'No Char';
    const label = `${isAdmin ? 'ADMIN ' : ''}${p.name || 'Player'} ${idText}`;
    ctx.fillText(label, s.x + 10, s.y + 4);
  }
}

window.cmMapToggleCalibration = cmMapToggleCalibration;
window.cmMapCalSet = cmMapCalSet;
window.cmMapCalShift = cmMapCalShift;
window.cmMapCalScale = cmMapCalScale;
window.cmMapCalSave = cmMapCalSave;
window.cmMapCalReset = cmMapCalReset;
window.cmMapCalCopy = cmMapCalCopy;
window.cmMapVehToggle = cmMapVehToggle;
window.cmMapAdminToggle = cmMapAdminToggle;
window.cmMapZoom = cmMapZoom;
window.cmMapFocusSelf = cmMapFocusSelf;
window.cmMapClearSelection = cmMapClearSelection;
window.cmMapInspectPlayer = cmMapInspectPlayer;
window.cmMapTeleport = cmMapTeleport;
window.cmMapVehicleAction = cmMapVehicleAction;

// ---------------------------------------------------------------------------
// Developer panel launchers (plugin-registered; no commands or forms run here).
// ---------------------------------------------------------------------------
function developerPage() {
  const tools = state.data.devTools || [];
  if (!tools.length) {
    return `<div class="card"><h3>Developer Tools</h3>
      <p class="empty">No tools registered (or none you have permission for).<br><br>
      Resources self-register with:<br>
      <code>exports['cm-admin']:RegisterDevTool({ ... })</code><br>
      and appear here automatically — this panel never needs editing.</p></div>`;
  }

  const selected = tools.find(t => t.id === state.devTool) || tools[0];
  state.devTool = selected.id;

  let lastCat = null;
  const list = tools.map(t => {
    const cat = t.category !== lastCat ? `<div class="dev-cat">${esc(t.category)}</div>` : '';
    lastCat = t.category;
    return `${cat}<button class="item ${t.id === selected.id ? 'active' : ''}" onclick="cmDevSelect('${esc(t.id)}')">
      <div><strong>${esc(t.label)}</strong><small>${(t.actions || []).length} actions</small></div>
    </button>`;
  }).join('');

  const actions = (selected.actions || []).map(a => {
    return `<div class="dev-action">
      <div class="dev-action-head"><strong>${esc(a.label)}</strong>${a.hint ? `<small>${esc(a.hint)}</small>` : ''}</div>
      <button class="btn" onclick="cmDevAction('${esc(selected.id)}', '${esc(a.id)}')">Open</button>
    </div>`;
  }).join('');

  return `
    <div class="split">
      <div class="card list-card">${list}</div>
      <div class="card"><h3>${esc(selected.label)}</h3><div class="dev-actions">${actions}</div></div>
    </div>`;
}

function cmDevSelect(id) { state.devTool = id; render(); }

function cmDevAction(tool, actionId) {
  sendAction('devAction', { tool, actionId });
}

const supplyWarPresentationAdminBase = supplyWarAdmin;
supplyWarAdmin = function () {
  const events = (state.data.gangs || {}).events || {};
  const presentation = events.presentation || {};
  const extra = events.extra || {};
  const image = String(presentation.image || '').replace(/^nui:\/\/([^/]+)\//, 'https://cfx-nui-$1/');
  const filename = String(presentation.image || '').split('/').pop() || 'Not configured';
  const presentationCard = `<div class="card"><strong>EVENT PRESENTATION</strong><p>Current Asset: ${esc(filename)}</p><img src="${esc(image)}" alt="Supply War preview" style="width:min(420px,100%);aspect-ratio:16/9;object-fit:cover;border:1px solid rgba(79,209,255,.25)"></div>`;
  let html = supplyWarPresentationAdminBase();
  html = html.replace('<details open><summary>Main Event & Automatic Schedule</summary>', `${presentationCard}<details open><summary>Main Event & Automatic Schedule</summary>`);
  html = html.replace('<label><input id="swEnabled" type="checkbox"', `<label>Result Quick View <input id="swResultQuick" type="number" min="10" max="300" value="${Number(extra.resultQuickViewSeconds || 60)}"> seconds</label><label><input id="swEnabled" type="checkbox"`);
  html = html.replace("warmupAreaMessageEnabled:swRuleWarmupMessage.checked})", "warmupAreaMessageEnabled:false,resultQuickViewSeconds:+swResultQuick.value})");
  html = html.replace(/<label><input id="swRuleWarmupMessage"[^<]*<\/label>/, '<span>Proximity warmup notifications are disabled.</span>');
  return html;
};

function arsenalAdmin(){const a=(state.data.gangs||{}).arsenal;if(!a?.ok)return'';const c=a.settings||{},manifest=a.manifest||[],routes=a.routes||[],points=a.extractionPoints||[],can=hasPerm('gang.admin.manage');return `<div class="card"><div class="section-head"><div><small>GANGS · EVENTS · ARSENAL</small><h3>Arsenal Resupply</h3><p>State ${esc(a.state||'IDLE')} · Army Organisation: ARMY · Next ${a.nextStartAt?new Date(Number(a.nextStartAt)*1000).toLocaleString():'Not scheduled'}</p></div><div class="actions"><button class="btn primary" ${can?'':'disabled'} onclick="cmGangEventAction('arsenalStart')">START</button><button class="btn danger" ${can?'':'disabled'} onclick="cmGangEventAction('arsenalCancel')">CANCEL</button></div></div>
<details open><summary>GENERAL / SCHEDULE / CONVOY / GAMEPLAY / RESULT</summary><div class="form"><label><input id="arEnabled" type="checkbox" ${c.enabled?'checked':''}> Enabled</label><label><input id="arDaily" type="checkbox" ${c.dailyEnabled?'checked':''}> Daily schedule</label><input id="arHour" type="number" min="0" max="23" value="${Number(c.hour||0)}" placeholder="Hour"><input id="arMinute" type="number" min="0" max="59" value="${Number(c.minute||0)}" placeholder="Minute"><input id="arMinArmy" type="number" min="1" max="100" value="${Number(c.minimumArmyOnline||2)}" placeholder="Minimum Army"><input id="arWarmup" type="number" min="30" max="1800" value="${Number(c.warmupSeconds||300)}" placeholder="Warmup seconds"><input id="arPrep" type="number" min="10" max="1800" value="${Number(c.preparationSeconds||120)}" placeholder="Preparation seconds"><input id="arDuration" type="number" min="300" max="14400" value="${Number(c.maximumDurationSeconds||3600)}" placeholder="Maximum duration"><input id="arQuick" type="number" min="10" max="300" value="${Number(c.resultQuickViewSeconds||60)}" placeholder="Quick result seconds"><input id="arLead" type="number" min="0" max="3" value="${Number(c.leadEscortCount||0)}" placeholder="Lead escorts"><input id="arCargo" type="number" min="1" max="3" value="${Number(c.cargoTruckCount||2)}" placeholder="Cargo trucks"><input id="arRear" type="number" min="0" max="3" value="${Number(c.rearEscortCount||0)}" placeholder="Rear escorts"><label><input id="arIntel" type="checkbox" ${c.intelEnabled?'checked':''}> Approximate intel</label><input id="arIntelInterval" type="number" min="30" max="300" value="${Number(c.intelIntervalSeconds||75)}" placeholder="Intel interval"><input id="arIntelRadius" type="number" min="200" max="1000" value="${Number(c.approximateSearchRadius||750)}" placeholder="Search radius"><input id="arBreach" type="number" min="5" max="180" value="${Number(c.breachSeconds||20)}" placeholder="Breach seconds"><input id="arSpeed" type="number" min=".05" max="3" step=".05" value="${Number(c.maxStoppedSpeed||.75)}" placeholder="Stopped speed"><input id="arDistance" type="number" min="1" max="5" step=".1" value="${Number(c.interactionDistance||2.5)}" placeholder="Interaction distance"><input id="arUnload" type="number" min="5" max="300" value="${Number(c.unloadSeconds||20)}" placeholder="Unload seconds"><button class="btn primary" ${can?'':'disabled'} onclick="cmGangEventAction('arsenalConfig','',{enabled:arEnabled.checked,dailyEnabled:arDaily.checked,hour:+arHour.value,minute:+arMinute.value,minimumArmyOnline:+arMinArmy.value,warmupSeconds:+arWarmup.value,preparationSeconds:+arPrep.value,maximumDurationSeconds:+arDuration.value,resultQuickViewSeconds:+arQuick.value,leadEscortCount:+arLead.value,cargoTruckCount:+arCargo.value,rearEscortCount:+arRear.value,intelEnabled:arIntel.checked,intelIntervalSeconds:+arIntelInterval.value,approximateSearchRadius:+arIntelRadius.value,breachSeconds:+arBreach.value,maxStoppedSpeed:+arSpeed.value,interactionDistance:+arDistance.value,unloadSeconds:+arUnload.value})">SAVE CONFIGURATION</button></div></details>
<details><summary>MANIFEST</summary><div class="form"><input id="arItem" class="input" placeholder="Authoritative item ID"><input id="arQuantity" type="number" min="1" max="100000" value="1" placeholder="Quantity"><input id="arCrate" type="number" min="1" max="100000" value="1" placeholder="Crate size"><input id="arValue" type="number" min="1" max="100000" value="1" placeholder="Value weight"><button class="btn primary" ${can?'':'disabled'} onclick="cmGangEventAction('arsenalManifest','',{item:arItem.value,quantity:+arQuantity.value,crateSize:+arCrate.value,valueWeight:+arValue.value})">ADD / UPDATE</button></div><div class="table-wrap"><table><tbody>${manifest.map(x=>`<tr><td>${esc(x.item)}</td><td>${Number(x.quantity)} total</td><td>${Number(x.crateSize)} / crate</td><td>${Number(x.valueWeight)} value</td><td><button class="btn small danger" ${can?'':'disabled'} onclick="cmGangEventAction('arsenalManifestDelete','',{item:'${esc(x.item)}'})">DELETE</button></td></tr>`).join('')||'<tr><td>No manifest.</td></tr>'}</tbody></table></div></details>
<details><summary>ROUTES / LOADING / WAREHOUSE / WAYPOINTS</summary><div class="form"><input id="arRouteId" class="input" placeholder="Route ID"><button class="btn primary" ${can?'':'disabled'} onclick="cmGangEventAction('arsenalRoutePoint','',{routeId:arRouteId.value,point:'start'})">SET START HERE</button><button class="btn primary" ${can?'':'disabled'} onclick="cmGangEventAction('arsenalRoutePoint','',{routeId:arRouteId.value,point:'waypoint_add'})">ADD WAYPOINT HERE</button><button class="btn primary" ${can?'':'disabled'} onclick="cmGangEventAction('arsenalRoutePoint','',{routeId:arRouteId.value,point:'destination'})">SET WAREHOUSE HERE</button></div><div class="table-wrap"><table><tbody>${routes.map(r=>`<tr><td>${esc(r.label||r.id)}</td><td>${(r.waypoints||[]).map((_,i)=>`<button class="btn small" ${can?'':'disabled'} onclick="cmGangEventAction('arsenalRoutePoint','',{routeId:'${esc(r.id)}',point:'waypoint_remove',index:${i+1}})">REMOVE ${i+1}</button>`).join(' ')||'No waypoints'}</td><td><button class="btn small danger" ${can?'':'disabled'} onclick="cmGangEventAction('arsenalRouteDelete','',{routeId:'${esc(r.id)}'})">DELETE</button></td></tr>`).join('')||'<tr><td>No valid routes.</td></tr>'}</tbody></table></div></details>
<details><summary>GANG EXTRACTION LOCATIONS</summary><div class="form"><input id="arExtractGang" class="input" placeholder="Optional gang ID"><input id="arExtractRadius" type="number" min="2" max="15" value="4"><button class="btn primary" ${can?'':'disabled'} onclick="cmGangEventAction('arsenalExtraction','',{gangId:arExtractGang.value||null,radius:+arExtractRadius.value})">ADD AT MY POSITION</button></div><div class="table-wrap"><table><tbody>${points.map(p=>`<tr><td>#${Number(p.id)} · ${esc(p.gang_id||p.gangId||'ALL GANGS')}</td><td>Radius ${Number(p.radius||4)}m</td><td><button class="btn small danger" ${can?'':'disabled'} onclick="cmGangEventAction('arsenalExtractionDelete','',{id:${Number(p.id)}})">DELETE</button></td></tr>`).join('')||'<tr><td>No extraction points.</td></tr>'}</tbody></table></div></details></div>`}
const arsenalGangsPageBase=gangsPage;gangsPage=function(){return arsenalAdmin()+arsenalGangsPageBase()};
