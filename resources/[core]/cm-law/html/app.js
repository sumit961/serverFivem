const app=document.querySelector('#app'),roster=document.querySelector('#roster'),toast=document.querySelector('#toast');let state=null,facilityOnly=false;
const post=(name,data={})=>fetch(`https://${GetParentResourceName()}/${name}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)}).then(r=>r.json());
function notice(message,kind='success'){toast.textContent=message||'';toast.className=`show ${kind}`;clearTimeout(notice.timer);notice.timer=setTimeout(()=>toast.className='',2600)}
const orgBranding={
  sahp:{logo:'assets/org/sahp.svg',banner:'assets/org/sahp-banner.svg',art:'assets/org/sahp-officer.png',mark:'SAHP',label:'San Andreas Highway Patrol',shortLabel:'SAHP',jurisdiction:'State highway patrol coverage'},
  sheriff:{logo:'assets/org/sheriff.svg',banner:'assets/org/sheriff-banner.svg',art:'assets/org/sheriff-officer.png',mark:'BCSO',label:"Blaine County Sheriff's Office",shortLabel:'BCSO',jurisdiction:'Blaine County and county contract areas'},
  fib:{logo:'assets/org/fib.svg',banner:'assets/org/fib-banner.svg',art:'assets/org/fib-agent.png',mark:'FIB',label:'Federal Investigation Bureau',shortLabel:'FIB',jurisdiction:'Federal investigations and intelligence'},
  army:{logo:'assets/org/army.svg',banner:'assets/org/army-banner.svg',art:'assets/org/army-soldier.png',mark:'ARMY',label:'San Andreas Army',shortLabel:'ARMY',jurisdiction:'Military support and controlled deployments'},
  default:{logo:'assets/org/default.svg',banner:'assets/org/default-banner.svg',art:'assets/org/default-officer.png',mark:'LAW',label:'Legal Organization',shortLabel:'LEGAL ORGANIZATION',jurisdiction:'Authorized jurisdiction'}
};
function orgProfile(org={}){const brand=orgBranding[org.id]||orgBranding.default;return {...brand,...org,label:org.label||brand.label||'Organization',shortLabel:org.shortLabel||brand.shortLabel||brand.mark||'LAW',jurisdiction:org.jurisdiction||brand.jurisdiction||'Authorized jurisdiction'}}
function applyOrgBranding(org={}){
  const profile=orgProfile(org);
  const logoEl=document.querySelector('#brandLogo'); if(logoEl) logoEl.src=profile.logo;
  const overviewLogoEl=document.querySelector('#overviewLogo'); if(overviewLogoEl) overviewLogoEl.src=profile.logo;
  const art=document.querySelector('#overviewCharacterArt'); if(art) art.src=profile.art;
  const mark=document.querySelector('#overviewWatermark'); if(mark) mark.textContent=profile.mark||profile.shortLabel||'LAW';
  document.documentElement.style.setProperty('--org-accent',profile.color||'#52dce9');
  return profile;
}
function render(data){
  state=data;
  if(!data?.ok){notice(data?.error||'Unable to load organization.','error');return}
  const m=data.member||{},o=applyOrgBranding(data.organization||{});
  const shortLabelEl=document.querySelector('#shortLabel'); if(shortLabelEl) shortLabelEl.textContent=o.shortLabel;
  const orgLabelEl=document.querySelector('#orgLabel'); if(orgLabelEl) orgLabelEl.textContent=o.label;
  const jurisdictionEl=document.querySelector('#jurisdiction'); if(jurisdictionEl) jurisdictionEl.textContent=o.jurisdiction||'';
  const rankNameEl=document.querySelector('#rankName'); if(rankNameEl) rankNameEl.textContent=m.rankName||'—';
  const dutyStatusEl=document.querySelector('#dutyStatus'); if(dutyStatusEl) dutyStatusEl.textContent=m.suspended?'Suspended':m.onDuty?'On duty':'Off duty';
  const fleetAllowed = data.canFleetManage || data.canFleetSpawn || Number(data?.summary?.fleetConfigured||0)>0;
  const logsAllowed = data.canManage || data.canViewActivity === true;
  const fleetTab=document.querySelector('#fleetTab'); if(fleetTab) fleetTab.classList.toggle('hidden',!fleetAllowed);
  const fleetRecall=document.querySelector('#fleetRecallAll'); if(fleetRecall) fleetRecall.classList.toggle('hidden',!data.canFleetManage);
  const logsTab=document.querySelector('#logsTab'); if(logsTab) logsTab.classList.toggle('hidden',!logsAllowed);
  const logisticsTab=document.querySelector('#logisticsTab'); if(logisticsTab) logisticsTab.classList.toggle('hidden',data.logisticsVisible!==true);
  const ranks=(data.ranks||[]).filter(r=>!r.is_leader&&Number(r.tier)<Number(m.tier||0));
  roster.innerHTML=(data.roster||[]).map(x=>`<article class="member"><div><div class="member-name">${esc(x.name||x.character_id)}</div><div class="meta">CID ${esc(x.character_id)} · ${esc(x.rank_name)}</div></div><span class="badge ${x.suspended?'suspended':x.on_duty?'on':''}">${x.suspended?'Suspended':x.on_duty?'On duty':'Off duty'}</span>${data.canManage&&!x.is_leader&&Number(x.tier)<Number(m.tier||0)?`<div class="actions"><select data-rank="${esc(x.character_id)}">${ranks.map(r=>`<option value="${r.id}" ${Number(r.id)===Number(x.rank_id)?'selected':''}>${esc(r.name)}</option>`).join('')}</select><button data-action="rank" data-cid="${esc(x.character_id)}">Set rank</button><button data-action="${x.suspended?'reinstate':'suspend'}" data-cid="${esc(x.character_id)}">${x.suspended?'Reinstate':'Suspend'}</button><button data-action="fire" data-cid="${esc(x.character_id)}">Remove</button></div>`:'<div></div>'}</article>`).join('')||(data.canViewMembers?'<p>No members found.</p>':'<p>Your rank does not have roster visibility.</p>');
  const f=data.facilities||{},types=data.facilityTypes||{};document.querySelector('#facilities').innerHTML=Object.entries(types).map(([id,t])=>{const set=!!f[id];return `<article class="facility-card"><small>${esc(t.role)}</small><h3>${esc(t.label)}</h3><p>${set?'Configured and active':'Location not configured'}</p>${data.canManage?`<div class="actions"><button data-facility="${esc(id)}" data-reset="false">Set here</button>${set?`<button class="danger" data-facility="${esc(id)}" data-reset="true">Reset</button>`:''}</div>`:''}</article>`}).join('');
  renderOverview({...data,organization:o});renderRanksList()
}

// ── Overview ───────────────────────────────────────────────────────────────
function renderOverview(data){
  const m=data.member||{}, roster=data.roster||[], summary=data.summary||{};
  const caps=m.capabilities||{};
  const capLabels={dispatch:'Dispatch',mdt:'MDT',arrest:'Arrest',search:'Search',citations:'Citations',impound:'Impound',radar:'Radar',spikes:'Spikes',barricades:'Barricades',clamp:'Clamp',k9:'K9',alpr:'ALPR',armory:'Armory',fleet:'Fleet',evidence:'Evidence',prisonIntake:'Prison Intake'};
  const memberCount = Number(summary.memberCount ?? roster.length ?? 0);
  const dutyRoster = roster.filter(x=>x.on_duty&&!x.suspended);
  const onDutyCount = Number(summary.onDutyCount ?? dutyRoster.length ?? 0);
  const leaderName = summary.leaderName || data.organization.leaderName || 'Not assigned';
  const leaderCid = summary.leaderCid || data.organization.leaderCid || '';
  document.querySelector('#overviewShortLabel').textContent=data.organization.shortLabel||'LEGAL ORGANIZATION';
  document.querySelector('#overviewOrgName').textContent=data.organization.label||'Organization';
  document.querySelector('#overviewJurisdiction').textContent=data.organization.jurisdiction||'Authorized jurisdiction';
  document.querySelector('#overviewRank').textContent=m.rankName||'—';
  document.querySelector('#overviewCharacterId').textContent=`CID ${esc(data.characterId||m.characterId||'—')}`;
  const dutyBadge=document.querySelector('#overviewDutyBadge');
  const dutyText=m.suspended?'SUSPENDED':m.onDuty?'ON DUTY':'OFF DUTY';
  dutyBadge.textContent=dutyText; dutyBadge.className=`status-pill ${m.suspended?'is-suspended':m.onDuty?'is-on':'is-off'}`;
  document.querySelector('#overviewStats').innerHTML=[
    ['COMMAND',leaderName,leaderCid?`CID ${leaderCid}`:'Leader not assigned','command'],
    ['MEMBERS',memberCount.toLocaleString(),`${onDutyCount} currently on duty`,'members'],
    ['ON DUTY',onDutyCount.toLocaleString(),onDutyCount===1?'1 active unit':'Active personnel','duty'],
    ['FLEET AVAILABLE',Number(summary.fleetAvailable||0).toLocaleString(),`${Number(summary.fleetConfigured||0)} configured for agency`,'fleet'],
  ].map(([label,value,sub,kind])=>`<div class="stat stat--${kind}"><span class="stat-icon" aria-hidden="true"></span><div><small>${esc(label)}</small><strong>${esc(value)}</strong><span>${esc(sub)}</span></div></div>`).join('');
  const enabled=Object.entries(caps).filter(([,on])=>on===true);
  document.querySelector('#overviewCapabilityCount').textContent=`${enabled.length} ACTIVE`;
  document.querySelector('#overviewCapabilities').innerHTML=enabled.length?enabled.map(([id])=>`<span class="capability-pill"><i></i>${esc(capLabels[id]||id)}</span>`).join(''):'<span class="muted-inline">No operational capabilities enabled.</span>';
  // Field coordination: hidden entirely unless the viewer holds at least one
  // of the two permissions, matching how cm-ems and cm-police gate the same
  // panel. The server checks again on every call -- this is presentation only.
  const canMap=data.canViewMemberMap===true,canMeet=data.canSetMeeting===true;
  document.querySelector('#overviewToolsPanel').hidden=!(canMap||canMeet);
  document.querySelector('#memberMap').hidden=!canMap;
  document.querySelector('#meetingPoint').hidden=!canMeet;
  document.querySelector('#clearMeeting').hidden=!canMeet;
  document.querySelector('#overviewDutyCount').textContent=`${onDutyCount} UNIT${onDutyCount===1?'':'S'}`;
  document.querySelector('#overviewDutyRoster').innerHTML=data.canViewMembers
    ? (dutyRoster.length?dutyRoster.slice(0,5).map(x=>{const name=x.name||`CID ${x.character_id}`;const initials=name.split(/\s+/).filter(Boolean).slice(0,2).map(n=>n[0]).join('').toUpperCase();return `<div class="duty-person"><span class="duty-avatar">${esc(initials||'U')}</span><div><strong>${esc(name)}</strong><small>${esc(x.rank_name||'Member')}</small></div><span class="duty-live">10-8</span></div>`}).join(''):'<p class="overview-copy">No organization members are currently on duty.</p>')
    : '<p class="overview-copy">Roster visibility is restricted for your rank.</p>';
  document.querySelector('#overviewShiftKicker').textContent=m.suspended?'ACCESS LIMITED':m.onDuty?'ACTIVE SHIFT':'NOT ACTIVE';
  document.querySelector('#overviewShift').innerHTML=`
    <div class="shift-row"><span>Rank</span><strong>${esc(m.rankName||'—')}</strong></div>
    <div class="shift-row"><span>Tier</span><strong>${Number(m.tier||0)}</strong></div>
    <div class="shift-row"><span>Status</span><strong class="shift-state ${m.suspended?'danger':m.onDuty?'live':''}">${esc(dutyText)}</strong></div>
    <div class="shift-row"><span>Uniform</span><strong>${m.uniformActive?'Duty uniform':'Not active'}</strong></div>`;
  const activityPanel=document.querySelector('#overviewActivityPanel');
  const activity=data.recentActivity||[];
  activityPanel.classList.toggle('is-restricted',data.canViewActivity!==true);
  document.querySelector('#overviewRecentActivity').innerHTML=data.canViewActivity===true
    ? (activity.length?activity.map(row=>{const label=(typeof activityLabels!=='undefined'&&activityLabels[row.action])||String(row.action||'Activity').replaceAll('_',' ');const desc=typeof describeLog==='function'?describeLog(row.detail):'';return `<div class="activity-item"><span class="activity-marker"></span><div><strong>${esc(row.actorName||'System')}</strong><p>${esc(label)}${desc?` · ${desc}`:''}</p></div><time>${esc(row.createdAt||'')}</time></div>`}).join(''):'<p class="overview-copy">No organization activity recorded yet.</p>')
    : '<div class="activity-restricted"><span>Restricted</span><p>Recent organization activity is available to command staff.</p></div>';
}

// ── Ranks & Access ─────────────────────────────────────────────────────────
let editingRankId=null;
function renderRanksList(){
  const data=state;if(!data)return;
  const m=data.member,manage=data.canManageRanks,permLabels=data.permissions||{};
  document.querySelector('#newRank').classList.toggle('hidden',!manage);
  document.querySelector('#ranksList').innerHTML=(data.ranks||[]).map(r=>{
    const editable=manage&&!r.is_leader&&Number(r.tier)<Number(m.tier);
    const granted=Object.keys(r.permissions||{}).filter(k=>r.permissions[k]);
    const pills=!data.canInspectRankPermissions?'<span class="perm-pill perm-pill--empty">Permission details restricted</span>':granted.length?granted.map(k=>`<span class="perm-pill">${esc(permLabels[k]||k)}</span>`).join(''):'<span class="perm-pill perm-pill--empty">No permissions</span>';
    return `<article class="rank-card${r.is_leader?' leader':''}">
      <div class="rank-card__head"><strong>${esc(r.name)}</strong><span class="badge">Tier ${r.tier}</span>${r.is_leader?'<span class="badge leader">Leader</span>':''}</div>
      <div class="perm-pills">${pills}</div>
      ${editable?`<div class="actions"><button data-rank-edit="${r.id}">Edit</button><button class="danger" data-rank-delete="${r.id}">Delete</button></div>`:''}
    </article>`;
  }).join('')||'<p>No ranks configured.</p>';
}
function openRankEditor(rank){
  editingRankId=rank?Number(rank.id):null;
  document.querySelector('#editRankName').value=rank?rank.name:'';
  document.querySelector('#editRankTier').value=rank?rank.tier:'';
  const perms=state.permissions||{},mine=state.member.permissions||{},canPerms=state.canManagePermissions,isLeader=state.member.isLeader;
  const current=rank?(rank.permissions||{}):{};
  document.querySelector('#permissionEditor').innerHTML=Object.entries(perms).map(([key,label])=>{
    const checked=current[key]===true;
    const allowed=canPerms&&(isLeader||mine[key]===true);
    return `<label class="permission-check${allowed?'':' disabled'}"><input type="checkbox" value="${esc(key)}" ${checked?'checked':''} ${allowed?'':'disabled'}>${esc(label)}</label>`;
  }).join('');
  document.querySelector('#rankEditor').classList.remove('hidden');
}
function closeRankEditor(){editingRankId=null;document.querySelector('#rankEditor').classList.add('hidden')}
document.querySelector('#newRank').onclick=()=>openRankEditor(null);
document.querySelector('#cancelRank').onclick=()=>closeRankEditor();
document.querySelector('#saveRankBtn').onclick=async()=>{
  const permissions={};
  document.querySelectorAll('#permissionEditor input[type=checkbox]:checked').forEach(c=>permissions[c.value]=true);
  const r=await post('saveRank',{rankId:editingRankId,name:document.querySelector('#editRankName').value,tier:Number(document.querySelector('#editRankTier').value||0),permissions});
  notice(r.message||r.error,r.ok?'success':'error');
  if(r.ok)closeRankEditor();
};
document.querySelector('#ranksList').onclick=async e=>{
  const editBtn=e.target.closest('[data-rank-edit]'),delBtn=e.target.closest('[data-rank-delete]');
  if(editBtn){const rank=(state.ranks||[]).find(r=>Number(r.id)===Number(editBtn.dataset.rankEdit));if(rank)openRankEditor(rank)}
  if(delBtn){
    if(!confirm('Delete this rank? Members must be reassigned first.'))return;
    const r=await post('deleteRank',{rankId:Number(delBtn.dataset.rankDelete)});
    notice(r.message||r.error,r.ok?'success':'error');
  }
};

// ── Activity Logs ──────────────────────────────────────────────────────────
const activityLabels={
  duty_started:'Started duty',duty_ended:'Ended duty',wardrobe_duty_started:'Started duty in uniform',
  member_hire:'Added a member',member_rank:'Changed a member\'s rank',member_suspend:'Suspended a member',
  member_reinstate:'Reinstated a member',member_fire:'Removed a member',member_promoted:'Promoted a member',
  member_demoted:'Demoted a member',rank_created:'Created a rank',rank_edited:'Edited a rank',rank_deleted:'Deleted a rank',
  facility_set:'Set a facility location',facility_reset:'Reset a facility location',facility_opened:'Used a facility',
  suspect_cuffed:'Cuffed a suspect',suspect_uncuffed:'Uncuffed a suspect',suspect_removed_from_vehicle:'Removed a suspect from a vehicle',
  suspect_booked:'Booked a suspect',fleet_vehicle_location_saved:'Saved a fleet vehicle location',
  fleet_vehicle_min_tier_set:'Changed a fleet vehicle\'s minimum rank',fleet_recalled_all:'Recalled the fleet',
  dispatch_call_resolved:'Resolved a dispatch call',dispatch_officer_alert:'Activated an officer dispatch alert',
  armory_stock_configured:'Configured armory stock',armory_checkout:'Checked out armory equipment',
  suspect_inventory_searched:'Searched a suspect',suspect_items_confiscated:'Confiscated suspect evidence',
  mdt_note_added:'Added a shared MDT note',mdt_report_created:'Created a shared MDT report',
  mdt_wanted_set:'Changed a wanted level',mdt_warrant_created:'Issued a shared warrant',
  mdt_warrant_closed:'Closed a shared warrant',
  shared_jail_spawn_added:'Added a shared jail spawn',shared_jail_spawns_reset:'Reset shared jail spawns',
  shared_jail_release_set:'Set the shared jail release point',shared_jail_release_reset:'Reset the shared jail release point',
  front_desk_service_requested:'Requested front-desk assistance',front_desk_surrendered:'Surrendered at a front desk',
  front_desk_contraband_surrendered:'Surrendered contraband at a front desk',
};
function describeLog(detail){
  detail=detail||{};
  const parts=[];
  if(detail.targetCid)parts.push(`Target CID ${detail.targetCid}`);
  if(detail.name)parts.push(esc(detail.name));
  if(detail.rank)parts.push(esc(detail.rank));
  if(detail.tier!==undefined)parts.push(`Tier ${detail.tier}`);
  if(detail.model)parts.push(esc(detail.model));
  if(detail.minTier!==undefined)parts.push(`Min tier ${detail.minTier}`);
  if(detail.minutes!==undefined)parts.push(`${detail.minutes} min`);
  if(detail.recalled!==undefined)parts.push(`${detail.recalled} recalled`);
  if(detail.failed!==undefined)parts.push(`${detail.failed} failed`);
  if(detail.callId!==undefined)parts.push(`Call #${detail.callId}`);
  if(detail.facilityType)parts.push(esc(detail.facilityType));
  if(detail.itemName)parts.push(esc(detail.itemName));
  if(detail.amount!==undefined)parts.push(`Amount ${detail.amount}`);
  if(detail.stock!==undefined)parts.push(`Stock ${detail.stock}`);
  if(detail.reportId!==undefined)parts.push(`Report #${detail.reportId}`);
  if(detail.warrantId!==undefined)parts.push(`Warrant #${detail.warrantId}`);
  if(detail.stars!==undefined)parts.push(`${detail.stars} stars`);
  return parts.join(' · ');
}
let activityLogRows=[];
function renderActivityLog(){
  document.querySelector('#activityLogList').innerHTML=activityLogRows.map(row=>{
    const label=activityLabels[row.action]||row.action;
    const desc=describeLog(row.detail);
    return `<article class="log-row"><div class="log-row__main"><strong>${esc(row.actorName)}</strong> ${esc(label)}${desc?` · ${desc}`:''}</div><time>${esc(row.createdAt)}</time></article>`;
  }).join('')||'<p>No activity recorded yet.</p>';
}
async function loadActivityLog(){const r=await post('activityLog');activityLogRows=r?.list||[];renderActivityLog()}

