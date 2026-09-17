(function () {
  'use strict';
  var root = document.getElementById('helipad-picker');
  var res = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cm-house';
  function post(name, data) { return fetch('https://' + res + '/' + name, { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(data || {}) }).catch(function(){}); }
  function close() { if (!root) return; root.classList.remove('on'); root.style.display='none'; root.setAttribute('aria-hidden','true'); post('helipad:close'); }
  function render(data) {
    var list = document.getElementById('hp-list'); list.textContent='';
    document.getElementById('hp-title').textContent = 'House #' + String(data.houseNumber || '?') + ' Helipad';
    document.getElementById('hp-subtitle').textContent = String(data.vehicles.length) + ' accessible helicopter' + (data.vehicles.length === 1 ? '' : 's');
    data.vehicles.forEach(function (vehicle) {
      var card=document.createElement('button'); card.type='button'; card.className='helipad-vehicle-card';
      if (vehicle.image && /^(nui|https?):\/\//i.test(String(vehicle.image))) { var img=document.createElement('img'); img.src=vehicle.image; img.alt=vehicle.label || 'Helicopter'; img.onerror=function(){img.remove();}; card.appendChild(img); }
      var copy=document.createElement('span'); var name=document.createElement('strong'); name.textContent=vehicle.label || vehicle.model || 'Helicopter'; var meta=document.createElement('small'); meta.textContent=(vehicle.plate || 'NO PLATE') + (vehicle.family ? ' · FAMILY' : ''); copy.appendChild(name); copy.appendChild(meta); card.appendChild(copy); card.onclick=function(){ post('helipad:call',{houseId:data.houseId,vehicleId:Number(vehicle.id)}); close(); }; list.appendChild(card);
    });
    root.style.display='grid'; root.classList.add('on'); root.setAttribute('aria-hidden','false');
  }
  root.addEventListener('click',function(e){if(e.target.closest('[data-helipad-act="close"]')) close();});
  document.addEventListener('keydown',function(e){if(e.key==='Escape' && root.classList.contains('on')) close();});
  window.addEventListener('message',function(e){if(e.data && e.data.action==='openHelipadPicker') render(e.data.data || {vehicles:[]}); if(e.data && e.data.action==='closeHelipadPicker') close();});
}());
