const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cm-items';
const post = (name, data={}) => fetch(`https://${resource}/${name}`, {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(data)}).then(r=>r.json().catch(()=>({}))).catch(()=>({success:false,message:'NUI post failed'}));

const app=document.getElementById('app'), grid=document.getElementById('grid'), stats=document.getElementById('stats'),
      search=document.getElementById('search'), mode=document.getElementById('mode'), tabs=document.getElementById('tabs'),
      propModal=document.getElementById('propModal'), ctxMenu=document.getElementById('ctxMenu');

let payload={items:[],catalog:[]};
let activeCat='all';
let editing=null;
let ctxRow=null, ctxCard=null;

function esc(v){return String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]))}

/* Inline placeholder — a data URI can never 404, so no error loop and no "?" boxes.
   Items without a real image show a neutral "no image" tile instead. */
const NO_IMG = 'data:image/svg+xml;utf8,' + encodeURIComponent(
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
     <rect x="8" y="12" width="48" height="40" rx="5" fill="none" stroke="rgba(255,255,255,0.18)" stroke-width="3"/>
     <circle cx="24" cy="27" r="4.5" fill="rgba(255,255,255,0.18)"/>
     <path d="M14 46l13-13 9 9 6-6 8 10z" fill="rgba(255,255,255,0.18)"/>
   </svg>`);
function imgFallback(el){
  if(el.dataset.fb) return;      // only ever run once -> no infinite onerror loop
  el.dataset.fb = '1';
  el.src = NO_IMG;
  el.classList.add('no-img');
}
window.imgFallback = imgFallback;
function allRows(){const m=mode.value; if(m==='items')return payload.items; if(m==='catalog')return payload.catalog; return [...payload.items,...payload.catalog];}
function rowText(r){return [r.kind,r.source,r.name,r.label,r.category,r.itemType,r.gender,r.shop,r.equipmentSlot,r.worldModel,r.propModel].join(' ').toLowerCase();}
function canGive(r){return r.kind==='catalog' || (r.kind==='item' && r.inventory!==false && r.virtual!==true);}
function canDelete(r){return r.deletable===true || r.kind==='catalog' || r.source==='catalog' || r.source==='clothing_catalog';}
// Clothing shares ONE prop for all clothes, so no per-item prop editing for it.
function canSetProp(r){return r.kind==='item' && String(r.category||'').toLowerCase()!=='clothing' && String(r.name||'').indexOf('clothing_')!==0;}

function pushStatus(message, ok){
  const base = `<span class="pill">Items: ${payload.items.length}</span><span class="pill">Catalog: ${payload.catalog.length}</span><span class="pill">Showing: ${(window.__renderRows||[]).length}</span>`;
  stats.innerHTML = `${base}<span class="pill ${ok?'ok':'bad'}">${esc(message)}</span>`;
}

function categories(){
  const set=new Set();
  allRows().forEach(r=>set.add(String(r.category||'misc').toLowerCase()));
  return [...set].sort();
}
function renderTabs(){
  const cats=['all',...categories()];
  if(!cats.includes(activeCat)) activeCat='all';
  tabs.innerHTML=cats.map(c=>`<button class="tab ${c===activeCat?'active':''}" data-cat="${esc(c)}">${c==='all'?'All':esc(c[0].toUpperCase()+c.slice(1))}</button>`).join('');
  tabs.querySelectorAll('.tab').forEach(b=>b.onclick=()=>{activeCat=b.dataset.cat; render();});
}

/* ================= ACTIONS (unchanged NUI callbacks) ================= */
async function giveRow(row){
  if(!row) return;
  const res=await post('previewGiveItem', row);
  pushStatus(res.success?`Added ${res.itemName||row.name}`:(res.message||'Could not add item'), !!res.success);
}
async function deleteRow(row){
  if(!row) return;
  const label=row.label||row.name||'this item';
  if(!confirm(`Delete ${label} from the server registry?\n\nThis removes SQL catalog entries. Static shared/items.lua items must be removed from code.`)) return;
  const res=await post('previewDeleteItem', row);
  pushStatus(res.success?`Deleted ${res.itemName||row.name}`:(res.message||'Could not delete item'), !!res.success);
}
function openProp(row){
  if(!row) return;
  editing=row;
  document.getElementById('propItemName').textContent=`${row.label||row.name} (${row.name})`;
  document.getElementById('propModel').value=row.propModel||'';
  document.getElementById('propZOffset').value=Number(row.propZOffset)||0;
  document.getElementById('propHeading').value=Number(row.propHeading)||0;
  propModal.classList.remove('hidden');
}
function closeProp(){editing=null; propModal.classList.add('hidden');}
function propPayload(){
  return {name:editing?editing.name:'', model:document.getElementById('propModel').value.trim(),
    zOffset:parseFloat(document.getElementById('propZOffset').value)||0,
    heading:parseFloat(document.getElementById('propHeading').value)||0};
}

/* ---------- Set item image (used everywhere the item appears) ---------- */
const imgInput=document.createElement('input');
imgInput.type='file'; imgInput.accept='image/*'; imgInput.style.display='none';
document.body.appendChild(imgInput);
let imgTarget=null;
function openImage(row){ if(!row) return; imgTarget=row.name; imgInput.value=''; imgInput.click(); }
imgInput.onchange=()=>{
  const f=imgInput.files[0]; if(!f||!imgTarget) return;
  const fr=new FileReader();
  fr.onload=async()=>{ const res=await post('previewSetImage',{name:imgTarget, imageData:fr.result}); pushStatus(res.success?`Image set for ${imgTarget}`:(res.message||'Image failed'), !!res.success); };
  fr.readAsDataURL(f);
};

async function copyName(row){
  if(!row) return;
  try{ await navigator.clipboard.writeText(row.name); pushStatus(`Copied "${row.name}"`, true); }
  catch(e){ pushStatus('Copy failed', false); }
}

/* ================= RIGHT-CLICK CONTEXT MENU ================= */
const ICONS={
  get:'<svg class="ci" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 5v14M5 12h14"/></svg>',
  img:'<svg class="ci" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="8.5" cy="9.5" r="1.5"/><path d="M21 16l-5-5-6 6"/></svg>',
  prop:'<svg class="ci" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 16V8l-9-5-9 5v8l9 5 9-5z"/><path d="M3.3 7.3L12 12l8.7-4.7M12 22V12"/></svg>',
  copy:'<svg class="ci" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="12" height="12" rx="2"/><path d="M5 15V5a2 2 0 012-2h10"/></svg>',
  del:'<svg class="ci" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6"/></svg>',
};

function closeCtx(){
  ctxMenu.classList.add('hidden');
  if(ctxCard) ctxCard.classList.remove('ctx-active');
  ctxRow=null; ctxCard=null;
}

function openCtx(x, y, row, card){
  closeCtx();
  ctxRow=row; ctxCard=card;
  card.classList.add('ctx-active');

  const items=[];
  if(canGive(row))    items.push({k:'get',  label:'Get item',      icon:ICONS.get,  cls:'green'});
  if(row.kind==='item') items.push({k:'img',label:'Set image',     icon:ICONS.img,  cls:''});
  if(canSetProp(row)) items.push({k:'prop', label:row.propOverride?'Edit drop prop':'Set drop prop', icon:ICONS.prop, cls:''});
  items.push({k:'copy', label:'Copy item name', icon:ICONS.copy, cls:''});
  if(canDelete(row))  items.push({sep:true}, {k:'del', label:'Delete item', icon:ICONS.del, cls:'danger'});

  ctxMenu.innerHTML =
    `<div class="ctx-head"><div class="ctx-title">${esc(row.label||row.name)}</div><div class="ctx-sub">${esc(row.name)}</div></div>` +
    items.map(it => it.sep
      ? '<div class="ctx-sep"></div>'
      : `<button class="ctx-item ${it.cls}" data-k="${it.k}">${it.icon}<span>${esc(it.label)}</span></button>`
    ).join('');

  ctxMenu.classList.remove('hidden');

  // Position, flipping if it would go off-screen.
  const r = ctxMenu.getBoundingClientRect();
  const px = (x + r.width  > window.innerWidth  - 8) ? x - r.width  : x;
  const py = (y + r.height > window.innerHeight - 8) ? y - r.height : y;
  ctxMenu.style.left = Math.max(8, px) + 'px';
  ctxMenu.style.top  = Math.max(8, py) + 'px';

  ctxMenu.querySelectorAll('.ctx-item').forEach(b=>{
    b.onclick=()=>{
      const k=b.dataset.k, row=ctxRow;
      closeCtx();
      if(k==='get') giveRow(row);
      else if(k==='img') openImage(row);
      else if(k==='prop') openProp(row);
      else if(k==='copy') copyName(row);
      else if(k==='del') deleteRow(row);
    };
  });
}

document.addEventListener('click', e=>{ if(!ctxMenu.contains(e.target)) closeCtx(); });
document.addEventListener('contextmenu', e=>{ if(!e.target.closest('.card')) closeCtx(); });
window.addEventListener('blur', closeCtx);
grid.addEventListener('scroll', closeCtx);

/* ================= RENDER (cards have NO buttons now) ================= */
function render(){
  closeCtx();
  renderTabs();
  const q=search.value.trim().toLowerCase();
  const rows=allRows().filter(r=>(activeCat==='all'||String(r.category||'misc').toLowerCase()===activeCat) && (!q||rowText(r).includes(q)));
  window.__renderRows=rows;
  stats.innerHTML=`<span class="pill">Items: ${payload.items.length}</span><span class="pill">Catalog: ${payload.catalog.length}</span><span class="pill">Showing: ${rows.length}</span>`;

  grid.innerHTML=rows.map((r,i)=>{
    const propLine = r.kind==='item' ? `prop: ${esc(r.propModel||'-')}` : (r.worldModel?`model: ${esc(r.worldModel)}`:'');
    const catMeta = r.kind==='catalog' ? ` • ${esc(r.gender)} • ${esc(r.componentIndex)}:${esc(r.drawableId)}:${esc(r.textureId)}` : '';
    return `<article class="card" data-i="${i}">
      <div class="thumb"><img src="${esc(r.image)}" loading="lazy" onerror="imgFallback(this)"></div>
      <div class="body">
        <div class="name">${esc(r.label||r.name)}</div>
        <div class="meta">${esc(r.name)}<br>${esc(r.category||'misc')} • ${esc(r.source||'static')}${catMeta}${r.equipmentSlot?` • slot ${esc(r.equipmentSlot)}`:''}${propLine?`<br>${propLine}`:''}</div>
        ${r.price!==undefined?`<div class="price">$${Number(r.price)||0}</div>`:''}
        <div class="card-foot">
          <span class="tag ${r.enabled===false?'off':''}">${esc(r.kind)}${r.enabled===false?' disabled':''}</span>
          ${r.propOverride?'<span class="dot prop-set" title="Custom drop prop"></span>':''}
        </div>
      </div>
    </article>`;
  }).join('') || `<div class="hint" style="grid-column:1/-1;padding:40px 0">No items match.</div>`;

  // Attach right-click to each card.
  grid.querySelectorAll('.card').forEach(card=>{
    card.addEventListener('contextmenu', e=>{
      e.preventDefault(); e.stopPropagation();
      const row=(window.__renderRows||[])[Number(card.dataset.i)];
      if(row) openCtx(e.clientX, e.clientY, row, card);
    });
  });
}

/* ================= Prop modal ================= */
document.getElementById('propCancel').onclick=closeProp;
document.getElementById('propSpawn').onclick=()=>post('previewSpawnProp', propPayload());
document.getElementById('propSave').onclick=async()=>{
  const p=propPayload();
  if(!p.model){pushStatus('Enter a prop model', false); return;}
  const res=await post('previewSetProp', p);
  pushStatus(res.success?`Prop saved for ${p.name}`:(res.message||'Save failed'), !!res.success);
  if(res.success) closeProp();
};
document.getElementById('propReset').onclick=async()=>{
  if(!editing) return;
  const res=await post('previewClearProp', {name:editing.name});
  pushStatus(res.success?`Prop reset for ${editing.name}`:(res.message||'Reset failed'), !!res.success);
  if(res.success) closeProp();
};

/* ================= Wiring ================= */
window.addEventListener('message', e=>{
  const d=e.data||{};
  if(d.type==='openItemPreview'){payload=d.payload||payload; app.classList.remove('hidden'); render();}
  if(d.type==='closeItemPreview'){app.classList.add('hidden'); closeProp(); closeCtx();}
});
search.oninput=render;
mode.onchange=render;
document.getElementById('refresh').onclick=()=>post('refreshItemPreview');
document.getElementById('close').onclick=()=>post('closeItemPreview');
document.addEventListener('keydown',e=>{
  if(e.key==='Escape'){
    if(!ctxMenu.classList.contains('hidden')){ closeCtx(); }
    else if(!propModal.classList.contains('hidden')){ closeProp(); }
    else { post('closeItemPreview'); }
  }
});