// ── Fleet vehicles ─────────────────────────────────────────────────────────
// Appearance (model/label/category/image) comes live from the vehicle shop
// admin's org-tagged catalog -- there is no separate "add to fleet" step;
// every tagged vehicle shows up here, unconfigured ones just need a
// location set first (Set location, drive it, press H).
let fleetVehicles = [];
function renderFleetList(){
  const manage = state?.canFleetManage;
  document.querySelector('#fleetRoster').innerHTML = fleetVehicles.map(v => {
    return `<article class="fleet-row${v.configured && !v.enabled ? ' disabled' : ''}">
    <div class="fleet-row__main"><strong>${esc(v.label)}</strong><small>${esc(v.category || 'Vehicle')} · Parking: ${v.configured ? `${v.location?.x ?? 'saved'}, ${v.location?.y ?? 'saved'}` : 'not configured'} · Minimum rank tier ${v.minTier}${v.enabled ? '' : ' · Disabled'} · ${esc(String(v.status || 'available').replaceAll('_', ' '))}${v.engineHealth != null ? ` · Engine ${Math.round(Number(v.engineHealth) / 10)}% · Body ${Math.round(Number(v.bodyHealth) / 10)}% · Fuel ${Math.round(Number(v.fuel || 0))}%` : ''}</small></div>
    <div class="actions">
      ${manage ? `<input type="number" min="0" max="100" value="${v.minTier}" data-fleet-tier="${esc(v.model)}"${v.configured ? '' : ' disabled title="Set a location first"'}>` : ''}
      ${manage ? `<button data-fleet-location="${esc(v.model)}">Set location</button>` : ''}
    </div>
  </article>`;
  }).join('') || `<p>${manage ? 'No vehicles are tagged for this organization in the vehicle shop admin yet.' : 'No fleet vehicles are available to your rank yet.'}</p>`;
}
async function loadFleet(){const r=await post('fleetCatalog');fleetVehicles=r?.vehicles||[];renderFleetList()}
document.querySelector('#fleetRoster').onclick=async e=>{
  const location=e.target.closest('[data-fleet-location]');
  if(location){const r=await post('setFleetVehicleLocation',{model:location.dataset.fleetLocation});notice(r.message||r.error,r.ok?'success':'error')}
};
document.querySelector('#fleetRoster').addEventListener('change',async e=>{
  const tierInput=e.target.closest('[data-fleet-tier]');
  if(!tierInput)return;
  const r=await post('setFleetVehicleMinTier',{model:tierInput.dataset.fleetTier,minTier:Number(tierInput.value||0)});
  if(!r?.ok)loadFleet();
});
document.querySelector('#fleetRecallAll').onclick=async()=>{
  if(!confirm('Recall every enabled fleet vehicle back to its saved location?'))return;
  const r=await post('recallAllFleetVehicles');
  notice(r.message||r.error,r.ok?'success':'error');
};
// ── Dispatch (911 calls) ──────────────────────────────────────────────────
let dispatchActiveCalls = [], dispatchHistory = [];
function timeAgo(epochSeconds){const seconds=Math.max(0,Math.floor(Date.now()/1000)-Number(epochSeconds||0));if(seconds<60)return `${seconds}s ago`;if(seconds<3600)return `${Math.floor(seconds/60)}m ago`;return `${Math.floor(seconds/3600)}h ago`}
function renderDispatchActiveList(){
  const myCid = state?.characterId;
  document.querySelector('#lawDispatchActiveCount').textContent=dispatchActiveCalls.length;
  document.querySelector('#lawDispatchAssignedCount').textContent=dispatchActiveCalls.filter(call=>(call.responders||[]).length>0).length;
  document.querySelector('#dispatchActiveList').innerHTML = dispatchActiveCalls.map(call => {
    const mine = myCid && (call.responders || []).find(r => r.characterId === myCid);
    const responders = (call.responders || []).map(r => `${esc(r.name)} (${r.status === 'en_route' ? 'En Route' : 'Accepted'})`).join(', ') || 'No one responding yet';
    const callType=call.callType||'citizen',priority=Number(call.priority||1);
    return `<article class="dispatch-call-row priority-${priority}">
      <div class="dispatch-call-main"><strong><span class="dispatch-type ${esc(callType)}">${esc(callType)}</span>${esc(call.details)}</strong>
      <small>Location: ${esc(call.location || 'Unknown')} · Caller: ${esc(call.callerName || 'Unknown')} · ${timeAgo(call.createdAt)}</small>
      <small>Responding: ${responders}</small></div>
      <div class="actions">
        ${!mine ? `<button data-dispatch-accept="${call.id}">Accept</button>` : ''}
        ${mine && mine.status !== 'en_route' ? `<button data-dispatch-enroute="${call.id}">En Route</button>` : ''}
        ${mine ? `<button data-dispatch-resolve="${call.id}">Resolve</button>` : ''}
      </div>
    </article>`;
  }).join('') || '<p>No active calls.</p>';
}
function renderDispatchHistoryList(){
  document.querySelector('#dispatchHistoryList').innerHTML = dispatchHistory.map(row => `<article class="dispatch-call-row"><div class="dispatch-call-main"><strong>${esc(row.details)}</strong> · ${esc(row.status)}<small>Location: ${esc(row.location || 'Unknown')} · Caller: ${esc(row.callerName || 'Unknown')} · ${esc(row.createdAt)}${row.resolution ? ' · ' + esc(row.resolution) : ''}</small></div></article>`).join('') || '<p>No resolved calls yet.</p>';
}
async function loadDispatchActiveCalls(){const r=await post('dispatchActiveCalls');dispatchActiveCalls=r?.list||[];renderDispatchActiveList()}
async function loadDispatchHistory(){const r=await post('dispatchHistory');dispatchHistory=r?.list||[];renderDispatchHistoryList()}
document.querySelector('#dispatchActiveList').onclick=async e=>{
  const accept=e.target.closest('[data-dispatch-accept]'),enroute=e.target.closest('[data-dispatch-enroute]'),resolve=e.target.closest('[data-dispatch-resolve]');
  if(accept){const r=await post('dispatchAccept',{callId:Number(accept.dataset.dispatchAccept)});notice(r.message||r.error,r.ok?'success':'error');loadDispatchActiveCalls()}
  if(enroute){const r=await post('dispatchEnRoute',{callId:Number(enroute.dataset.dispatchEnroute)});notice(r.message||r.error,r.ok?'success':'error');loadDispatchActiveCalls()}
  if(resolve){const r=await post('dispatchResolve',{callId:Number(resolve.dataset.dispatchResolve)});notice(r.message||r.error,r.ok?'success':'error');if(r.ok){loadDispatchActiveCalls();loadDispatchHistory()}}
};
document.querySelector('#dispatchBackup').onclick=async()=>{if(!confirm('Request backup and send your current location to all available legal units?'))return;const r=await post('dispatchOfficerAlert',{alertType:'backup',confirmed:true});notice(r.message||r.error,r.ok?'success':'error')};
document.querySelector('#dispatchPanic').onclick=async()=>{if(!confirm('Activate the panic button and send an urgent officer-in-distress alert?'))return;const r=await post('dispatchOfficerAlert',{alertType:'panic',confirmed:true});notice(r.message||r.error,r.ok?'success':'error')};
function esc(v){const d=document.createElement('div');d.textContent=String(v??'');return d.innerHTML}
window.addEventListener('message',e=>{const {action,data,kind,message,initialTab}=e.data||{};if(action==='open'){facilityOnly=e.data?.facilityOnly===true;const standalone=e.data?.standaloneMode===true;app.classList.toggle('standalone-interface',standalone);app.classList.toggle('standalone-dispatch',standalone&&initialTab==='dispatch');app.classList.toggle('standalone-mdt',standalone&&initialTab==='mdt');app.classList.remove('hidden');render(data);if(standalone&&initialTab){document.querySelectorAll('.view').forEach(x=>x.classList.add('hidden'));document.querySelector(`#${initialTab}View`)?.classList.remove('hidden');document.querySelector('#pageTitle').textContent=pageTitles[initialTab]||initialTab;if(initialTab==='dispatch'){loadDispatchActiveCalls();loadDispatchHistory()}}else{const requested=initialTab&&document.querySelector(`[data-tab="${initialTab}"]`);const tab=requested&&!requested.classList.contains('hidden')?requested:document.querySelector('[data-tab="overview"]');if(tab)tab.click()}}if(action==='dashboard')render(data);if(action==='close'){app.classList.add('hidden');app.classList.remove('standalone-interface','standalone-dispatch','standalone-mdt')}if(action==='notice')notice(message,kind);if(action==='dispatchRefresh'&&!app.classList.contains('hidden')&&!document.querySelector('#dispatchView').classList.contains('hidden'))loadDispatchActiveCalls()});
document.querySelectorAll('[data-close]').forEach(b=>b.onclick=()=>post('close'));document.addEventListener('keydown',e=>{if(e.key==='Escape'){if(!document.querySelector('#legalArmory').classList.contains('hidden'))post('legalArmoryClose');else if(!document.querySelector('#wardrobeRoom').classList.contains('hidden'))post('legalWardrobeCancel');else if(!document.querySelector('#facilityDialogue').classList.contains('hidden'))post('facilityDialogueClose');else post('close')}});
let logisticsData={items:[],orders:[]};
function renderLogistics(){const info=state?.logistics||{},form=document.querySelector('#logisticsOrderForm');form.classList.toggle('hidden',info.canRequest!==true);document.querySelector('#logisticsHint').textContent=info.canRequest===true?'Submit from your on-duty organization armory. Army quartermasters accept, prepare, load, and deliver orders.':'View order progress here; your rank cannot submit routine supply requests.';document.querySelector('#logisticsItem').innerHTML=(logisticsData.items||[]).map(x=>`<option value="${esc(x.itemName)}">${esc(x.label)} · ${esc(x.itemName)}</option>`).join('');document.querySelector('#logisticsOrders').innerHTML=(logisticsData.orders||[]).map(o=>{const lines=(o.lines||[]).map(l=>`${esc(l.itemName)} × ${l.quantity}`).join(', ');const buttons=Object.keys(o.actions||{}).map(a=>`<button data-logistics-action="${esc(a)}" data-order-id="${o.id}">${esc(a.replaceAll('_',' '))}</button>`).join('');return `<article class="logistics-order"><div><strong>Order #${o.id} · ${esc(o.status.replaceAll('_',' '))}</strong><small>${esc(o.requesterLabel)} · ${lines}</small>${o.shipment?`<small>Shipment ${esc(o.shipment)}</small>`:''}</div><div class="actions">${buttons}</div></article>`}).join('')||'<p>No supply orders.</p>'}
async function loadLogistics(){const r=await post('logistics');if(!r?.ok)return notice(r?.error||'Logistics unavailable.','error');logisticsData=r;renderLogistics()}
async function loadArsenalHistory(){const r=await post('arsenalHistory'),box=document.querySelector('#arsenalHistory');if(!box)return;if(!r?.ok){box.innerHTML=`<p>${esc(r?.error||'Arsenal history unavailable.')}</p>`;return}box.innerHTML=(r.history||[]).map(row=>`<article class="logistics-order"><div><strong>ARSENAL RESUPPLY · ${esc(row.status)}</strong><small>${row.endedAt?new Date(Number(row.endedAt)*1000).toLocaleString():'In progress'} · Army ${Number(row.armyPercent||0)}% · Gangs ${Number(row.gangPercent||0)}% · Lost ${Number(row.lostPercent||0)}%</small><details><summary>VIEW DETAILS</summary><small>Reference ${esc(row.eventId)} · ${esc(row.reason||'No result reason')}</small><small>Incoming ${Number(row.totalValue||0).toLocaleString()} value · Army ${Number(row.armyValue||0).toLocaleString()} · Gangs ${Number(row.gangValue||0).toLocaleString()} · Lost ${Number(row.lostValue||0).toLocaleString()}</small><small>${(row.standings||[]).map(g=>`${esc(String(g.gang_id||g.gangId||'').toUpperCase())}: ${Number(g.percent||0)}%`).join(' · ')||'No gang extraction'}</small></details></div></article>`).join('')||'<p>No Arsenal history.</p>'}
document.querySelector('#logisticsOrderForm').onsubmit=async e=>{e.preventDefault();const r=await post('logisticsCreate',{lines:[{itemName:document.querySelector('#logisticsItem').value,quantity:Number(document.querySelector('#logisticsQuantity').value||0)}]});notice(r.message||r.error,r.ok?'success':'error');if(r.ok)loadLogistics()};
document.querySelector('#logisticsOrders').onclick=async e=>{const b=e.target.closest('[data-logistics-action]');if(!b)return;const r=await post('logisticsAction',{action:b.dataset.logisticsAction,orderId:Number(b.dataset.orderId)});notice(r.message||r.error,r.ok?'success':'error');if(r.ok)loadLogistics()};
const pageTitles={overview:'Overview',roster:'Members',ranks:'Ranks & Access',facilities:'Facilities',fleet:'Fleet Vehicles',logs:'Activity Logs',dispatch:'Dispatch',mdt:'Shared MDT',logistics:'Logistics'};
document.querySelectorAll('.tab').forEach(b=>b.onclick=()=>{document.querySelectorAll('.tab').forEach(x=>x.classList.remove('active'));b.classList.add('active');document.querySelectorAll('.view').forEach(x=>x.classList.add('hidden'));document.querySelector(`#${b.dataset.tab}View`).classList.remove('hidden');document.querySelector('#pageTitle').textContent=pageTitles[b.dataset.tab]||b.dataset.tab;if(b.dataset.tab==='dispatch'){loadDispatchActiveCalls();loadDispatchHistory()}if(b.dataset.tab==='fleet')loadFleet();if(b.dataset.tab==='logs')loadActivityLog();if(b.dataset.tab==='logistics'){loadLogistics();loadArsenalHistory()}});
document.querySelector('#arsenalHistoryRefresh')?.addEventListener('click',loadArsenalHistory);
roster.onclick=async e=>{const b=e.target.closest('[data-action]');if(!b)return;const action=b.dataset.action,cid=b.dataset.cid;if(action==='fire'&&!confirm('Remove this member from the organization?'))return;const rank=roster.querySelector(`[data-rank="${CSS.escape(cid)}"]`);const r=await post('staffAction',{action,characterId:cid,rankId:rank?Number(rank.value):null});notice(r.message||r.error,r.ok?'success':'error')};

