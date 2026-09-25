const app=document.querySelector('#app'),roster=document.querySelector('#roster'),toast=document.querySelector('#toast');let state=null,facilityOnly=false;
const res=typeof GetParentResourceName==='function'?GetParentResourceName():'cm-law';
const previewParams=new URLSearchParams(location.search);const previewOrg=String(previewParams.get('preview')||'').toLowerCase();const previewMode=['lspd','sheriff','sahp','fib','army'].includes(previewOrg);
const post=async(name,data={})=>{if(previewMode)return{ok:false,error:'Preview mode is read-only.'};if(window.cmRequest)return window.cmRequest(`https://${res}/${name}`,data);try{const r=await fetch(`https://${res}/${name}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});if(!r.ok)return{ok:false,error:`Request failed (${r.status}).`};return await r.json()}catch(_){return{ok:false,error:'The organization terminal did not respond.'}}};
// Shared booking review. It is intentionally outside the dashboard lifecycle so
// the same intake form works from the player interaction menu while F6 is closed.
const bookingPanel=document.querySelector('#bookingPanel');let bookingData=null,bookingBusy=false;
function renderBooking(data){
  bookingData=data||{}; bookingBusy=false; bookingPanel?.classList.remove('is-busy'); if(!bookingPanel)return;
  bookingPanel.hidden=false; document.querySelector('#bookingTitle').textContent=`Book ${data.suspectName||'Suspect'}`;
  document.querySelector('#bookingSuspectMeta').textContent=`Suspect · CID ${data.characterId||'—'} · Shared prison intake`;
  const charges=document.querySelector('#bookingCharges'); const max=Number(data.maxCharges||10);
  charges.innerHTML=(data.charges||[]).map(c=>`<label class="booking-charge"><input type="checkbox" value="${esc(c.id)}" data-booking-charge><span><strong>${esc(c.label)}</strong><small>${Number(c.jailMinutes||0)} minute${Number(c.jailMinutes||0)===1?'':'s'}${Number(c.fine||0)>0?` · $${Number(c.fine).toLocaleString()} fine`:''}</small></span></label>`).join('')||'<p class="hint">No charge catalogue is available.</p>';
  document.querySelector('#bookingChargeCount').textContent=`0 / ${max}`;document.querySelector('#bookingMinutes').textContent='0 min';document.querySelector('#bookingSummaryText').textContent='Select at least one charge.';document.querySelector('#bookingReason').value='';document.querySelector('#bookingReasonCount').textContent='0';document.querySelector('#bookingStatus').textContent='';
}
function closeBooking(){if(!bookingPanel||bookingPanel.hidden)return;bookingPanel.hidden=true;bookingData=null;bookingBusy=false;bookingPanel.classList.remove('is-busy');post('bookingClose')}
function updateBookingPreview(){
  const selected=[...document.querySelectorAll('[data-booking-charge]:checked')],max=Number(bookingData?.maxCharges||10),lookup=new Map((bookingData?.charges||[]).map(c=>[String(c.id),c]));
  const minutes=selected.reduce((sum,n)=>sum+Number(lookup.get(n.value)?.jailMinutes||0),0);
  const fine=selected.reduce((sum,n)=>sum+Number(lookup.get(n.value)?.fine||0),0);
  document.querySelector('#bookingChargeCount').textContent=`${selected.length} / ${max}`;document.querySelector('#bookingMinutes').textContent=fine>0?`${minutes} min · $${fine.toLocaleString()} fine`:`${minutes} min`;document.querySelector('#bookingSummaryText').textContent=selected.length?`${selected.length} charge${selected.length===1?'':'s'} selected · server will verify before custody transfer`:'Select at least one charge.';selected.forEach(n=>n.closest('.booking-charge')?.classList.toggle('is-selected',true));
}
document.querySelector('#bookingCharges')?.addEventListener('change',updateBookingPreview);document.querySelector('#bookingReason')?.addEventListener('input',e=>document.querySelector('#bookingReasonCount').textContent=e.target.value.length);document.querySelector('#bookingClose')?.addEventListener('click',closeBooking);document.querySelector('#bookingCancel')?.addEventListener('click',closeBooking);
document.querySelector('#bookingSubmit')?.addEventListener('click',async()=>{if(!bookingData||bookingBusy)return;const chargeIds=[...document.querySelectorAll('[data-booking-charge]:checked')].map(n=>n.value),reason=document.querySelector('#bookingReason').value.trim();if(!chargeIds.length)return document.querySelector('#bookingStatus').textContent='Select at least one charge.';if(reason.length<5)return document.querySelector('#bookingStatus').textContent='Enter a clear arrest reason.';bookingBusy=true;bookingPanel.classList.add('is-busy');document.querySelector('#bookingStatus').textContent='Verifying custody and transferring to prison…';const result=await post('bookingSubmit',{targetServerId:bookingData.targetServerId,chargeIds,reason});if(result?.ok){document.querySelector('#bookingStatus').textContent='Booking confirmed.';setTimeout(closeBooking,650)}else{bookingBusy=false;bookingPanel.classList.remove('is-busy');document.querySelector('#bookingStatus').textContent=result?.error||'Booking failed; the suspect remains cuffed.'}});
// Native window.confirm()/confirm() never render in FiveM's NUI CEF (no JS
// dialog handler is registered), so it returns false immediately without
// showing anything -- every guarded action below would silently do nothing.
// This overlay replaces it. Queued so a second call before the first
// resolves waits its turn instead of orphaning the first caller's promise.
let lawConfirmQueue=Promise.resolve();
function showConfirmOverlay(title,message,yesLabel='Confirm',noLabel='Cancel',options={}){
  if (window.CMUI && typeof window.CMUI.confirm === 'function') {
    const isDanger = /delete|fire|suspend|kick|recall|reset|clear|remove|close|panic/i.test(`${title} ${yesLabel}`);
    return window.CMUI.confirm({
      title: (title || 'CONFIRM').toUpperCase(),
      message: message || 'Are you sure you want to proceed?',
      confirmText: (yesLabel || 'CONFIRM').toUpperCase(),
      cancelText: (noLabel || 'CANCEL').toUpperCase(),
      danger: isDanger,
      dismissOnBackdrop: options.dismissOnBackdrop !== false && !isDanger ? true : false,
      ...options
    });
  }
  const overlay=document.getElementById('lawConfirm');
  if (!overlay) return Promise.resolve(false);
  const run=()=>new Promise(resolve=>{
    document.getElementById('lawConfirmTitle').textContent=title||'Confirm';
    document.getElementById('lawConfirmMessage').textContent=message||'Are you sure?';
    const yesBtn=document.getElementById('lawConfirmYes'),noBtn=document.getElementById('lawConfirmNo');
    yesBtn.textContent=yesLabel;noBtn.textContent=noLabel;
    overlay.hidden=false;
    const cleanup=result=>{overlay.hidden=true;yesBtn.onclick=null;noBtn.onclick=null;resolve(result)};
    yesBtn.onclick=()=>cleanup(true);
    noBtn.onclick=()=>cleanup(false);
  });
  const result=lawConfirmQueue.then(run);
  lawConfirmQueue=result;
  return result;
}
function notice(message,kind='success'){toast.textContent=message||'';toast.className=`show ${kind}`;clearTimeout(notice.timer);notice.timer=setTimeout(()=>toast.className='',2600)}
function formatTerminalTime(value){const raw=String(value??'').trim();if(!raw)return'';const numeric=Number(raw.replace(/[^0-9.+-]/g,''));const date=Number.isFinite(numeric)&&numeric>0?new Date(numeric>1e12?numeric:numeric>1e9?numeric*1000:numeric):new Date(raw);return Number.isNaN(date.getTime())?raw:date.toLocaleString([], {month:'short',day:'2-digit',hour:'2-digit',minute:'2-digit'})}
const orgBranding={
  lspd:{logo:'police/assets/org/lspd.svg',banner:'police/assets/org/lspd-banner.svg',art:'police/assets/org/lspd-officer.png',mark:'LSPD',label:'Los Santos Police Department',shortLabel:'LSPD',jurisdiction:'Los Santos and state law enforcement coverage',color:'#2D7FF9'},
  sahp:{logo:'assets/org/sahp.svg',banner:'assets/org/sahp-banner.svg',art:'assets/org/sahp-officer.png',mark:'SAHP',label:'San Andreas Highway Patrol',shortLabel:'SAHP',jurisdiction:'State highway patrol coverage'},
  sheriff:{logo:'assets/org/sheriff.svg',banner:'assets/org/sheriff-banner.svg',art:'assets/org/sheriff-officer.png',mark:'BCSO',label:"Blaine County Sheriff's Office",shortLabel:'BCSO',jurisdiction:'Blaine County and county contract areas'},
  fib:{logo:'assets/org/fib.svg',banner:'assets/org/fib-banner.svg',art:'assets/org/fib-agent.png',mark:'FIB',label:'Federal Investigation Bureau',shortLabel:'FIB',jurisdiction:'Federal investigations and intelligence'},
  army:{logo:'assets/org/army.svg',banner:'assets/org/army-banner.svg',art:'assets/org/army-soldier.png',mark:'ARMY',label:'San Andreas Army',shortLabel:'ARMY',jurisdiction:'Military support and controlled deployments'},
  default:{logo:'assets/org/default.svg',banner:'assets/org/default-banner.svg',art:'assets/org/default-officer.png',mark:'LAW',label:'Legal Organization',shortLabel:'LEGAL ORGANIZATION',jurisdiction:'Authorized jurisdiction'}
};
function previewPayload(id){
  const profile=orgProfile({id});
  const names=['Alex Mercer','Jordan Wells','Maya Ortiz','Riley Chen','Taylor Brooks','Samira Cole','Noah Grant','Casey Reed'];
  const roster=names.map((name,index)=>({character_id:`${4200+index}`,name,rank_id:index===0?1:2,rank_name:index===0?'Chief':'Officer',tier:index===0?5:2,on_duty:index<5,suspended:false,is_leader:index===0,photo_url:''}));
  return {ok:true,organization:{id,label:profile.label,shortLabel:profile.shortLabel,color:profile.color||'#00E5FF',jurisdiction:profile.jurisdiction,leaderCid:'4200',leaderName:'Alex Mercer'},characterId:'4201',member:{characterId:'4201',rankName:'Officer',tier:2,isLeader:false,onDuty:true,suspended:false,permissions:{'law.view_members':true,'law.receive_dispatch':true,'law.mdt':true},capabilities:{dispatch:true,mdt:true,fleet:true,armory:true,arrest:true,search:true,citations:true,prisonIntake:true}},roster,ranks:[{id:1,name:'Chief',tier:5,is_leader:true,permissions:{}},{id:2,name:'Officer',tier:2,is_leader:false,permissions:{'law.view_members':true}}],summary:{memberCount:8,onDutyCount:5,fleetConfigured:12,fleetAvailable:8,activeCalls:3,assignedCalls:1,priorityCall:{id:1,callerName:'Dispatch',details:'Officer assistance requested',location:'Mission Row',priority:3,createdAt:Date.now()/1000}},canViewMembers:true,canManage:true,canManageRanks:true,canManagePermissions:false,canInspectRankPermissions:true,canDispatch:true,canMdt:true,canCustody:true,canFleetManage:true,canFleetSpawn:true,logisticsVisible:id==='army',logistics:{canRequest:id==='army'},canManageCharges:true,canViewActivity:true,recentActivity:[{id:1,actorName:'Alex Mercer',action:'duty_started',createdAt:'Just now',detail:{}}],prison:{ready:true,configured:true,intakeConfigured:true,releaseConfigured:true,spawnCount:12,capacity:48,activeCount:9},facilities:{},facilityTypes:{}};
}
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
  const dispatchTab=document.querySelector('#dispatchTab');if(dispatchTab)dispatchTab.classList.toggle('hidden',data.canDispatch!==true);
  const mdtTab=document.querySelector('#mdtTab');if(mdtTab)mdtTab.classList.toggle('hidden',data.canMdt!==true);
  const ranksTab=document.querySelector('#ranksTab');if(ranksTab)ranksTab.classList.toggle('hidden',data.canInspectRankPermissions!==true && data.canManageRanks!==true);
  const dutyButton=document.querySelector('#dashboardDutyButton');
  if(dutyButton){dutyButton.hidden=data.source==='cm-police';dutyButton.textContent=m.onDuty?'End duty':'Off duty';dutyButton.disabled=m.onDuty!==true;dutyButton.classList.toggle('is-on',m.onDuty===true)}
  const capturePhoto=document.querySelector('#overviewCapturePhoto');if(capturePhoto)capturePhoto.hidden=data.source==='cm-police';
  const logsAllowed = data.canManage || data.canViewActivity === true;
  const logsTab=document.querySelector('#logsTab'); if(logsTab) logsTab.classList.toggle('hidden',!logsAllowed);
  const custodyTab=document.querySelector('#custodyTab'); if(custodyTab) custodyTab.classList.toggle('hidden',data.canCustody!==true);
  const fleetTab=document.querySelector('#fleetTab'); if(fleetTab) fleetTab.classList.toggle('hidden',data.canFleetUse!==true && data.canFleetSpawn!==true && data.canFleetManage!==true);
  const logisticsTab=document.querySelector('#logisticsTab'); if(logisticsTab) logisticsTab.classList.toggle('hidden',data.logisticsVisible!==true);
  const chargesTab=document.querySelector('#chargesTab'); if(chargesTab) chargesTab.classList.toggle('hidden',data.canManageCharges!==true);
  const ranks=(data.ranks||[]).filter(r=>!r.is_leader&&Number(r.tier)<Number(m.tier||0));
  roster.innerHTML=(data.roster||[]).map(x=>`<article class="member"><div>${x.photo_url?`<img class="member-avatar" src="${esc(x.photo_url)}" alt="">`:''}<div class="member-name">${esc(x.name||x.character_id)}</div><div class="meta">CID ${esc(x.character_id)} · ${esc(x.rank_name)}</div></div><span class="badge ${x.suspended?'suspended':x.on_duty?'on':''}">${x.suspended?'Suspended':x.on_duty?'On duty':'Off duty'}</span>${data.canManage&&!x.is_leader&&Number(x.tier)<Number(m.tier||0)?`<div class="actions"><select data-rank="${esc(x.character_id)}">${ranks.map(r=>`<option value="${r.id}" ${Number(r.id)===Number(x.rank_id)?'selected':''}>${esc(r.name)}</option>`).join('')}</select><button data-action="rank" data-cid="${esc(x.character_id)}">Set rank</button><button data-action="${x.suspended?'reinstate':'suspend'}" data-cid="${esc(x.character_id)}">${x.suspended?'Reinstate':'Suspend'}</button><button data-action="fire" data-cid="${esc(x.character_id)}">Remove</button></div>`:'<div></div>'}</article>`).join('')||(data.canViewMembers?'<p>No members found.</p>':'<p>Your rank does not have roster visibility.</p>');
  const f=data.facilities||{},types=data.facilityTypes||{};document.querySelector('#facilities').innerHTML=Object.entries(types).map(([id,t])=>{const set=!!f[id];return `<article class="facility-card"><small>${esc(t.role)}</small><h3>${esc(t.label)}</h3><p>${set?'Configured and active':'Location not configured'}</p>${data.canManage?`<div class="actions"><button data-facility="${esc(id)}" data-reset="false">Set here</button>${set?`<button class="danger" data-facility="${esc(id)}" data-reset="true">Reset</button>`:''}</div>`:''}</article>`}).join('');
  renderOverview({...data,organization:o});renderRanksList();renderLawRecordRail(data,o,m)
}

// ── Right-hand member record rail (persistent across every tab) ────────────
function renderLawRecordRail(data,o,m){
  const cid=data.characterId||m.characterId||'—';
  const me=(data.roster||[]).find(x=>String(x.character_id)===String(cid));
  const myName=(me&&(me.name||me.character_id))||cid;
  const dutyText=m.suspended?'Suspended':m.onDuty?'On duty':'Off duty';
  const railArt=document.querySelector('#railArt');if(railArt)railArt.src=o.art;
  const railTitle=document.querySelector('#railTitle');if(railTitle)railTitle.textContent=`${o.shortLabel||'LEGAL'} RECORD`;
  const railInfo=document.querySelector('#railInfo');
  if(railInfo)railInfo.innerHTML=[
    ['Rank',m.rankName||'—'],
    ['Character',`CID ${cid}`],
    ['Status',dutyText],
    ['Terminal','F6 · Organization'],
  ].map(([label,value])=>`<div class="law-record-rail__row"><small>${esc(label)}</small><strong>${esc(value)}</strong></div>`).join('');
  const tabVisible=tab=>{const el=document.querySelector(`#${tab}Tab`);return !el||!el.classList.contains('hidden')};
  const actions=[
    {label:'Ranks & access',tab:'ranks',show:true},
    {label:'Custody monitor',tab:'custody',show:data.canCustody===true},
    {label:'Activity logs',tab:'logs',show:tabVisible('logs')},
    {label:'Logistics',tab:'logistics',show:tabVisible('logistics')},
  ].filter(a=>a.show);
  const railActions=document.querySelector('#railActions');
  if(railActions){
    railActions.innerHTML=actions.map(a=>`<button type="button" data-rail-tab="${esc(a.tab)}">${esc(a.label)}</button>`).join('');
    railActions.onclick=e=>{const b=e.target.closest('[data-rail-tab]');if(b){const tab=document.querySelector(`.tab[data-tab="${b.dataset.railTab}"]`);if(tab)tab.click()}};
  }
  const railName=document.querySelector('#railName');if(railName)railName.textContent=myName;
  const railRankTier=document.querySelector('#railRankTier');if(railRankTier)railRankTier.textContent=`${m.rankName||'—'} · Tier ${Number(m.tier||0)}`;
  const dot=document.querySelector('#sideDutyDot');if(dot)dot.classList.toggle('is-on',m.onDuty===true);
}

// ── Overview ───────────────────────────────────────────────────────────────
const pageBlurbs={overview:'Command status, agency tools and the organization feed at a glance.',roster:'Everyone in the organization, with rank, status and tier.',ranks:'Ranks define tier and permissions. Leaders can create, edit, and delete ranks below their own tier.',fleet:'Manage each vehicle\'s parking location and minimum rank.',logs:'Every staffing, rank and facility change in this organization.',dispatch:'Shared 911 calls across every authorized legal unit.',mdt:'Shared citizen, vehicle and case records.',staffing:'Hire and manage organization members.'};
let overviewFeedRows=[];
function renderOverview(data){
  const m=data.member||{}, roster=data.roster||[], summary=data.summary||{};
  const caps=m.capabilities||{};
  const capLabels={dispatch:'Dispatch',mdt:'MDT',arrest:'Arrest',search:'Search',citations:'Citations',impound:'Impound',radar:'Radar',spikes:'Spikes',barricades:'Barricades',clamp:'Clamp',k9:'K9',alpr:'ALPR',armory:'Armory',fleet:'Fleet',evidence:'Evidence',prisonIntake:'Prison Intake'};
  const memberCount = Number(summary.memberCount ?? roster.length ?? 0);
  const dutyRoster = roster.filter(x=>x.on_duty&&!x.suspended);
  const onDutyCount = Number(summary.onDutyCount ?? dutyRoster.length ?? 0);
  const leaderName = summary.leaderName || data.organization.leaderName || 'Not assigned';
  const leaderCid = summary.leaderCid || data.organization.leaderCid || '';
  const activeCalls=Number(summary.activeCalls||0),assignedCalls=Number(summary.assignedCalls||0);
  const priorityCall=summary.priorityCall;
  const prison=data.prison||{};
  const cid=data.characterId||m.characterId||'—';
  const me=roster.find(x=>String(x.character_id)===String(cid));
  const memberName=(me&&(me.name||me.character_id))||`CID ${cid}`;
  const priorityAlert=document.querySelector('#overviewPriorityAlert');
  if(priorityAlert){
    priorityAlert.classList.toggle('hidden',!priorityCall);
    priorityAlert.classList.toggle('is-critical',Number(priorityCall?.priority||0)>=3);
    if(priorityCall){
      document.querySelector('#overviewPriorityBadge').textContent=Number(priorityCall.priority)>=3?'OFFICER ASSISTANCE':'ACTIVE CALL';
      document.querySelector('#overviewPriorityTitle').textContent=priorityCall.details||'Emergency call awaiting response';
      document.querySelector('#overviewPriorityMeta').textContent=`${priorityCall.location||'Unknown location'} · ${timeAgo(priorityCall.createdAt)} · ${priorityCall.status==='accepted'?'Units assigned':'Awaiting unit'}`;
      const viewCall=document.querySelector('[data-overview-dispatch]');if(viewCall)viewCall.hidden=data.canDispatch!==true;
      document.querySelector('#overviewRespond').dataset.callId=priorityCall.id;
      document.querySelector('#overviewRespond').hidden=data.canDispatch!==true;
    }
  }
  document.querySelector('#overviewShortLabel').textContent=data.organization.shortLabel||'LEGAL ORGANIZATION';
  document.querySelector('#overviewOrgName').textContent=data.organization.label||'Organization';
  document.querySelector('#overviewJurisdiction').textContent=data.organization.jurisdiction||'Authorized jurisdiction';
  document.querySelector('#overviewRank').textContent=m.rankName||'—';
  document.querySelector('#overviewCharacterId').textContent=`CID ${esc(data.characterId||m.characterId||'—')}`;
  document.querySelector('#overviewMemberName').textContent=memberName;
  const photoImg=document.querySelector('#overviewMemberPhoto');
  if(photoImg){if(me&&me.photo_url){photoImg.src=me.photo_url;photoImg.style.visibility='visible'}else{photoImg.style.visibility='hidden'}}
  document.querySelector('#overviewTier').textContent=Number(m.tier||0);
  const dutyBadge=document.querySelector('#overviewDutyBadge');
  const dutyText=m.suspended?'SUSPENDED':m.onDuty?'ON DUTY':'OFF DUTY';
  dutyBadge.textContent=dutyText; dutyBadge.className=`status-pill ${m.suspended?'is-suspended':m.onDuty?'is-on':'is-off'}`;
  const readinessPct=memberCount>0?Math.min(100,Math.round((onDutyCount/memberCount)*100)):0;
  document.querySelector('#overviewReadinessMeta').textContent=`${onDutyCount} / ${memberCount}`;
  document.querySelector('#overviewReadinessTotal').textContent=`${onDutyCount} unit${onDutyCount===1?'':'s'}`;
  document.querySelector('#overviewReadinessBar').style.width=`${readinessPct}%`;
  const prisonCard=document.querySelector('#overviewPrisonStatus');
  if(prisonCard){
    const configured=prison.configured===true, online=prison.ready===true;
    const occupied=Math.max(0,Number(prison.activeCount||0)), capacity=Math.max(0,Number(prison.capacity||0));
    document.querySelector('#overviewPrisonCells').textContent=`${occupied} / ${capacity}`;
    document.querySelector('#overviewPrisonSpawns').textContent=String(Number(prison.spawnCount||0));
    const stateNode=document.querySelector('#overviewPrisonState');
    stateNode.textContent=!online?'OFFLINE':configured?'READY':'SETUP REQUIRED';
    stateNode.className=`prison-status-card__state ${!online?'is-offline':configured?'is-ready':'is-warning'}`;
    document.querySelector('#overviewPrisonMeta').textContent=!online?'cm-prison is not ready. Start it before booking.':configured?'One intake location shared by every law organization.':'Configure intake, release, and cell spawns once in prison admin.';
    prisonCard.classList.toggle('is-warning',online&&!configured);
  }
  const overviewCount=value=>String(Math.max(0,Number(value)||0)).padStart(2,'0');
  // Card status badges are derived from live counts, never fixed labels, so they
  // cannot claim a readiness state the server data does not actually show.
  const priorityCalls=Number(summary.priorityCalls||0);
  const callsState=priorityCalls>0?['PRIORITY','red']:activeCalls>0?['ACTIVE','amber']:['ALL CLEAR','green'];
  const dutyState=onDutyCount>0?['ACTIVE','green']:['STANDBY','amber'];
  document.querySelector('#overviewStats').innerHTML=[
    ['ON DUTY UNITS',overviewCount(onDutyCount),`${memberCount} total personnel`,'duty',dutyState],
    ['ACTIVE CALLS',overviewCount(activeCalls),`${assignedCalls} assigned · ${priorityCalls} priority`,'calls',callsState],
    ['FLEET AVAILABLE',Number(summary.fleetAvailable||0).toLocaleString(),`${Number(summary.fleetConfigured||0)} configured for agency`,'fleet'],
    ['COMMAND',leaderName,leaderCid?`CID ${leaderCid}`:'Leader not assigned','command'],
  ].map(([label,value,sub,kind,badge])=>`<div class="stat stat--${kind}"><span class="stat-icon" aria-hidden="true"></span>${badge?`<em class="stat-badge stat-badge--${badge[1]}">${esc(badge[0])}</em>`:''}<div><small>${esc(label)}</small><strong>${esc(value)}</strong><span>${esc(sub)}</span></div></div>`).join('');
  const enabled=Object.entries(caps).filter(([,on])=>on===true);
  document.querySelector('#overviewCapabilityCount').textContent=`${enabled.length} SYSTEMS ONLINE`;
  const capsBox=document.querySelector('#overviewCapabilities');
  capsBox.classList.toggle('is-empty',!enabled.length);
  capsBox.innerHTML=enabled.length?enabled.map(([id])=>`<span class="capability-pill"><i></i>${esc(capLabels[id]||id)}</span>`).join(''):cmEmptyState('tools','No operational capabilities enabled for this rank.');
  // Field coordination: hidden entirely unless the viewer holds at least one
  // of the two permissions, matching how cm-ems and cm-police gate the same
  // panel. The server checks again on every call -- this is presentation only.
  const canMap=data.canViewMemberMap===true,canMeet=data.canSetMeeting===true;
  const canDeskMdt=data.canMdt===true, canDeskDispatch=data.canDispatch===true;
  const launchMdt=document.querySelector('#overviewLaunchMdt'), openDispatch=document.querySelector('#overviewDispatch');
  if(launchMdt){launchMdt.hidden=!canDeskMdt;launchMdt.disabled=!canDeskMdt;launchMdt.title=canDeskMdt?'Open the shared MDT':'MDT requires on-duty access for this rank';}
  if(openDispatch){openDispatch.hidden=!canDeskDispatch;openDispatch.disabled=!canDeskDispatch;openDispatch.title=canDeskDispatch?'Open shared dispatch':'Dispatch requires on-duty access for this rank';}
  document.querySelector('#overviewToolsPanel').hidden=false;
  document.querySelector('#memberMap').hidden=!canMap;
  document.querySelector('#meetingPoint').hidden=!canMeet;
  document.querySelector('#clearMeeting').hidden=!canMeet;
  document.querySelector('#overviewDutyCount').textContent=`${onDutyCount} UNIT${onDutyCount===1?'':'S'}`;
  const dutyBox=document.querySelector('#overviewDutyRoster');
  dutyBox.classList.toggle('is-empty',!(data.canViewMembers&&dutyRoster.length));
  dutyBox.innerHTML=data.canViewMembers
    ? (dutyRoster.length?dutyRoster.slice(0,5).map(x=>{const name=x.name||`CID ${x.character_id}`;const initials=name.split(/\s+/).filter(Boolean).slice(0,2).map(n=>n[0]).join('').toUpperCase();return `<div class="duty-person"><span class="duty-avatar">${esc(initials||'U')}</span><div><strong>${esc(name)}</strong><small>${esc(x.rank_name||'Member')}</small></div><span class="duty-live">10-8</span></div>`}).join(''):cmEmptyState('duty','No organization members are currently on duty.'))
    : cmEmptyState('duty','Roster visibility is restricted for your rank.');
  document.querySelector('#overviewShiftKicker').textContent=m.suspended?'ACCESS LIMITED':m.onDuty?'ACTIVE SHIFT':'NOT ACTIVE';
  document.querySelector('#overviewShift').innerHTML=`
    <div class="shift-row"><span>Rank</span><strong>${esc(m.rankName||'—')}</strong></div>
    <div class="shift-row"><span>Tier</span><strong>${Number(m.tier||0)}</strong></div>
    <div class="shift-row"><span>Status</span><strong class="shift-state ${m.suspended?'danger':m.onDuty?'live':''}">${esc(dutyText)}</strong></div>
    <div class="shift-row"><span>Uniform</span><strong>${m.uniformActive?'Duty uniform':'Not active'}</strong></div>
    <div class="shift-row"><span>Radio</span><strong>/${esc(data.organization.radioChannel||'—')}</strong></div>
    <div class="shift-row"><span>Non-RP chat</span><strong>/${esc(data.organization.chatChannel||'—')}</strong></div>`;
  const activityPanel=document.querySelector('#overviewActivityPanel');
  const activity=data.recentActivity||[];
  const activityBox=document.querySelector('#overviewRecentActivity');
  activityPanel.classList.toggle('is-restricted',data.canViewActivity!==true);
  activityBox.classList.toggle('is-empty',data.canViewActivity!==true||!activity.length);
  activityBox.innerHTML=data.canViewActivity===true
    ? (activity.length?activity.map(row=>{const label=(typeof activityLabels!=='undefined'&&activityLabels[row.action])||String(row.action||'Activity').replaceAll('_',' ');const desc=typeof describeLog==='function'?describeLog(row.detail):'';return `<div class="activity-item"><span class="activity-marker"></span><div><strong>${esc(row.actorName||'System')}</strong><p>${esc(label)}${desc?` · ${desc}`:''}</p></div><time>${esc(formatTerminalTime(row.createdAt))}</time></div>`}).join(''):cmEmptyState('feed','No organization activity recorded yet.'))
    : cmEmptyState('feed','Recent organization activity is available to command staff.');
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
      <details class="rank-access"><summary>${data.canInspectRankPermissions?`${granted.length} permissions`:"Restricted access"}<span>View details</span></summary><div class="perm-pills">${pills}</div></details>
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
    if(!(await showConfirmOverlay('Delete rank','Delete this rank? Members must be reassigned first.','Delete','Cancel')))return;
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
    return `<article class="log-row"><div class="log-row__main"><strong>${esc(row.actorName)}</strong> ${esc(label)}${desc?` · ${desc}`:''}</div><time>${esc(formatTerminalTime(row.createdAt))}</time></article>`;
  }).join('')||'<p>No activity recorded yet.</p>';
}
async function loadActivityLog(){const r=await post('activityLog');activityLogRows=r?.list||[];renderActivityLog()}

