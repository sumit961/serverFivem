const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cm-items';
const post = (name, data={}) => fetch(`https://${resource}/${name}`, {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(data)}).then(r=>r.json().catch(()=>({}))).catch(()=>({success:false,message:'NUI post failed'}));
const app=document.getElementById('app'), grid=document.getElementById('grid'), stats=document.getElementById('stats'), search=document.getElementById('search'), mode=document.getElementById('mode'), tabs=document.getElementById('tabs');
const propModal=document.getElementById('propModal');
let payload={items:[],catalog:[]};
let activeCat='all';
let editing=null;

function esc(v){return String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]))}
function allRows(){const m=mode.value; if(m==='items')return payload.items; if(m==='catalog')return payload.catalog; return [...payload.items,...payload.catalog];}
function rowText(r){return [r.kind,r.source,r.name,r.label,r.category,r.itemType,r.gender,r.shop,r.equipmentSlot,r.worldModel,r.propModel].join(' ').toLowerCase();}
function canGive(r){return r.kind==='catalog' || (r.kind==='item' && r.inventory!==false && r.virtual!==true);}
function canDelete(r){return r.deletable===true || r.kind==='catalog' || r.source==='catalog' || r.source==='clothing_catalog';}
// Clothing shares ONE prop for all clothes, so no per-item prop editing for it.
function canSetProp(r){return r.kind==='item' && String(r.category||'').toLowerCase()!=='clothing' && String(r.name||'').indexOf('clothing_')!==0;}

function pushStatus(message, ok){
  const current = stats.innerHTML;
  stats.innerHTML = `${current}<span class="pill ${ok?'ok':'bad'}">${esc(message)}</span>`;
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

async function giveRow(index){
  const row=(window.__renderRows||[])[index]; if(!row) return;
  const res=await post('previewGiveItem', row);
  pushStatus(res.success?`Added ${res.itemName||row.name}`:(res.message||'Could not add item'), !!res.success);
}
async function deleteRow(index){
  const row=(window.__renderRows||[])[index]; if(!row) return;
  const label=row.label||row.name||'this item';
  if(!confirm(`Delete ${label} from the server registry?\n\nThis removes SQL catalog entries. Static shared/items.lua items must be removed from code.`)) return;
  const res=await post('previewDeleteItem', row);
  pushStatus(res.success?`Deleted ${res.itemName||row.name}`:(res.message||'Could not delete item'), !!res.success);
}

function openProp(index){
  const row=(window.__renderRows||[])[index]; if(!row) return;
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

function render(){
  renderTabs();
  const q=search.value.trim().toLowerCase();
  const rows=allRows().filter(r=>(activeCat==='all'||String(r.category||'misc').toLowerCase()===activeCat) && (!q||rowText(r).includes(q)));
  window.__renderRows=rows;
  stats.innerHTML=`<span class="pill">Items: ${payload.items.length}</span><span class="pill">Catalog: ${payload.catalog.length}</span><span class="pill">Showing: ${rows.length}</span>`;
  grid.innerHTML=rows.map((r,i)=>{
    const propLine = r.kind==='item' ? `<br>prop: ${esc(r.propModel||'-')}${r.propOverride?' •set':''}` : (r.worldModel?`<br>model: ${esc(r.worldModel)}`:'');
    const catMeta = r.kind==='catalog' ? ` • ${esc(r.gender)} • ${esc(r.componentIndex)}:${esc(r.drawableId)}:${esc(r.textureId)}` : '';
    return `<article class="card"><div class="thumb"><img src="${esc(r.image)}" onerror="this.src='nui://cm-items/ui/images/clothing.png'"></div>`+
    `<div class="body"><div class="name">${esc(r.label||r.name)}</div>`+
    `<div class="meta">${esc(r.name)}<br>${esc(r.category||'misc')} • ${esc(r.source||'static')}${catMeta}${r.equipmentSlot?` • slot ${esc(r.equipmentSlot)}`:''}${propLine}</div>`+
    `${r.price!==undefined?`<div class="meta price">$${Number(r.price)||0}</div>`:''}`+
    `<div class="row-actions"><span class="tag ${r.enabled===false?'off':''}">${esc(r.kind)}${r.enabled===false?' disabled':''}</span>`+
    `<div class="buttons">${r.kind==='item'?`<button class="img" onclick="openImage(${i})">Img</button>`:''}${canSetProp(r)?`<button class="prop ${r.propOverride?'set':''}" onclick="openProp(${i})">Prop</button>`:''}${canGive(r)?`<button class="give" onclick="giveRow(${i})">Get</button>`:''}${canDelete(r)?`<button class="delete" onclick="deleteRow(${i})">Delete</button>`:''}</div></div></div></article>`;
  }).join('');
}

window.giveRow=giveRow; window.deleteRow=deleteRow; window.openProp=openProp;

// ---------- Set item image (used everywhere) ----------
const imgInput=document.createElement('input');
imgInput.type='file'; imgInput.accept='image/*'; imgInput.style.display='none';
document.body.appendChild(imgInput);
let imgTarget=null;
function openImage(index){ const r=(window.__renderRows||[])[index]; if(!r) return; imgTarget=r.name; imgInput.value=''; imgInput.click(); }
window.openImage=openImage;
imgInput.onchange=()=>{
  const f=imgInput.files[0]; if(!f||!imgTarget) return;
  const fr=new FileReader();
  fr.onload=async()=>{ const res=await post('previewSetImage',{name:imgTarget, imageData:fr.result}); pushStatus(res.success?`Image set for ${imgTarget}`:(res.message||'Image failed'), !!res.success); };
  fr.readAsDataURL(f);
};

// Prop modal buttons
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

window.addEventListener('message', e=>{const d=e.data||{}; if(d.type==='openItemPreview'){payload=d.payload||payload; app.classList.remove('hidden'); render()} if(d.type==='closeItemPreview'){app.classList.add('hidden'); closeProp()}});
search.oninput=render; mode.onchange=render;
document.getElementById('refresh').onclick=()=>post('refreshItemPreview');
document.getElementById('close').onclick=()=>post('closeItemPreview');
document.addEventListener('keydown',e=>{if(e.key==='Escape'){ if(!propModal.classList.contains('hidden')){closeProp();} else {post('closeItemPreview');} }});