async function refresh(){ const data = await post('refresh'); if (data && data.ok !== false) render(data); }
const facilityPrompt=document.querySelector('#facilityPrompt'),facilityDialogue=document.querySelector('#facilityDialogue');
window.addEventListener('message',e=>{const d=e.data||{};if(d.action==='facilityPrompt'){facilityPrompt.classList.toggle('hidden',!d.visible);document.querySelector('#facilityPromptText').textContent=d.name?`${d.name} · ${d.role||''}`:''}if(d.action==='facilityDialogue'){facilityDialogue.className=`npc-dialogue${d.visible?'':' hidden'}`;if(d.visible){document.querySelector('#facilityName').textContent=d.name||'';document.querySelector('#facilityRole').textContent=d.role||'';document.querySelector('#facilityQuote').textContent=d.quote||'';document.querySelector('#facilitySignature').textContent=`— ${d.name||''}`;document.querySelector('#facilityContinue').textContent=d.continueLabel||'Continue'}}if(d.action==='facilityDialogueResponse'){facilityDialogue.className=`npc-dialogue response ${d.tone||'inform'}`;document.querySelector('#facilityQuote').textContent=d.message||''}});
document.querySelector('#facilityContinue').onclick=()=>post('facilityDialogueContinue');
document.querySelector('#facilityClose').onclick=()=>post('facilityDialogueClose');
const facilityOptions=document.querySelector('#facilityOptions');
window.addEventListener('message',e=>{const d=e.data||{};if(d.action==='facilityDialogue'){facilityOptions.classList.add('hidden');facilityOptions.innerHTML=''}if(d.action==='facilityDialogueChoices'){facilityDialogue.className='npc-dialogue services';document.querySelector('#facilityQuote').textContent=d.message||'How can I help you?';facilityOptions.innerHTML=(d.choices||[]).map(x=>`<button class="npc-dialogue__option ${x.primary?'npc-dialogue__option--primary':''}" data-facility-service="${esc(x.id)}">${esc(x.label)}${x.description?`<small>${esc(x.description)}</small>`:''}</button>`).join('');facilityOptions.classList.remove('hidden')}if(d.action==='facilityDialogueResponse')facilityOptions.classList.add('hidden')});
facilityOptions.onclick=e=>{const b=e.target.closest('[data-facility-service]');if(b)post('facilityPublicService',{service:b.dataset.facilityService})};

