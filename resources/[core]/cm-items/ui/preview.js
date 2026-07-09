const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cm-items';
const post = (name, data={}) => fetch(`https://${resource}/${name}`, {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(data)}).then(r=>r.json().catch(()=>({}))).catch(()=>({success:false,message:'NUI post failed'}));
const app=document.getElementById('app'), grid=document.getElementById('grid'), stats=document.getElementById('stats'), search=document.getElementById('search'), mode=document.getElementById('mode');
let payload={items:[],catalog:[]};
function esc(v){return String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]))}
function allRows(){const m=mode.value; if(m==='items')return payload.items; if(m==='catalog')return payload.catalog; return [...payload.items,...payload.catalog];}
function rowText(r){return [r.kind,r.source,r.name,r.label,r.category,r.gender,r.shop,r.componentIndex,r.drawableId,r.textureId,r.equipmentSlot,r.worldModel].join(' ').toLowerCase();}
function canGive(r){return r.kind==='catalog' || (r.kind==='item' && r.inventory!==false && r.virtual!==true);}
function canDelete(r){return r.deletable===true || r.kind==='catalog' || r.source==='catalog' || r.source==='clothing_catalog';}
function pushStatus(message, ok){
  const current = stats.innerHTML;
  stats.innerHTML = `${current}<span class="pill ${ok?'ok':'bad'}">${esc(message)}</span>`;
}
async function giveRow(index){
  const rows = window.__renderRows || [];
  const row = rows[index];
  if(!row) return;
  const res = await post('previewGiveItem', row);
  const msg = res.success ? `Added ${res.itemName || row.name}` : (res.message || 'Could not add item');
  pushStatus(msg, !!res.success);
}
async function deleteRow(index){
  const rows = window.__renderRows || [];
  const row = rows[index];
  if(!row) return;
  const label = row.label || row.name || 'this item';
  if(!confirm(`Delete ${label} from the server registry?\n\nThis removes SQL catalog entries. Static shared/items.lua items must be removed from code.`)) return;
  const res = await post('previewDeleteItem', row);
  const msg = res.success ? `Deleted ${res.itemName || row.name}` : (res.message || 'Could not delete item');
  pushStatus(msg, !!res.success);
}
function render(){
  const q=search.value.trim().toLowerCase();
  const rows=allRows().filter(r=>!q||rowText(r).includes(q));
  window.__renderRows = rows;
  stats.innerHTML=`<span class="pill">Items: ${payload.items.length}</span><span class="pill">Catalog: ${payload.catalog.length}</span><span class="pill">Showing: ${rows.length}</span>`;
  grid.innerHTML=rows.map((r,i)=>`<article class="card"><div class="thumb"><img src="${esc(r.image)}" onerror="this.src='nui://cm-items/ui/images/clothing.png'"></div><div class="body"><div class="name">${esc(r.label||r.name)}</div><div class="meta">${esc(r.name)}<br>${esc(r.category||'misc')} • ${esc(r.source||'static')}${r.kind==='catalog'?` • ${esc(r.gender)} • ${esc(r.componentIndex)}:${esc(r.drawableId)}:${esc(r.textureId)}`:''}${r.equipmentSlot?` • slot ${esc(r.equipmentSlot)}`:''}${r.worldModel?`<br>model: ${esc(r.worldModel)}`:''}</div>${r.price!==undefined?`<div class="meta price">$${Number(r.price)||0}</div>`:''}<div class="row-actions"><span class="tag ${r.enabled===false?'off':''}">${esc(r.kind)}${r.enabled===false?' disabled':''}</span><div class="buttons">${canGive(r)?`<button class="give" onclick="giveRow(${i})">Get</button>`:''}${canDelete(r)?`<button class="delete" onclick="deleteRow(${i})">Delete</button>`:''}</div></div></div></article>`).join('');
}
window.giveRow = giveRow;
window.deleteRow = deleteRow;
window.addEventListener('message', e=>{const d=e.data||{}; if(d.type==='openItemPreview'){payload=d.payload||payload; app.classList.remove('hidden'); render()} if(d.type==='closeItemPreview'){app.classList.add('hidden')}});
search.oninput=render; mode.onchange=render; document.getElementById('refresh').onclick=()=>post('refreshItemPreview'); document.getElementById('close').onclick=()=>post('closeItemPreview'); document.addEventListener('keydown',e=>{if(e.key==='Escape')post('closeItemPreview')});
