const $ = (id) => document.getElementById(id);
let dealership = null;
function post(name, data={}){return fetch(`https://${GetParentResourceName()}/${name}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)}).catch(()=>{});}
function money(n){return new Intl.NumberFormat('en-US').format(Number(n)||0)}
function toast(msg){const t=$('toast');t.textContent=msg||'';t.classList.remove('hidden');setTimeout(()=>t.classList.add('hidden'),2500)}
function close(){ $('store').classList.add('hidden'); post('close'); }
$('close').addEventListener('click', close); document.addEventListener('keydown',e=>{if(e.key==='Escape')close();});
function render(){
  $('dealerName').textContent = dealership?.label || 'Vehicle Store';
  const grid=$('vehicleGrid'); grid.innerHTML='';
  (dealership?.vehicles||[]).forEach(v=>{
    const card=document.createElement('div'); card.className='card';
    card.innerHTML=`<div class="car-icon">🚗</div><h2>${v.label||v.model}</h2><div class="category">${v.category||'Vehicle'}</div><p class="desc">${v.description||''}</p><div class="stats"><span>Price<b>$${money(v.price)}</b></span><span>Trunk<b>Level ${v.trunkLevel||0}</b></span></div><button class="buy">Buy Vehicle</button>`;
    card.querySelector('.buy').addEventListener('click',()=>{
      if(confirm(`Buy ${v.label||v.model} for $${money(v.price)}?`)) post('buyVehicle',{model:v.model});
    });
    grid.appendChild(card);
  });
}
window.addEventListener('message',e=>{
  const d=e.data||{};
  if(d.action==='open'){ dealership=d.dealership; render(); $('store').classList.remove('hidden'); }
  if(d.action==='close') $('store').classList.add('hidden');
  if(d.action==='toast') toast(d.message);
});