const wardrobe=document.querySelector('#wardrobeRoom');let wardrobeItems=[],wardrobeCategory='',wardrobeOption=0,wardrobeColor=0;
const categoryNames={torso:'Outerwear',pants:'Pants',shoes:'Shoes',tshirt:'Shirts',chains:'Accessories',bags:'Bags',hat:'Headwear',glasses:'Glasses',earrings:'Earrings',watches:'Watches'};
function wardrobeRows(){return wardrobeItems.filter(x=>(x.category||'other')===wardrobeCategory)}
function wardrobeDrawables(){const map=new Map();wardrobeRows().forEach(x=>{const k=Number(x.drawableId);if(!map.has(k))map.set(k,x)});return [...map.values()]}
function wardrobeTextures(drawable){return wardrobeRows().filter(x=>Number(x.drawableId)===Number(drawable))}
function wardrobeRender(){const cats=[...new Set(wardrobeItems.map(x=>x.category||'other'))];document.querySelector('#wardrobeCategories').innerHTML=cats.map(x=>`<button class="${x===wardrobeCategory?'active':''}" data-legal-category="${esc(x)}">${esc(categoryNames[x]||x)}</button>`).join('');const options=wardrobeDrawables(),item=options[wardrobeOption];if(!item){document.querySelector('#wardrobeOption').textContent='--';document.querySelector('#wardrobeColor').textContent='--';return}const colors=wardrobeTextures(item.drawableId),color=colors[wardrobeColor]||colors[0];document.querySelector('#wardrobeOption').textContent=`${item.label||`Option ${item.drawableId}`} · ${wardrobeOption+1}/${options.length}`;document.querySelector('#wardrobeColor').textContent=`Color ${wardrobeColor+1}/${colors.length}`;if(color)post('legalWardrobePreview',color)}
function wardrobeMoveOption(delta){const rows=wardrobeDrawables();if(!rows.length)return;wardrobeOption=(wardrobeOption+delta+rows.length)%rows.length;wardrobeColor=0;wardrobeRender()}
function wardrobeMoveColor(delta){const item=wardrobeDrawables()[wardrobeOption];if(!item)return;const rows=wardrobeTextures(item.drawableId);wardrobeColor=(wardrobeColor+delta+rows.length)%rows.length;wardrobeRender()}
window.addEventListener('message',e=>{const d=e.data||{};if(d.action==='legalWardrobeOpen'){app.classList.add('hidden');facilityDialogue.classList.add('hidden');facilityPrompt.classList.add('hidden');wardrobeItems=d.items||[];const priority=['torso','pants','shoes','tshirt','chains','bags','hat','glasses','earrings','watches'];const cats=[...new Set(wardrobeItems.map(x=>x.category||'other'))].sort((a,b)=>(priority.indexOf(a)<0?99:priority.indexOf(a))-(priority.indexOf(b)<0?99:priority.indexOf(b)));wardrobeCategory=cats[0]||'';wardrobeOption=0;wardrobeColor=0;document.querySelector('#wardrobeOrg').textContent=d.label||'LEGAL ORGANIZATION';wardrobe.classList.remove('hidden');wardrobeRender()}if(d.action==='legalWardrobeClose')wardrobe.classList.add('hidden')});
document.querySelector('#wardrobeCategories').onclick=e=>{const b=e.target.closest('[data-legal-category]');if(b){wardrobeCategory=b.dataset.legalCategory;wardrobeOption=0;wardrobeColor=0;wardrobeRender()}};document.querySelector('#wardrobePrev').onclick=()=>wardrobeMoveOption(-1);document.querySelector('#wardrobeNext').onclick=()=>wardrobeMoveOption(1);document.querySelector('#wardrobeColorPrev').onclick=()=>wardrobeMoveColor(-1);document.querySelector('#wardrobeColorNext').onclick=()=>wardrobeMoveColor(1);document.querySelector('#wardrobeDone').onclick=()=>post('legalWardrobeDone');document.querySelector('#wardrobeCancel').onclick=()=>post('legalWardrobeCancel');
(()=>{let drag=false,last=0;const view=document.querySelector('#wardrobeViewport');view.onmousedown=e=>{drag=true;last=e.clientX};window.addEventListener('mouseup',()=>drag=false);window.addEventListener('mousemove',e=>{if(!drag)return;const dx=e.clientX-last;last=e.clientX;post('legalWardrobeRotate',{delta:-dx*.45})})})();
document.addEventListener('keydown',e=>{if(wardrobe.classList.contains('hidden'))return;if(e.key==='w'||e.key==='W')wardrobeMoveOption(-1);if(e.key==='s'||e.key==='S')wardrobeMoveOption(1);if(e.key==='a'||e.key==='A')post('legalWardrobeRotate',{delta:-8});if(e.key==='d'||e.key==='D')post('legalWardrobeRotate',{delta:8})});