// ── Shared Custody ─────────────────────────────────────────────────────────
let custodyRows = {items:[], updatedAt:null}, custodyLoading = false;
function formatRemaining(seconds){
  seconds=Math.max(0,Math.floor(Number(seconds)||0));
  const days=Math.floor(seconds/86400); seconds%=86400;
  const hours=Math.floor(seconds/3600); seconds%=3600;
  const minutes=Math.floor(seconds/60), secs=seconds%60;
  return days>0?`${days}d ${String(hours).padStart(2,'0')}h`:hours>0?`${hours}h ${String(minutes).padStart(2,'0')}m`:`${minutes}m ${String(secs).padStart(2,'0')}s`;
}
function renderCustody(){
  const box=document.querySelector('#custodyList'); if(!box)return;
  document.querySelector('#custodyCount').textContent=String(custodyRows.length);
  document.querySelector('#custodyUpdated').textContent=custodyRows.updatedAt?formatTerminalTime(custodyRows.updatedAt):'—';
  const rows=custodyRows.items||[];
  box.innerHTML=rows.length?rows.map(row=>`<article class="custody-row"><div class="custody-row__identity"><span class="custody-avatar">CID</span><div><strong>${esc(row.name)}</strong><small>CID ${esc(row.characterId)} · Booked by ${esc(row.arrestedBy)}</small></div></div><div class="custody-row__reason"><small>BOOKING REASON</small><span>${esc(row.reason)}</span></div><div class="custody-row__release"><small>RELEASES IN</small><strong data-custody-release="${Number(row.releaseEpoch)||0}">${formatRemaining(row.remainingSeconds)}</strong><span>${row.releaseEpoch?new Date(Number(row.releaseEpoch)*1000).toLocaleString([], {month:'short',day:'numeric',hour:'2-digit',minute:'2-digit'}):'—'}</span></div></article>`).join(''):'<div class="custody-empty"><span>✓</span><strong>No active prisoners</strong><p>The central custody list is clear.</p></div>';
}
async function loadCustody(){
  if(custodyLoading)return; const box=document.querySelector('#custodyList'); if(!box)return;
  custodyLoading=true; box.innerHTML='<p class="hint">Loading central custody records…</p>';
  const result=await post('custody'); custodyLoading=false;
  if(!result?.ok){custodyRows=[];document.querySelector('#custodyCount').textContent='—';document.querySelector('#custodyUpdated').textContent='—';box.innerHTML=`<div class="custody-empty is-error"><span>!</span><strong>Custody unavailable</strong><p>${esc(result?.error||'The prison did not respond.')}</p></div>`;return}
  custodyRows={items:result.prisoners||[],updatedAt:result.fetchedAt?Number(result.fetchedAt)*1000:Date.now()}; renderCustody();
}
document.querySelector('#custodyRefresh')?.addEventListener('click',loadCustody);
setInterval(()=>document.querySelectorAll('[data-custody-release]').forEach(node=>{const epoch=Number(node.dataset.custodyRelease||0);if(epoch)node.textContent=formatRemaining(epoch-Math.floor(Date.now()/1000))}),1000);