// Organization armory: server-authoritative catalog, stock and checkout.
const legalArmory=document.querySelector('#legalArmory'),armoryManager=document.querySelector('#armoryManager');
let armoryData=null,armoryFilter='all',armoryManagement=[];
function armoryImage(item){return item.image?`<img src="${esc(item.image)}" alt="">`:'<span>NO IMAGE</span>'}
function renderArmory(){
  const allRows=armoryData?.items||[],rows=allRows.filter(x=>(armoryFilter!=='all'||x.itemType!=='vest')&&(armoryFilter==='all'||x.itemType===armoryFilter));
  document.querySelector('#armoryManage').classList.toggle('hidden',armoryData?.canManage!==true);
  for(const type of ['all','weapon','ammo','vest']){const node=document.querySelector(`#lawArmoryCount${type[0].toUpperCase()}${type.slice(1)}`);if(node)node.textContent=type==='all'?allRows.length:allRows.filter(item=>item.itemType===type).length}
  const card=item=>{
    const ratio=item.maxStock?item.stock/item.maxStock:0,stockClass=item.stock<=0?'empty':ratio<=.2?'low':'',unit=item.itemType==='ammo'?'ROUNDS':'PCS';
    return `<article class="armory-card"><div class="armory-card__image">${armoryImage(item)}<span><i></i>${esc(item.label)}</span></div><div class="armory-card__body"><small>${esc(item.itemType)}</small><h3>${esc(item.label)}</h3><p>${esc(item.description||'Department-issued equipment')}</p><label>IN VAULT</label><strong class="armory-vault-count">${Number(item.stock||0).toLocaleString()} <small>${unit}</small></strong><div class="armory-stock-line"><i style="width:${Math.max(0,Math.min(100,ratio*100))}%"></i></div><div class="armory-stock ${stockClass}"><span>CAPACITY ${Number(item.maxStock||0).toLocaleString()}</span><span>ISSUE ${Number(item.issueAmount||1)} ${unit}</span></div><button data-armory-checkout="${esc(item.itemName)}" ${item.available?'':'disabled'}>${item.available?'TAKE EQUIPMENT':item.stock<item.issueAmount?'OUT OF STOCK':'RANK RESTRICTED'}</button></div></article>`;
  };
  document.querySelector('#armoryGrid').innerHTML=rows.map(card).join('')||'<p>No equipment is enabled in this category.</p>';
  const armor=allRows.filter(item=>item.itemType==='vest');document.querySelector('#lawArmorCount').textContent=`${armor.length} MODELS`;document.querySelector('#lawArmorList').innerHTML=armor.map(card).join('')||'<div class="legal-armory__armor-empty"><strong>NO ARMOR CONFIGURED</strong><span>Protective equipment will appear here when enabled.</span></div>';
}
function renderArmoryManagement(){
  document.querySelector('#armoryManagerGrid').innerHTML=armoryManagement.map(item=>`<article class="armory-manage-row" data-armory-item="${esc(item.itemName)}"><div class="armory-manage-row__item">${item.image?`<img src="${esc(item.image)}" alt="">`:''}<div><strong>${esc(item.label)}</strong><small>${esc(item.itemType)} · ${esc(item.itemName)} · this organization: ${Number(item.stock||0)} in stock</small></div></div><label>Show in every organization<input data-field="enabled" type="checkbox" ${item.enabled?'checked':''}></label><button data-armory-save>Save catalogue</button></article>`).join('');
}
window.addEventListener('message',e=>{const d=e.data||{};if(d.action==='legalArmoryOpen'){app.classList.add('hidden');facilityDialogue.classList.add('hidden');facilityPrompt.classList.add('hidden');const label=d.label||'LEGAL ORGANIZATION';document.querySelector('#armoryOrg').textContent=label;document.querySelector('#armoryRailOrg').textContent=label;armoryData=d.data||{items:[]};armoryFilter='all';document.querySelectorAll('[data-armory-filter]').forEach(x=>x.classList.toggle('active',x.dataset.armoryFilter==='all'));legalArmory.classList.remove('hidden');armoryManager.classList.add('hidden');renderArmory()}if(d.action==='legalArmoryClose'){legalArmory.classList.add('hidden');armoryManager.classList.add('hidden')}});
document.querySelector('#armoryClose').onclick=()=>post('legalArmoryClose');
document.querySelector('#armoryFilters').onclick=e=>{const b=e.target.closest('[data-armory-filter]');if(!b)return;armoryFilter=b.dataset.armoryFilter;document.querySelectorAll('[data-armory-filter]').forEach(x=>x.classList.toggle('active',x===b));renderArmory()};
document.querySelector('#armoryGrid').onclick=async e=>{const b=e.target.closest('[data-armory-checkout]');if(!b)return;b.disabled=true;const r=await post('legalArmoryCheckout',{itemName:b.dataset.armoryCheckout});notice(r.message||r.error,r.ok?'success':'error');if(r.ok&&r.armory){armoryData=r.armory;renderArmory()}else{const fresh=await post('legalArmoryRefresh');if(fresh?.ok){armoryData=fresh;renderArmory()}}};
document.querySelector('#lawArmorList').onclick=e=>document.querySelector('#armoryGrid').onclick(e);
document.querySelector('#armoryManage').onclick=async()=>{const r=await post('legalArmoryManagement');if(!r?.ok)return notice(r?.error||'Management unavailable.','error');armoryManagement=r.items||[];renderArmoryManagement();armoryManager.classList.remove('hidden')};
document.querySelector('#armoryManagerClose').onclick=async()=>{armoryManager.classList.add('hidden');const r=await post('legalArmoryRefresh');if(r?.ok){armoryData=r;renderArmory()}};
document.querySelector('#armoryManagerGrid').onclick=async e=>{const b=e.target.closest('[data-armory-save]');if(!b)return;const row=b.closest('[data-armory-item]');const data={itemName:row.dataset.armoryItem,enabled:row.querySelector('[data-field="enabled"]').checked};b.disabled=true;const r=await post('legalArmorySave',data);b.disabled=false;notice(r.message||r.error,r.ok?'success':'error');if(r.ok){const fresh=await post('legalArmoryManagement');armoryManagement=fresh.items||armoryManagement;renderArmoryManagement()}};
document.querySelector('#armoryLoadStock').onclick=async()=>{const button=document.querySelector('#armoryLoadStock');button.disabled=true;const r=await post('legalArmoryLoadStock');button.disabled=false;notice(r.message||r.error,r.ok?'success':'error');if(r.ok){const fresh=await post('legalArmoryManagement');armoryManagement=fresh.items||armoryManagement;renderArmoryManagement()}};

// Shared legal MDT
let lawMdtProfile=null;
const mdtResults=document.querySelector('#lawMdtResults'),mdtWorkspace=document.querySelector('#lawMdtWorkspace');
function mdtList(rows,renderer,empty){return (rows||[]).map(renderer).join('')||`<p class="hint">${esc(empty)}</p>`}
function renderLawMdtProfile(profile){
  lawMdtProfile=profile;const cid=esc(profile.characterId),wanted=profile.wanted;
  mdtWorkspace.innerHTML=`<section class="law-mdt-profile"><header class="law-mdt-profile__head"><div><small>CITIZEN ${cid}</small><h2>${esc(profile.name)}</h2></div><span class="badge ${wanted?'suspended':'on'}">${wanted?`${profile.stars} STAR WANTED`:'NOT WANTED'}</span></header>
  <div class="law-mdt-actions"><label>Stars<input id="lawMdtStars" type="number" min="0" max="5" value="${Number(profile.stars||0)}"></label><label>Wanted reason<input id="lawMdtWantedReason" maxlength="160" value="${esc(profile.wantedReason||'')}"></label><button data-mdt-wanted>Update wanted</button></div>
  <div class="law-mdt-columns"><article class="card"><small>LICENCES</small>${mdtList(profile.licenses,x=>`<div class="mdt-record"><strong>${esc(x.license_type)}</strong><span>${esc(x.status)}${x.license_number?` · ${esc(x.license_number)}`:''}</span></div>`,'No licence records')}</article><article class="card"><small>REGISTERED VEHICLES</small>${mdtList(profile.vehicles,x=>`<button class="mdt-record mdt-record--button" data-mdt-plate="${esc(x.plate)}"><strong>${esc(x.plate)}</strong><span>${esc(x.label||x.model)}${x.licenseNumber?` · ${esc(x.licenseNumber)}`:''}</span></button>`,'No vehicles')}</article></div>
  <div class="law-mdt-compose"><textarea id="lawMdtNote" maxlength="1000" placeholder="Shared agency note"></textarea><button data-mdt-note>Add note</button></div>
  <article class="card"><small>SHARED NOTES</small>${mdtList(profile.notes,x=>`<div class="mdt-record"><strong>${esc(x.organization_id).toUpperCase()} · ${esc(x.author_name||x.author_cid)}</strong><span>${esc(x.note)}</span><time>${esc(x.created_at)}</time></div>`,'No notes')}</article>
  <div class="law-mdt-compose law-mdt-compose--report"><input id="lawMdtReportTitle" maxlength="120" placeholder="Report title"><textarea id="lawMdtReportNarrative" maxlength="6000" placeholder="Detailed incident narrative"></textarea><button data-mdt-report>Create report</button></div>
  <article class="card"><small>SHARED REPORTS</small>${mdtList(profile.reports,x=>`<details class="mdt-record"><summary><strong>#${x.id} · ${esc(x.title)}</strong> <span>${esc(x.organization_id).toUpperCase()} · ${esc(x.status)}</span></summary><p>${esc(x.narrative)}</p><time>${esc(x.created_at)}</time></details>`,'No reports')}</article>
  <div class="law-mdt-compose law-mdt-warrant-compose"><input id="lawMdtWarrantReason" maxlength="1000" placeholder="Warrant reason"><input id="lawMdtWarrantStars" type="number" min="1" max="5" value="1"><button data-mdt-warrant>Create warrant</button></div>
  <article class="card"><small>SHARED WARRANTS</small>${mdtList(profile.warrants,x=>`<div class="mdt-record"><strong>#${x.id} · ${esc(x.organization_id).toUpperCase()} · ${x.stars} star</strong><span>${esc(x.reason)}</span><time>${esc(x.created_at)}</time>${x.status==='active'?`<button data-mdt-close-warrant="${x.id}">Close warrant</button>`:`<em>${esc(x.status)}</em>`}</div>`,'No warrants')}</article>
  <article class="card"><small>SHARED LEGAL BOOKING HISTORY</small>${mdtList(profile.legalBookings,x=>`<div class="mdt-record"><strong>${esc(x.organization_id)} booking #${x.id} · ${Number(x.sentence_minutes||0)} minutes</strong><span>${esc((x.charges||[]).map(c=>c.label).join(', ')||'No charges')} · ${esc(x.reason||'No reason')} · ${esc(x.handoff_status||'unknown')}</span><time>${esc(x.booked_at||'')}</time></div>`,'No shared legal bookings')}</article>
  <div class="law-mdt-columns"><article class="card"><small>CITATION HISTORY</small>${mdtList(profile.citations,x=>`<div class="mdt-record"><strong>${esc(x.violation_label||'Citation')} · $${Number(x.fine||0).toLocaleString()}</strong><time>${esc(x.created_at||'')}</time></div>`,'No citations')}</article><article class="card"><small>POLICE BOOKING HISTORY</small>${mdtList(profile.bookings,x=>`<div class="mdt-record"><strong>Booking #${x.id} · ${Number(x.wanted_stars||0)} stars</strong><span>${esc(x.reason||'No reason')} · ${Number(x.sentence_minutes||0)} minutes · ${esc(x.handoff_status||'unknown')}</span><time>${esc(x.booked_at||'')}</time></div>`,'No police bookings')}</article></div></section>`;
}
async function loadLawMdtProfile(characterId){const r=await post('lawMdtCitizenProfile',{characterId});if(!r?.ok)return notice(r?.error||'Profile unavailable.','error');renderLawMdtProfile(r.profile)}
document.querySelector('#lawMdtCitizenSearch').onclick=async()=>{const r=await post('lawMdtSearchCitizens',{query:document.querySelector('#lawMdtCitizenQuery').value});if(!r?.ok)return notice(r?.error||'Search failed.','error');mdtResults.innerHTML=mdtList(r.citizens,x=>`<button class="law-mdt-result" data-mdt-cid="${esc(x.characterId)}"><strong>${esc(x.name)}</strong><span>CID ${esc(x.characterId)}${x.wanted?` · ${x.stars} STAR WANTED`:''}</span></button>`,'No citizens found')};
document.querySelector('#lawMdtVehicleSearch').onclick=async()=>{const r=await post('lawMdtVehicleSearch',{plate:document.querySelector('#lawMdtPlateQuery').value});if(!r?.ok)return notice(r?.error||'Vehicle not found.','error');const v=r.vehicle;mdtWorkspace.innerHTML=`<article class="card law-mdt-vehicle"><small>VEHICLE RECORD</small><h2>${esc(v.plate)}</h2><p>${esc(v.label||v.model)}</p><div class="mdt-record"><strong>Owner</strong><span>${esc(v.ownerName)}${v.ownerCid?` · CID ${esc(v.ownerCid)}`:''}</span></div><div class="mdt-record"><strong>Registration</strong><span>${esc(v.licenseNumber||'UNLICENSED')}</span></div><div class="mdt-record"><strong>Impound</strong><span>${v.impound?`${esc(v.impound.reason)} · $${Number(v.impound.fee||0).toLocaleString()}`:'Not impounded'}</span></div>${v.ownerCid?`<button data-mdt-cid="${esc(v.ownerCid)}">Open owner profile</button>`:''}</article>`};
mdtResults.onclick=e=>{const b=e.target.closest('[data-mdt-cid]');if(b)loadLawMdtProfile(b.dataset.mdtCid)};
mdtWorkspace.onclick=async e=>{const cidButton=e.target.closest('[data-mdt-cid]'),plateButton=e.target.closest('[data-mdt-plate]');if(cidButton)return loadLawMdtProfile(cidButton.dataset.mdtCid);if(plateButton){document.querySelector('#lawMdtPlateQuery').value=plateButton.dataset.mdtPlate;return document.querySelector('#lawMdtVehicleSearch').click()}if(!lawMdtProfile)return;const cid=lawMdtProfile.characterId;let r;if(e.target.closest('[data-mdt-wanted]'))r=await post('lawMdtSetWanted',{characterId:cid,stars:Number(document.querySelector('#lawMdtStars').value),reason:document.querySelector('#lawMdtWantedReason').value});if(e.target.closest('[data-mdt-note]'))r=await post('lawMdtAddNote',{characterId:cid,note:document.querySelector('#lawMdtNote').value});if(e.target.closest('[data-mdt-report]'))r=await post('lawMdtCreateReport',{characterId:cid,title:document.querySelector('#lawMdtReportTitle').value,narrative:document.querySelector('#lawMdtReportNarrative').value});if(e.target.closest('[data-mdt-warrant]'))r=await post('lawMdtCreateWarrant',{characterId:cid,stars:Number(document.querySelector('#lawMdtWarrantStars').value),reason:document.querySelector('#lawMdtWarrantReason').value});const close=e.target.closest('[data-mdt-close-warrant]');if(close)r=await post('lawMdtCloseWarrant',{warrantId:Number(close.dataset.mdtCloseWarrant)});if(r){notice(r.message||r.error,r.ok?'success':'error');if(r.ok)loadLawMdtProfile(cid)}};

document.querySelector('#memberMap').onclick=async()=>{
  const button=document.querySelector('#memberMap');
  const r=await post('toggleMemberMap',{});
  if(!r||r.ok===false){notice('Your rank cannot view members on the map.','error');return}
  const on=button.classList.toggle('is-active');
  button.textContent=on?'Member map: on':'Member map';
};
document.querySelector('#meetingPoint').onclick=async()=>{
  // One click routes every online member of this organization to your
  // position, so make it deliberate.
  if(!confirm('Set the meeting point at your current position? Every online member of your organization gets a map route to it.'))return;
  const r=await post('setMeetingPoint',{});
  notice(r.message||r.error,r.ok?'success':'error');
};
document.querySelector('#clearMeeting').onclick=async()=>{
  if(!confirm('Clear the meeting point for everyone in your organization?'))return;
  const r=await post('setMeetingPoint',{clear:true});
  notice(r.message||r.error,r.ok?'success':'error');
};