// ── Fleet vehicles ─────────────────────────────────────────────────────────
// Appearance (model/label/category/image) comes live from the vehicle shop
// admin's org-tagged catalog -- there is no separate "add to fleet" step;
// every tagged vehicle shows up here, unconfigured ones just need a
// location set first (Set location, drive it, press H).
let fleetVehicles = [], fleetRanks = [], fleetCanManage = false;
const fleetPending = new Set();
async function postFleetAction(name,data={}){let timer;try{return await Promise.race([post(name,data),new Promise(resolve=>{timer=setTimeout(()=>resolve({ok:false,error:'Fleet request timed out. Try again.'}),12000)})])}finally{clearTimeout(timer)}}
const fleetRosterNode=()=>document.querySelector('#fleetView:not(.hidden) #orgFleetRoster')||document.querySelector('#fleetRoster');
const fleetRecallNode=()=>document.querySelector('#fleetView:not(.hidden) #orgFleetRecallAll')||document.querySelector('#fleetRecallAll');
function renderFleetList(npcMode = !legalFleet.classList.contains('hidden')){
  const manage = fleetCanManage;
  const rosterNode=fleetRosterNode(); if(!rosterNode)return;
  if(!npcMode){
    rosterNode.innerHTML = fleetVehicles.map(v => `<article class="fleet-row${v.configured && !v.enabled ? ' disabled' : ''}">
      <div class="fleet-row__main"><strong>${esc(v.label)}</strong><small>${esc(v.category || 'Vehicle')} · Parking: ${v.configured ? `${v.location?.x ?? 'saved'}, ${v.location?.y ?? 'saved'}` : 'not configured'} · Required rank ${esc(v.minRankName || `Tier ${v.minTier}`)}${v.enabled ? '' : ' · Disabled'} · ${esc(String(v.status || 'available').replaceAll('_', ' '))}</small></div>
      <div class="actions">${manage ? `<select data-fleet-tier="${esc(v.model)}"${v.configured ? '' : ' disabled title="Set a location first"'}>${fleetRanks.map(rank => `<option value="${Number(rank.tier)}"${String(rank.tier) === String(v.minTier) ? ' selected' : ''}>${esc(rank.name)}</option>`).join('')}${fleetRanks.some(rank => String(rank.tier) === String(v.minTier)) ? '' : `<option value="${Number(v.minTier)}" selected disabled>${esc(v.minRankName || `Tier ${v.minTier}`)} (saved)</option>`}</select><button data-fleet-location="${esc(v.model)}">Set location</button>${v.configured ? `<button data-fleet-recall="${esc(v.model)}"${v.status === 'in_use' ? ' disabled' : ''}>${v.status === 'in_use' ? 'In use' : 'Recall'}</button>` : ''}` : ''}</div>
    </article>`).join('') || `<p>${manage ? 'No vehicles have been added to this organization\'s fleet yet.' : 'No fleet vehicles are available to your rank yet.'}</p>`;
    return;
  }
  rosterNode.innerHTML = fleetVehicles.map(v => {
    const status = v.status === 'in_use' ? 'IN USE' : v.status === 'recovering' ? 'RECOVERING' : !v.configured ? 'NOT CONFIGURED' : !v.enabled ? 'DISABLED' : 'AVAILABLE';
    const selected = String(v.minTier);
    const disabled = !v.configured || !v.enabled;
    const pending = (action) => fleetPending.has(`${v.model}:${action}`);
    return `<article class="fleet-row${disabled ? ' disabled' : ''}">
      ${v.image ? `<img class="fleet-thumb" src="${esc(v.image)}" alt="">` : '<div class="fleet-thumb fleet-thumb--empty" aria-hidden="true">VEHICLE</div>'}
      <div class="fleet-row__main"><strong>${esc(v.label)}</strong><small>Required: ${esc(v.minRankName || `Tier ${v.minTier}`)}+ · ${status}</small>
      ${manage ? `<div class="actions"><label>Required Rank${pending('rank') ? ' · Saving…' : ''} <select data-fleet-tier="${esc(v.model)}"${disabled || pending('rank') ? ' disabled' : ''}>${fleetRanks.map(rank => `<option value="${Number(rank.tier)}"${String(rank.tier) === selected ? ' selected' : ''}>${esc(rank.name)}</option>`).join('')}${fleetRanks.some(rank => String(rank.tier) === selected) ? '' : `<option value="${esc(selected)}" selected disabled>${esc(v.minRankName || `Tier ${selected}`)} (saved)</option>`}</select></label>
      <button data-fleet-location="${esc(v.model)}"${pending('location') ? ' disabled' : ''}>${pending('location') ? 'Saving…' : 'Set Location'}</button>
      ${v.configured ? `<button data-fleet-recall="${esc(v.model)}"${v.status === 'in_use' || pending('recall') ? ' disabled' : ''}>${pending('recall') ? 'Recalling…' : 'Recall'}</button>` : ''}</div>` : ''}
      </div>
    </article>`;
  }).join('') || `<p>${manage ? 'No vehicles have been added to this organization\'s fleet yet.' : 'No fleet vehicles are available to your rank yet.'}</p>`;
}
async function loadFleet(){const r=await postFleetAction('fleetCatalog');fleetVehicles=r?.vehicles||[];fleetRanks=r?.ranks||[];fleetCanManage=r?.canManage===true;renderFleetList();const fleetRecall=fleetRecallNode();if(fleetRecall)fleetRecall.classList.toggle('hidden',!fleetCanManage)}
document.querySelectorAll('#orgFleetRoster,#fleetRoster').forEach(node=>node.addEventListener('click',async e=>{
  const location=e.target.closest('[data-fleet-location]');
  if(location){const model=location.dataset.fleetLocation;fleetPending.add(`${model}:location`);renderFleetList();const r=await postFleetAction('setFleetVehicleLocation',{model});notice(r.message||r.error,r.ok?'success':'error');await loadFleet();fleetPending.delete(`${model}:location`);renderFleetList()}
  const recall=e.target.closest('[data-fleet-recall]');
  if(recall){const model=recall.dataset.fleetRecall;if(!(await showConfirmOverlay('Recall fleet vehicle',`Return ${recall.closest('.fleet-row')?.querySelector('strong')?.textContent||'this vehicle'} to its saved parking location? Occupied vehicles cannot be recalled.`,'Recall','Cancel')))return;fleetPending.add(`${model}:recall`);renderFleetList();const r=await postFleetAction('recallFleetVehicle',{model});notice(r.message||r.error,r.ok?'success':'error');await loadFleet();fleetPending.delete(`${model}:recall`);renderFleetList()}
}));
document.querySelectorAll('#orgFleetRoster,#fleetRoster').forEach(node=>node.addEventListener('change',async e=>{
  const tierInput=e.target.closest('[data-fleet-tier]');
  if(!tierInput)return;
  const model=tierInput.dataset.fleetTier;fleetPending.add(`${model}:rank`);renderFleetList();const r=await postFleetAction('setFleetVehicleMinTier',{model,minTier:Number(tierInput.value)});notice(r.message||r.error,r.ok?'success':'error');await loadFleet();fleetPending.delete(`${model}:rank`);renderFleetList();
}));
document.querySelectorAll('#orgFleetRecallAll,#fleetRecallAll').forEach(node=>node.addEventListener('click',async()=>{
  if(!(await showConfirmOverlay('Recall fleet','Recall every enabled fleet vehicle back to its saved location?','Recall','Cancel')))return;
  node.disabled=true;node.textContent='Recalling Fleet…';
  const r=await postFleetAction('recallAllFleetVehicles');
  notice(r.message||r.error,r.ok?'success':'error');
  await loadFleet();node.disabled=false;node.textContent='Recall All to Parking';
}));
// Standalone Motor Pool panel (opened only from the Fleet facility NPC --
// never through the F6 dashboard). Reuses the fleet list/actions above,
// which already read from a dedicated fleetCanManage flag rather than the
// full dashboard's `state`, since this panel can open without ever loading
// the dashboard.
const legalFleet=document.querySelector('#legalFleet');
window.addEventListener('message',e=>{const d=e.data||{};if(d.action==='legalFleetOpen'){app.classList.add('hidden');facilityDialogue.classList.add('hidden');facilityPrompt.classList.add('hidden');document.querySelector('#fleetOrg').textContent=d.label||'LEGAL ORGANIZATION';fleetVehicles=d.vehicles||[];fleetRanks=d.ranks||[];fleetCanManage=d.canManage===true;legalFleet.classList.remove('hidden');renderFleetList(true);document.querySelector('#fleetRecallAll').classList.toggle('hidden',!fleetCanManage)}if(d.action==='legalFleetClose'){legalFleet.classList.add('hidden');fleetPending.clear()}});
document.querySelector('#fleetClose').onclick=()=>post('legalFleetClose');
// ── Dispatch (911 calls) ──────────────────────────────────────────────────
let dispatchActiveCalls = [], dispatchHistory = [];
function timeAgo(epochSeconds){const seconds=Math.max(0,Math.floor(Date.now()/1000)-Number(epochSeconds||0));if(seconds<60)return `${seconds}s ago`;if(seconds<3600)return `${Math.floor(seconds/60)}m ago`;return `${Math.floor(seconds/3600)}h ago`}
function renderDispatchActiveList(){
  const myCid = state?.characterId;
  document.querySelector('#lawDispatchActiveCount').textContent=dispatchActiveCalls.length;
  document.querySelector('#lawDispatchAssignedCount').textContent=dispatchActiveCalls.filter(call=>(call.responders||[]).length>0).length;
  document.querySelector('#dispatchActiveList').innerHTML = dispatchActiveCalls.map(call => {
    const mine = myCid && (call.responders || []).find(r => r.characterId === myCid);
    const responders = (call.responders || []).map(r => `${esc(r.callsign || r.name)} (${r.status === 'on_scene' ? 'On Scene' : r.status === 'en_route' ? 'En Route' : 'Accepted'})`).join(', ') || 'No one responding yet';
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
document.querySelector('#dispatchBackup').onclick=async()=>{if(!(await showConfirmOverlay('Request backup','Request backup and send your current location to all available legal units?','Request','Cancel')))return;const r=await post('dispatchOfficerAlert',{alertType:'backup',confirmed:true});notice(r.message||r.error,r.ok?'success':'error')};
document.querySelector('#dispatchPanic').onclick=async()=>{if(!(await showConfirmOverlay('Panic button','Activate the panic button and send an urgent officer-in-distress alert?','Activate','Cancel',{dismissOnBackdrop:false})))return;const r=await post('dispatchOfficerAlert',{alertType:'panic',confirmed:true});notice(r.message||r.error,r.ok?'success':'error')};
document.querySelector('[data-overview-dispatch]').onclick=()=>document.querySelector('#dispatchTab')?.click();
document.querySelector('[data-overview-respond]').onclick=async e=>{const callId=Number(e.currentTarget.dataset.callId||0);if(!callId)return;const r=await post('dispatchAccept',{callId,route:true});notice(r.message||r.error,r.ok?'success':'error');if(r.ok){document.querySelector('#dispatchTab')?.click();refresh()}};

// ── Dispatch notification carousel ──────────────────────────────────────
// Persistent overlay outside the F6 menu (lives at the body level, see
// law.html's #dispatchNotifyStack), so a new call is actionable via quick
// GPS/Accept without opening the full Dispatch tab. client/dispatch.lua
// sends dispatchNotifyNew/Assigned/Resolved; client/main.lua's
// dispatchNotifyFocus NUI callback grants mouse-only NUI focus
// (SetNuiFocus(true,false)+SetNuiFocusKeepInput) while at least one card is
// up, so clicking a button doesn't require opening F6 or blocking movement.
const dispatchCodeLabels={panic:'10-99 · OFFICER NEEDS HELP',backup:'10-78 · BACKUP REQUESTED',gunfire:'10-71 · SHOTS FIRED',front_desk:'10-16 · FRONT DESK REQUEST',citizen:'911 · CITIZEN CALL'};
const dispatchNotifyStack=document.querySelector('#dispatchNotifyStack');
const dispatchNotifyTimers={};
const NOTIFY_AUTO_DISMISS_MS=25000;
const NOTIFY_MAX_CARDS=4;
function syncDispatchNotifyFocus(){post('dispatchNotifyFocus',{active:dispatchNotifyStack.children.length>0})}
function removeDispatchNotify(callId){
  const card=dispatchNotifyStack.querySelector(`[data-notify-call="${callId}"]`);
  if(card)card.remove();
  if(dispatchNotifyTimers[callId]){clearTimeout(dispatchNotifyTimers[callId]);delete dispatchNotifyTimers[callId]}
  syncDispatchNotifyFocus();
}
function addDispatchNotify(call,kind){
  if(!call||!call.id)return;
  removeDispatchNotify(call.id);
  const priority=Number(call.priority||1)>=3||call.callType==='panic';
  const card=document.createElement('article');
  card.className=`dispatch-notify-card${priority?' is-priority':''}${kind==='assigned'?' is-assigned':''}`;
  card.dataset.notifyCall=call.id;
  card.innerHTML=`<div class="dispatch-notify-card__head"><span class="dispatch-notify-card__code">${esc(dispatchCodeLabels[call.callType]||dispatchCodeLabels.citizen)}${kind==='assigned'?' · ASSIGNED TO YOU':''}</span><button class="dispatch-notify-card__dismiss" data-notify-dismiss aria-label="Dismiss">×</button></div><div class="dispatch-notify-card__details">${esc(call.details||'Dispatch call')}</div><div class="dispatch-notify-card__meta">${esc(call.location||'Unknown location')}</div><div class="dispatch-notify-card__actions"><button data-notify-gps>Set GPS</button>${kind==='new'?'<button data-notify-accept>Accept</button>':''}</div>`;
  dispatchNotifyStack.prepend(card);
  while(dispatchNotifyStack.children.length>NOTIFY_MAX_CARDS)dispatchNotifyStack.lastElementChild.remove();
  if(kind==='new')dispatchNotifyTimers[call.id]=setTimeout(()=>removeDispatchNotify(call.id),NOTIFY_AUTO_DISMISS_MS);
  syncDispatchNotifyFocus();
}
dispatchNotifyStack.addEventListener('click',async e=>{
  const card=e.target.closest('[data-notify-call]');if(!card)return;
  const callId=Number(card.dataset.notifyCall);
  if(e.target.closest('[data-notify-dismiss]'))return removeDispatchNotify(callId);
  if(e.target.closest('[data-notify-gps]')){await post('dispatchQuickRoute',{callId});return}
  if(e.target.closest('[data-notify-accept]')){
    const r=await post('dispatchAccept',{callId,route:true});
    notice(r.message||r.error,r.ok?'success':'error');
    if(r.ok)removeDispatchNotify(callId);
  }
});
window.addEventListener('message',e=>{
  const d=e.data||{};
  if(d.action==='dispatchNotifyNew')addDispatchNotify(d.call,'new');
  if(d.action==='dispatchNotifyAssigned')addDispatchNotify(d.call,'assigned');
  if(d.action==='dispatchNotifyResolved')removeDispatchNotify(Number(d.callId));
});
function esc(v){return String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
// Centered icon+label placeholder for any overview list/grid that has nothing to show
// (no items, or access restricted). Pairs with the .cm-empty-state rules in
// command-ui-v3.0.css and the .is-empty modifier toggled on the list container.
function cmEmptyState(icon,label){return `<div class="cm-empty-state"><i class="cm-empty-state__icon cm-empty-state__icon--${icon}"></i><span>${esc(label)}</span></div>`}
window.addEventListener('message',e=>{const {action,data,kind,message,initialTab}=e.data||{};if(action==='bookingOpen'){renderBooking(data);return}if(action==='bookingResult'){bookingBusy=false;bookingPanel?.classList.remove('is-busy');if(!data?.ok&&bookingPanel)document.querySelector('#bookingStatus').textContent=data?.error||'Booking failed.';return}if(action==='open'){facilityOnly=e.data?.facilityOnly===true;const standalone=e.data?.standaloneMode===true;app.classList.toggle('standalone-interface',standalone);app.classList.toggle('standalone-dispatch',standalone&&initialTab==='dispatch');app.classList.toggle('standalone-mdt',standalone&&initialTab==='mdt');app.classList.remove('hidden');render(data);if(standalone&&initialTab){document.querySelectorAll('.view').forEach(x=>x.classList.add('hidden'));document.querySelector(`#${initialTab}View`)?.classList.remove('hidden');document.querySelector('#pageTitle').textContent=pageTitles[initialTab]||initialTab;if(initialTab==='dispatch'){loadDispatchActiveCalls();loadDispatchHistory()}if(initialTab==='mdt')loadMdtDashboard()}else{const requested=initialTab&&document.querySelector(`[data-tab="${initialTab}"]`);const tab=requested&&!requested.classList.contains('hidden')?requested:document.querySelector('[data-tab="overview"]');if(tab)tab.click()}}if(action==='dashboard')render(data);if(action==='close'){closeBooking();fleetPending.clear();app.classList.add('hidden');app.classList.remove('standalone-interface','standalone-dispatch','standalone-mdt');document.getElementById('lawConfirmNo').click()}if(action==='notice')notice(message,kind);if(action==='dispatchRefresh'&&!app.classList.contains('hidden')&&!document.querySelector('#dispatchView').classList.contains('hidden'))loadDispatchActiveCalls()});
document.querySelectorAll('[data-close]').forEach(b=>b.onclick=()=>post('close'));window.cmHandleEscape=()=>{if(window.CMUI&&typeof window.CMUI.cancelAllConfirms==='function'&&document.querySelector('.cm-modal-backdrop')){window.CMUI.cancelAllConfirms();return;}if(bookingPanel&&!bookingPanel.hidden)closeBooking();else if(!document.getElementById('lawConfirm').hidden)document.getElementById('lawConfirmNo').click();else if(armoryManager&&!armoryManager.classList.contains('hidden'))document.querySelector('#armoryManagerClose')?.click();else if(!document.querySelector('#legalArmory').classList.contains('hidden'))post('legalArmoryClose');else if(!document.querySelector('#legalFleet').classList.contains('hidden'))post('legalFleetClose');else if(!document.querySelector('#wardrobeRoom').classList.contains('hidden'))post('legalWardrobeCancel');else if(!document.querySelector('#facilityDialogue').classList.contains('hidden'))post('facilityDialogueClose');else post('escape')};document.addEventListener('keydown',e=>{if(e.key==='Escape'||e.key==='Esc'||e.keyCode===27){e.preventDefault();if(!e.repeat)window.cmHandleEscape()}});
let logisticsData={items:[],orders:[]};
function renderLogistics(){const info=state?.logistics||{},form=document.querySelector('#logisticsOrderForm');form.classList.toggle('hidden',info.canRequest!==true);document.querySelector('#logisticsHint').textContent=info.canRequest===true?'Submit from your on-duty organization armory. Army quartermasters accept, prepare, load, and deliver orders.':'View order progress here; your rank cannot submit routine supply requests.';document.querySelector('#logisticsItem').innerHTML=(logisticsData.items||[]).map(x=>`<option value="${esc(x.itemName)}">${esc(x.label)} · ${esc(x.itemName)}</option>`).join('');document.querySelector('#logisticsOrders').innerHTML=(logisticsData.orders||[]).map(o=>{const lines=(o.lines||[]).map(l=>`${esc(l.itemName)} × ${l.quantity}`).join(', ');const buttons=Object.keys(o.actions||{}).map(a=>`<button data-logistics-action="${esc(a)}" data-order-id="${o.id}">${esc(a.replaceAll('_',' '))}</button>`).join('');return `<article class="logistics-order"><div><strong>Order #${o.id} · ${esc(o.status.replaceAll('_',' '))}</strong><small>${esc(o.requesterLabel)} · ${lines}</small>${o.shipment?`<small>Shipment ${esc(o.shipment)}</small>`:''}</div><div class="actions">${buttons}</div></article>`}).join('')||'<p>No supply orders.</p>'}
async function loadLogistics(){const r=await post('logistics');if(!r?.ok)return notice(r?.error||'Logistics unavailable.','error');logisticsData=r;renderLogistics()}
async function loadArsenalHistory(){const r=await post('arsenalHistory'),box=document.querySelector('#arsenalHistory');if(!box)return;if(!r?.ok){box.innerHTML=`<p>${esc(r?.error||'Arsenal history unavailable.')}</p>`;return}box.innerHTML=(r.history||[]).map(row=>`<article class="logistics-order"><div><strong>ARSENAL RESUPPLY · ${esc(row.status)}</strong><small>${row.endedAt?new Date(Number(row.endedAt)*1000).toLocaleString():'In progress'} · Army ${Number(row.armyPercent||0)}% · Gangs ${Number(row.gangPercent||0)}% · Lost ${Number(row.lostPercent||0)}%</small><details><summary>VIEW DETAILS</summary><small>Reference ${esc(row.eventId)} · ${esc(row.reason||'No result reason')}</small><small>Incoming ${Number(row.totalValue||0).toLocaleString()} value · Army ${Number(row.armyValue||0).toLocaleString()} · Gangs ${Number(row.gangValue||0).toLocaleString()} · Lost ${Number(row.lostValue||0).toLocaleString()}</small><small>${(row.standings||[]).map(g=>`${esc(String(g.gang_id||g.gangId||'').toUpperCase())}: ${Number(g.percent||0)}%`).join(' · ')||'No gang extraction'}</small></details></div></article>`).join('')||'<p>No Arsenal history.</p>'}
document.querySelector('#logisticsOrderForm').onsubmit=async e=>{e.preventDefault();const r=await post('logisticsCreate',{lines:[{itemName:document.querySelector('#logisticsItem').value,quantity:Number(document.querySelector('#logisticsQuantity').value||0)}]});notice(r.message||r.error,r.ok?'success':'error');if(r.ok)loadLogistics()};
document.querySelector('#logisticsOrders').onclick=async e=>{const b=e.target.closest('[data-logistics-action]');if(!b)return;const r=await post('logisticsAction',{action:b.dataset.logisticsAction,orderId:Number(b.dataset.orderId)});notice(r.message||r.error,r.ok?'success':'error');if(r.ok)loadLogistics()};
const pageTitles={overview:'Overview',roster:'Members',ranks:'Ranks & Access',facilities:'Facilities',fleet:'Fleet Vehicles',logs:'Activity Logs',custody:'Custody',dispatch:'Dispatch',mdt:'Shared MDT',logistics:'Logistics',charges:'Criminal Code'};
document.querySelectorAll('.tab').forEach(b=>b.onclick=()=>{b.closest('.nav-more')?.setAttribute('open','');document.querySelectorAll('.tab').forEach(x=>x.classList.remove('active'));b.classList.add('active');document.querySelectorAll('.view').forEach(x=>x.classList.add('hidden'));document.querySelector(`#${b.dataset.tab}View`).classList.remove('hidden');document.querySelector('#pageTitle').textContent=pageTitles[b.dataset.tab]||b.dataset.tab;if(b.dataset.tab==='dispatch'){loadDispatchActiveCalls();loadDispatchHistory()}if(b.dataset.tab==='fleet')loadFleet();if(b.dataset.tab==='logs')loadActivityLog();if(b.dataset.tab==='custody')loadCustody();if(b.dataset.tab==='logistics'){loadLogistics();loadArsenalHistory()}if(b.dataset.tab==='mdt')loadMdtDashboard();if(b.dataset.tab==='charges')loadCriminalCode()});

// ── Criminal Code (F6 -> Criminal Code, leaders/cm-admin only) ─────────────
let chargeRows=[];
function renderCharges(){
  document.querySelector('#chargesList').innerHTML=chargeRows.map(c=>`<article class="charge-row${c.enabled?'':' is-disabled'}" data-charge-id="${esc(c.id)}">
    <input class="charge-row__label" data-field="label" value="${esc(c.label)}" maxlength="96">
    <label>Jail<input data-field="jailMinutes" type="number" min="0" max="180" value="${Number(c.jailMinutes||0)}"></label>
    <label>Fine<input data-field="fine" type="number" min="0" max="100000" value="${Number(c.fine||0)}"></label>
    <label class="charge-row__enabled"><input data-field="enabled" type="checkbox" ${c.enabled?'checked':''}>Enabled</label>
    <div class="actions"><button data-charge-save>Save</button><button class="danger" data-charge-delete>Delete</button></div>
  </article>`).join('')||'<p class="hint">No charges in the Criminal Code yet.</p>';
}
async function loadCriminalCode(){const r=await post('lawListCharges');if(!r?.ok)return notice(r?.error||'Criminal Code unavailable.','error');chargeRows=r.charges||[];renderCharges()}
document.querySelector('#chargeCreateForm').onsubmit=async e=>{
  e.preventDefault();
  const label=document.querySelector('#chargeNewLabel').value,jailMinutes=Number(document.querySelector('#chargeNewJail').value||0),fine=Number(document.querySelector('#chargeNewFine').value||0);
  const r=await post('lawCreateCharge',{label,jailMinutes,fine});
  notice(r.message||r.error,r.ok?'success':'error');
  if(r.ok){document.querySelector('#chargeCreateForm').reset();loadCriminalCode()}
};
document.querySelector('#chargesList').onclick=async e=>{
  const row=e.target.closest('[data-charge-id]');if(!row)return;
  const id=row.dataset.chargeId;
  if(e.target.closest('[data-charge-save]')){
    const label=row.querySelector('[data-field="label"]').value,jailMinutes=Number(row.querySelector('[data-field="jailMinutes"]').value||0),fine=Number(row.querySelector('[data-field="fine"]').value||0),enabled=row.querySelector('[data-field="enabled"]').checked;
    const r=await post('lawUpdateCharge',{id,label,jailMinutes,fine,enabled});
    notice(r.message||r.error,r.ok?'success':'error');
    if(r.ok)loadCriminalCode();
  }
  if(e.target.closest('[data-charge-delete]')){
    if(!(await showConfirmOverlay('Delete charge','Remove this charge from the Criminal Code? Past bookings keep their own record of it regardless.','Delete','Cancel')))return;
    const r=await post('lawDeleteCharge',{id});
    notice(r.message||r.error,r.ok?'success':'error');
    if(r.ok)loadCriminalCode();
  }
};
document.querySelector('#arsenalHistoryRefresh')?.addEventListener('click',loadArsenalHistory);
roster.onclick=async e=>{const b=e.target.closest('[data-action]');if(!b)return;const action=b.dataset.action,cid=b.dataset.cid;if(action==='fire'&&!(await showConfirmOverlay('Remove member','Remove this member from the organization?','Remove','Cancel')))return;const rank=roster.querySelector(`[data-rank="${CSS.escape(cid)}"]`);const r=await post('staffAction',{action,characterId:cid,rankId:rank?Number(rank.value):null});notice(r.message||r.error,r.ok?'success':'error')};

async function refresh(){ const data = await post('refresh'); if (data && data.ok !== false) render(data); }
document.querySelector('#dashboardRefresh').onclick=async e=>{const button=e.currentTarget;button.disabled=true;try{await refresh()}finally{button.disabled=false}};
document.querySelector('#overviewLaunchMdt')?.addEventListener('click',()=>document.querySelector('#mdtTab')?.click());
document.querySelector('#overviewDispatch')?.addEventListener('click',()=>document.querySelector('#dispatchTab')?.click());
document.querySelector('#dashboardDutyButton').onclick=async e=>{const button=e.currentTarget;if(!state?.member?.onDuty)return;if(!(await showConfirmOverlay('End duty','End your current legal organization shift?','End duty','Cancel')))return;button.disabled=true;try{const r=await post('endDuty');notice(r.message||r.error,r.ok?'success':'error');if(r.ok)await refresh()}finally{button.disabled=false}};
document.querySelector('#overviewCapturePhoto').onclick=async e=>{const button=e.currentTarget;button.disabled=true;try{const r=await post('setMemberPhoto');notice(r.message||r.error,r.ok?'success':'error');if(r.ok)await refresh()}finally{button.disabled=false}};
function updateDashboardClock(){const clock=document.querySelector('#dashboardClock');if(clock)clock.textContent=new Intl.DateTimeFormat(undefined,{hour:'2-digit',minute:'2-digit'}).format(new Date())}
updateDashboardClock();setInterval(updateDashboardClock,30000);
const facilityPrompt=document.querySelector('#facilityPrompt'),facilityDialogue=document.querySelector('#facilityDialogue');
window.addEventListener('message',e=>{const d=e.data||{};if(d.action==='facilityPrompt'){facilityPrompt.classList.toggle('hidden',!d.visible);document.querySelector('#facilityPromptText').textContent=d.name?`${d.name} · ${d.role||''}`:''}if(d.action==='facilityDialogue'){facilityDialogue.className=`npc-dialogue${d.visible?'':' hidden'}`;if(d.visible){document.querySelector('#facilityName').textContent=d.name||'';document.querySelector('#facilityRole').textContent=d.role||'';document.querySelector('#facilityQuote').textContent=d.quote||'';document.querySelector('#facilitySignature').textContent=`— ${d.name||''}`;document.querySelector('#facilityContinue').textContent=d.continueLabel||'Continue'}}if(d.action==='facilityDialogueResponse'){facilityDialogue.className=`npc-dialogue response ${d.tone||'inform'}`;document.querySelector('#facilityQuote').textContent=d.message||''}});
// Delegated fallback for the facility iframe: keeps controls working even
// when a layered dashboard stylesheet replaces a direct button handler.
document.addEventListener('click', (event) => {
  const target = event.target.closest?.('#facilityContinue,#facilityClose');
  if (!target) return;
  event.preventDefault();
  post(target.id === 'facilityContinue' ? 'facilityDialogueContinue' : 'facilityDialogueClose');
}, true);
const facilityOptions=document.querySelector('#facilityOptions');
window.addEventListener('message',e=>{const d=e.data||{};if(d.action==='facilityDialogue'){facilityOptions.classList.add('hidden');facilityOptions.innerHTML=''}if(d.action==='facilityDialogueChoices'){facilityDialogue.className='npc-dialogue services';document.querySelector('#facilityQuote').textContent=d.message||'How can I help you?';facilityOptions.innerHTML=(d.choices||[]).map(x=>`<button class="npc-dialogue__option ${x.primary?'npc-dialogue__option--primary':''}" data-facility-service="${esc(x.id)}">${esc(x.label)}${x.description?`<small>${esc(x.description)}</small>`:''}</button>`).join('');facilityOptions.classList.remove('hidden')}if(d.action==='facilityDialogueResponse')facilityOptions.classList.add('hidden')});
facilityOptions.addEventListener('click',e=>{const b=e.target.closest('[data-facility-service]');if(!b)return;e.preventDefault();post('facilityPublicService',{service:b.dataset.facilityService})},true);

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
document.querySelector('#armoryGrid').onclick=async e=>{const b=e.target.closest('[data-armory-checkout]');if(!b)return;b.disabled=true;const r=await post('legalArmoryCheckout',{itemName:b.dataset.armoryCheckout});notice(r.message||r.error,r.ok?'success':'error');if(r.ok&&r.armory){armoryData=r.armory;renderArmory()}else{const fresh=await post('legalArmoryRefresh');if(fresh?.ok){armoryData=fresh;renderArmory()}}b.disabled=false};
document.querySelector('#lawArmorList').onclick=e=>document.querySelector('#armoryGrid').onclick(e);
document.querySelector('#armoryManage').onclick=async()=>{const r=await post('legalArmoryManagement');if(!r?.ok)return notice(r?.error||'Management unavailable.','error');armoryManagement=r.items||[];renderArmoryManagement();armoryManager.classList.remove('hidden')};
document.querySelector('#armoryManagerClose').onclick=async()=>{armoryManager.classList.add('hidden');const r=await post('legalArmoryRefresh');if(r?.ok){armoryData=r;renderArmory()}};
document.querySelector('#armoryManagerGrid').onclick=async e=>{const b=e.target.closest('[data-armory-save]');if(!b)return;const row=b.closest('[data-armory-item]');const data={itemName:row.dataset.armoryItem,enabled:row.querySelector('[data-field="enabled"]').checked};b.disabled=true;const r=await post('legalArmorySave',data);b.disabled=false;notice(r.message||r.error,r.ok?'success':'error');if(r.ok){const fresh=await post('legalArmoryManagement');armoryManagement=fresh.items||armoryManagement;renderArmoryManagement()}};
document.querySelector('#armoryLoadStock').onclick=async()=>{const button=document.querySelector('#armoryLoadStock');button.disabled=true;const r=await post('legalArmoryLoadStock');button.disabled=false;notice(r.message||r.error,r.ok?'success':'error');if(r.ok){const fresh=await post('legalArmoryManagement');armoryManagement=fresh.items||armoryManagement;renderArmoryManagement()}};

// Shared legal MDT
let lawMdtProfile=null;
const mdtResults=document.querySelector('#lawMdtResults'),mdtWorkspace=document.querySelector('#lawMdtWorkspace');
function mdtList(rows,renderer,empty){return (rows||[]).map(renderer).join('')||`<p class="hint">${esc(empty)}</p>`}
const caseStatuses=['open','under_review','closed'];
function renderCaseFile(x){
  const evidence=x.evidence||[],officers=x.linkedOfficers||[];
  return `<details class="mdt-record mdt-case" data-report-id="${x.id}">
    <summary><strong>#${x.id} · ${esc(x.title)}</strong> <span>${esc(x.organization_id).toUpperCase()} · <select data-case-status>${caseStatuses.map(s=>`<option value="${s}" ${x.status===s?'selected':''}>${esc(s.replace('_',' '))}</option>`).join('')}</select></span></summary>
    ${x.summary?`<p class="case-summary">${esc(x.summary)}</p>`:''}
    <p>${esc(x.narrative)}</p>
    <div class="case-photo-row">${x.photo_url?`<img class="case-photo" src="${esc(x.photo_url)}" alt="">`:'<span class="hint">No scene photo attached.</span>'}<button data-case-photo>Capture scene photo</button></div>
    <div class="case-section"><small>EVIDENCE</small>${mdtList(evidence,e=>`<div class="mdt-record"><strong>${esc(e.label)}</strong><span>${esc(e.note||'')}</span><time>${esc(e.loggedBy||'')} · ${esc(e.loggedAt||'')}</time></div>`,'No evidence logged.')}
      <div class="law-mdt-compose"><input class="case-evidence-label" maxlength="80" placeholder="Evidence label"><input class="case-evidence-note" maxlength="400" placeholder="Note"><button data-case-add-evidence>Log evidence</button></div>
    </div>
    <div class="case-section"><small>LINKED OFFICERS</small>${mdtList(officers,o=>`<div class="mdt-record"><strong>${esc(o.name||('CID '+o.characterId))}</strong><span>CID ${esc(o.characterId)}</span></div>`,'No officers linked.')}
      <div class="law-mdt-compose"><input class="case-officer-cid" maxlength="64" placeholder="Officer character ID"><button data-case-link-officer>Link officer</button></div>
    </div>
    <time>${esc(x.created_at)}</time>
  </details>`;
}
function renderLawMdtProfile(profile){
  lawMdtProfile=profile;const cid=esc(profile.characterId),wanted=profile.wanted;
  mdtWorkspace.innerHTML=`<section class="law-mdt-profile"><header class="law-mdt-profile__head"><img class="mdt-profile-photo" src="${esc(profile.photoUrl||'')}" alt="" onerror="this.style.visibility='hidden'" ${profile.photoUrl?'':'style="visibility:hidden"'}><div><small>CITIZEN ${cid}</small><h2>${esc(profile.name)}</h2></div><button data-mdt-capture-photo>Capture photo</button><span class="badge ${wanted?'suspended':'on'}">${wanted?`${profile.stars} STAR WANTED`:'NOT WANTED'}</span></header>
  <div class="law-mdt-actions"><label>Stars<input id="lawMdtStars" type="number" min="0" max="5" value="${Number(profile.stars||0)}"></label><label>Wanted reason<input id="lawMdtWantedReason" maxlength="160" value="${esc(profile.wantedReason||'')}"></label><button data-mdt-wanted>Update wanted</button></div>
  <div class="law-mdt-columns"><article class="card"><small>LICENCES</small>${mdtList(profile.licenses,x=>`<div class="mdt-record"><strong>${esc(x.license_type)}</strong><span>${esc(x.status)}${x.license_number?` · ${esc(x.license_number)}`:''}${x.reason?` · ${esc(x.reason)}`:''}</span></div>`,'No licence records')}
    <div class="law-mdt-compose law-mdt-license-compose"><select id="lawMdtLicenseType">${(profile.licenseTypes||[]).map(t=>`<option value="${esc(t)}">${esc(t)}</option>`).join('')}</select><select id="lawMdtLicenseStatus"><option value="active">Active</option><option value="revoked">Revoked</option></select><input id="lawMdtLicenseReason" maxlength="160" placeholder="Reason (optional)"><button data-mdt-license>Apply</button></div>
  </article><article class="card"><small>REGISTERED VEHICLES</small>${mdtList(profile.vehicles,x=>`<button class="mdt-record mdt-record--button" data-mdt-plate="${esc(x.plate)}"><strong>${esc(x.plate)}</strong><span>${esc(x.label||x.model)}${x.licenseNumber?` · ${esc(x.licenseNumber)}`:''}</span></button>`,'No vehicles')}</article></div>
  <div class="law-mdt-compose"><textarea id="lawMdtNote" maxlength="1000" placeholder="Shared agency note"></textarea><button data-mdt-note>Add note</button></div>
  <article class="card"><small>SHARED NOTES</small>${mdtList(profile.notes,x=>`<div class="mdt-record"><strong>${esc(x.organization_id).toUpperCase()} · ${esc(x.author_name||x.author_cid)}</strong><span>${esc(x.note)}</span><time>${esc(x.created_at)}</time></div>`,'No notes')}</article>
  <div class="law-mdt-compose law-mdt-compose--report"><input id="lawMdtReportTitle" maxlength="120" placeholder="Report title"><input id="lawMdtReportSummary" maxlength="300" placeholder="Short case summary (optional)"><textarea id="lawMdtReportNarrative" maxlength="6000" placeholder="Detailed incident narrative"></textarea><button data-mdt-report>Create report</button></div>
  <article class="card"><small>SHARED CASE FILES</small>${mdtList(profile.reports,renderCaseFile,'No reports')}</article>
  <div class="law-mdt-compose law-mdt-warrant-compose"><input id="lawMdtWarrantReason" maxlength="1000" placeholder="Warrant reason"><input id="lawMdtWarrantStars" type="number" min="1" max="5" value="1"><button data-mdt-warrant>Create warrant</button></div>
  <article class="card"><small>SHARED WARRANTS</small>${mdtList(profile.warrants,x=>`<div class="mdt-record"><strong>#${x.id} · ${esc(x.organization_id).toUpperCase()} · ${x.stars} star</strong><span>${esc(x.reason)}</span><time>${esc(x.created_at)}</time>${x.status==='active'?`<button data-mdt-close-warrant="${x.id}">Close warrant</button>`:`<em>${esc(x.status)}</em>`}</div>`,'No warrants')}</article>
  <article class="card"><small>SHARED LEGAL BOOKING HISTORY</small>${mdtList(profile.legalBookings,x=>`<div class="mdt-record"><strong>${esc(x.organization_id)} booking #${x.id} · ${Number(x.sentence_minutes||0)} minutes${Number(x.fine_amount||0)>0?` · $${Number(x.fine_amount).toLocaleString()} fine`:''}</strong><span>${esc((x.charges||[]).map(c=>c.label).join(', ')||'No charges')} · ${esc(x.reason||'No reason')} · ${esc(x.handoff_status||'unknown')}</span><time>${esc(x.booked_at||'')}</time></div>`,'No shared legal bookings')}</article>
  <div class="law-mdt-columns"><article class="card"><small>CITATION HISTORY</small>${mdtList(profile.citations,x=>`<div class="mdt-record"><strong>${esc(x.violation_label||'Citation')} · $${Number(x.fine||0).toLocaleString()}</strong><time>${esc(x.created_at||'')}</time></div>`,'No citations')}</article><article class="card"><small>POLICE BOOKING HISTORY</small>${mdtList(profile.bookings,x=>`<div class="mdt-record"><strong>Booking #${x.id} · ${Number(x.wanted_stars||0)} stars</strong><span>${esc(x.reason||'No reason')} · ${Number(x.sentence_minutes||0)} minutes · ${esc(x.handoff_status||'unknown')}</span><time>${esc(x.booked_at||'')}</time></div>`,'No police bookings')}</article></div></section>`;
}
async function loadLawMdtProfile(characterId){const r=await post('lawMdtCitizenProfile',{characterId});if(!r?.ok)return notice(r?.error||'Profile unavailable.','error');document.querySelector('#lawMdtIdle').hidden=true;document.querySelector('#lawMdtDashboard').hidden=true;renderLawMdtProfile(r.profile)}
// ── MDT dashboard (idle-view landing page): active warrants, active BOLOs,
// recent incidents and stats -- one aggregated call (cm-law:server:mdtDashboard),
// each section rendered independently so a missing section just shows empty.
function renderMdtDashboard(data){
  document.querySelector('#lawMdtIdle').hidden=true;document.querySelector('#lawMdtDashboard').hidden=false;
  const stats=data?.stats||{};
  document.querySelector('#lawMdtDashboardStats').innerHTML=[
    ['ACTIVE WARRANTS',Number(stats.activeWarrants||0)],
    ['ACTIVE BOLOS',Number(stats.activeBolos||0)],
    ['ACTIVE DISPATCH CALLS',Number(stats.activeCalls||0)],
  ].map(([label,value])=>`<div class="stat"><small>${esc(label)}</small><strong>${value.toLocaleString()}</strong></div>`).join('');
  document.querySelector('#lawMdtBoloList').innerHTML=mdtList(data?.bolos,x=>`<div class="mdt-record"><strong>${esc(x.plate)}</strong><span>${esc(x.description)} · ${esc(String(x.organization_id||'').toUpperCase())}</span><time>${esc(formatTerminalTime(x.created_at))}</time><button data-mdt-bolo-clear="${x.id}">Clear</button></div>`,'No active BOLOs.');
  document.querySelector('#lawMdtDashboardWarrants').innerHTML=mdtList(data?.warrants,x=>`<button class="mdt-record mdt-record--button" data-mdt-cid="${esc(x.target_cid)}"><strong>${esc(x.target_name||('CID '+x.target_cid))} · ${x.stars} star</strong><span>${esc(x.reason)} · ${esc(String(x.organization_id||'').toUpperCase())}</span><time>${esc(formatTerminalTime(x.created_at))}</time></button>`,'No active warrants.');
  document.querySelector('#lawMdtDashboardIncidents').innerHTML=mdtList(data?.incidents,x=>`<div class="mdt-record"><strong>${esc(x.details)}</strong><span>${esc(x.location||'Unknown location')} · ${esc(x.status)}</span><time>${esc(formatTerminalTime(x.created_at))}</time></div>`,'No recent incidents.');
}
async function loadMdtDashboard(){const r=await post('lawMdtDashboard');if(!r?.ok)return;renderMdtDashboard(r)}
document.querySelector('#lawMdtDashboard').addEventListener('click',async e=>{
  const issue=e.target.closest('[data-mdt-bolo-issue]'),clear=e.target.closest('[data-mdt-bolo-clear]');
  if(issue){
    const plate=document.querySelector('#lawMdtBoloPlate').value,description=document.querySelector('#lawMdtBoloDescription').value;
    const r=await post('lawMdtIssueBolo',{plate,description});notice(r.message||r.error,r.ok?'success':'error');
    if(r.ok){document.querySelector('#lawMdtBoloPlate').value='';document.querySelector('#lawMdtBoloDescription').value='';loadMdtDashboard()}
  }
  if(clear){
    const r=await post('lawMdtClearBolo',{boloId:Number(clear.dataset.mdtBoloClear)});notice(r.message||r.error,r.ok?'success':'error');
    if(r.ok)loadMdtDashboard();
  }
});
document.querySelector('#lawMdtBoloHistoryToggle').onclick=async()=>{
  const box=document.querySelector('#lawMdtBoloHistoryList'),list=document.querySelector('#lawMdtBoloList');
  const showing=!box.hidden;
  if(showing){box.hidden=true;list.hidden=false;return}
  const r=await post('lawMdtBoloHistory');
  box.innerHTML=mdtList(r?.list,x=>`<div class="mdt-record"><strong>${esc(x.plate)}</strong><span>${esc(x.description)} · ${esc(String(x.organization_id||'').toUpperCase())} · cleared by ${esc(x.clearedByName||'Unknown')}</span><time>${esc(formatTerminalTime(x.clearedAt))}</time></div>`,'No cleared BOLOs.');
  box.hidden=false;list.hidden=true;
};
document.querySelector('#lawMdtCitizenSearch').onclick=async()=>{const r=await post('lawMdtSearchCitizens',{query:document.querySelector('#lawMdtCitizenQuery').value});if(!r?.ok)return notice(r?.error||'Search failed.','error');mdtResults.innerHTML=mdtList(r.citizens,x=>`<button class="law-mdt-result" data-mdt-cid="${esc(x.characterId)}"><strong>${esc(x.name)}</strong><span>CID ${esc(x.characterId)}${x.wanted?` · ${x.stars} STAR WANTED`:''}</span></button>`,'No citizens found')};
document.querySelector('#lawMdtVehicleSearch').onclick=async()=>{const r=await post('lawMdtVehicleSearch',{plate:document.querySelector('#lawMdtPlateQuery').value});if(!r?.ok)return notice(r?.error||'Vehicle not found.','error');document.querySelector('#lawMdtIdle').hidden=true;document.querySelector('#lawMdtDashboard').hidden=true;const v=r.vehicle;mdtWorkspace.innerHTML=`<article class="card law-mdt-vehicle">${v.bolo?`<div class="mdt-record mdt-record--alert"><strong>ACTIVE BOLO</strong><span>${esc(v.bolo.description)} · ${esc(String(v.bolo.organizationId||'').toUpperCase())}</span></div>`:''}<small>VEHICLE RECORD</small><h2>${esc(v.plate)}</h2><p>${esc(v.label||v.model)}</p><div class="mdt-record"><strong>Owner</strong><span>${esc(v.ownerName)}${v.ownerCid?` · CID ${esc(v.ownerCid)}`:''}</span></div><div class="mdt-record"><strong>Registration</strong><span>${esc(v.licenseNumber||'UNLICENSED')}</span></div><div class="mdt-record"><strong>Impound</strong><span>${v.impound?`${esc(v.impound.reason)} · $${Number(v.impound.fee||0).toLocaleString()}`:'Not impounded'}</span></div>${v.ownerCid?`<button data-mdt-cid="${esc(v.ownerCid)}">Open owner profile</button>`:''}</article>`};
document.querySelector('#lawMdtCitizenQuery')?.addEventListener('keydown',e=>{if(e.key==='Enter'){e.preventDefault();document.querySelector('#lawMdtCitizenSearch')?.click()}});
document.querySelector('#lawMdtPlateQuery')?.addEventListener('keydown',e=>{if(e.key==='Enter'){e.preventDefault();document.querySelector('#lawMdtVehicleSearch')?.click()}});
mdtResults.onclick=e=>{const b=e.target.closest('[data-mdt-cid]');if(b)loadLawMdtProfile(b.dataset.mdtCid)};
mdtWorkspace.onclick=async e=>{
  const cidButton=e.target.closest('[data-mdt-cid]'),plateButton=e.target.closest('[data-mdt-plate]');
  if(cidButton)return loadLawMdtProfile(cidButton.dataset.mdtCid);
  if(plateButton){document.querySelector('#lawMdtPlateQuery').value=plateButton.dataset.mdtPlate;return document.querySelector('#lawMdtVehicleSearch').click()}
  if(!lawMdtProfile)return;
  const cid=lawMdtProfile.characterId;let r;
  if(e.target.closest('[data-mdt-wanted]'))r=await post('lawMdtSetWanted',{characterId:cid,stars:Number(document.querySelector('#lawMdtStars').value),reason:document.querySelector('#lawMdtWantedReason').value});
  if(e.target.closest('[data-mdt-note]'))r=await post('lawMdtAddNote',{characterId:cid,note:document.querySelector('#lawMdtNote').value});
  if(e.target.closest('[data-mdt-report]'))r=await post('lawMdtCreateReport',{characterId:cid,title:document.querySelector('#lawMdtReportTitle').value,summary:document.querySelector('#lawMdtReportSummary').value,narrative:document.querySelector('#lawMdtReportNarrative').value});
  if(e.target.closest('[data-mdt-warrant]'))r=await post('lawMdtCreateWarrant',{characterId:cid,stars:Number(document.querySelector('#lawMdtWarrantStars').value),reason:document.querySelector('#lawMdtWarrantReason').value});
  const close=e.target.closest('[data-mdt-close-warrant]');if(close)r=await post('lawMdtCloseWarrant',{warrantId:Number(close.dataset.mdtCloseWarrant)});
  if(e.target.closest('[data-mdt-capture-photo]')){const cr=await post('lawMdtCapturePhoto',{characterId:cid});notice(cr.message||cr.error,cr.ok?'success':'error');if(cr.ok)loadLawMdtProfile(cid);return}
  if(e.target.closest('[data-mdt-license]')){
    const licenseType=document.querySelector('#lawMdtLicenseType').value,status=document.querySelector('#lawMdtLicenseStatus').value,licenseReason=document.querySelector('#lawMdtLicenseReason').value;
    const lr=await post('lawMdtSetLicenseStatus',{characterId:cid,licenseType,status,reason:licenseReason});
    notice(lr.message||lr.error,lr.ok?'success':'error');if(lr.ok)loadLawMdtProfile(cid);return;
  }
  const caseEl=e.target.closest('[data-report-id]');
  if(caseEl){
    const reportId=Number(caseEl.dataset.reportId);
    if(e.target.closest('[data-case-photo]')){const cr=await post('lawMdtCaptureReportPhoto',{reportId});notice(cr.message||cr.error,cr.ok?'success':'error');if(cr.ok)loadLawMdtProfile(cid);return}
    if(e.target.closest('[data-case-add-evidence]')){
      const label=caseEl.querySelector('.case-evidence-label').value,note=caseEl.querySelector('.case-evidence-note').value;
      const cr=await post('lawMdtAddReportEvidence',{reportId,label,note});notice(cr.message||cr.error,cr.ok?'success':'error');if(cr.ok)loadLawMdtProfile(cid);return;
    }
    if(e.target.closest('[data-case-link-officer]')){
      const officerCid=caseEl.querySelector('.case-officer-cid').value;
      const cr=await post('lawMdtLinkReportOfficer',{reportId,officerCid});notice(cr.message||cr.error,cr.ok?'success':'error');if(cr.ok)loadLawMdtProfile(cid);return;
    }
  }
  if(r){notice(r.message||r.error,r.ok?'success':'error');if(r.ok)loadLawMdtProfile(cid)}
};
mdtWorkspace.addEventListener('change',async e=>{
  const select=e.target.closest('[data-case-status]');if(!select||!lawMdtProfile)return;
  const caseEl=select.closest('[data-report-id]');if(!caseEl)return;
  const cid=lawMdtProfile.characterId,reportId=Number(caseEl.dataset.reportId);
  const r=await post('lawMdtSetReportStatus',{reportId,status:select.value});
  notice(r.message||r.error,r.ok?'success':'error');
  if(r.ok)loadLawMdtProfile(cid);
});

// ── In-world dashboard laptop glance (client/laptop_terminal.lua) ──────────
// A DUI created on a vehicle dashboard loads this same page with
// ?embedded=laptop. DUIs never receive SendNUIMessage (mouse-only native
// input, matching FiveM's platform limits noted in shared/config.lua), so
// this bootstraps itself instead of waiting for the usual 'open' message,
// and periodically refreshes to look live. It is read-only glance UI --
// actual interaction happens through the normal fullscreen panel.
(function(){
  const params=new URLSearchParams(location.search);
  if(params.get('embedded')!=='laptop')return;
  app.classList.add('hidden','standalone-interface','standalone-mdt');
  const boot=async()=>{
    const data=await post('refresh');
    if(!data||data.ok===false)return;
    app.classList.remove('hidden');
    render(data);
    document.querySelectorAll('.view').forEach(x=>x.classList.add('hidden'));
    document.querySelector('#mdtView')?.classList.remove('hidden');
    loadMdtDashboard();
  };
  boot();
  setInterval(boot,5000);
})();
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
  if(!(await showConfirmOverlay('Set meeting point','Set the meeting point at your current position? Every online member of your organization gets a map route to it.','Set point','Cancel')))return;
  const r=await post('setMeetingPoint',{});
  notice(r.message||r.error,r.ok?'success':'error');
};
document.querySelector('#clearMeeting').onclick=async()=>{
  if(!(await showConfirmOverlay('Clear meeting point','Clear the meeting point for everyone in your organization?','Clear','Cancel')))return;
  const r=await post('setMeetingPoint',{clear:true});
  notice(r.message||r.error,r.ok?'success':'error');
};

// Local design preview uses the production law.html, app.js and CSS. It is
// deliberately query-string gated, so mock data can never run in FiveM NUI.
if(previewMode){
  app.classList.remove('hidden');
  render(previewPayload(previewOrg));
  document.querySelectorAll('.tab').forEach(button=>button.classList.remove('hidden'));
}
