(function(){
  'use strict';

  var root = document.getElementById('root');
  var inspectViewport = document.getElementById('inspectViewport');
  var D = null;
  var selected = {};
  var account = 'cash';
  var activeCategory = null;
  var categorySearch = '';
  var isProcessing = false;
  var toastTimer = null;
  var vehicleDragActive = false;
  var pendingAction = null;
  var activeCamera = 2;

  function $(id){ return document.getElementById(id); }
  function resourceName(){ return typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cm-tuning'; }
  function post(name, data){
    return fetch('https://' + resourceName() + '/' + name, {
      method:'POST',
      headers:{'Content-Type':'application/json; charset=UTF-8'},
      body:JSON.stringify(data || {})
    }).catch(function(){ return null; });
  }
  function number(value){ var n = Number(value); return isFinite(n) ? n : 0; }
  function money(value){ return Math.floor(number(value)).toLocaleString(); }
  var iconPaths={
    engine:'<path d="M3 10h3l2-3h6l2 3h3v7h-3l-2 2H9l-2-2H3z"/><path d="M8 10v4m4-4v4m4-4v4M6 7V5m12 5h3v3"/>',
    brakes:'<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3"/><path d="m12 4 2 5m6 3-5 2m-3 6-2-5m-6-3 5-2"/>',
    transmission:'<path d="M5 4v16m7-16v16m7-16v16M3 7h4m3 5h4m3 5h4"/><circle cx="5" cy="7" r="1.5"/><circle cx="12" cy="12" r="1.5"/><circle cx="19" cy="17" r="1.5"/>',
    suspension:'<path d="M7 3v3l4 2-4 2 4 2-4 2 4 2-4 2v3m10-18v3l-4 2 4 2-4 2 4 2-4 2 4 2v3"/>',
    armor:'<path d="M12 3 20 6v5c0 5-3.4 8.3-8 10-4.6-1.7-8-5-8-10V6z"/><path d="m8 12 2.5 2.5L16 9"/>',
    turbo:'<circle cx="12" cy="12" r="8"/><path d="M12 4v8l6 5M4 12h8"/>',
    wheel:'<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3"/><path d="M12 4v5m8 3h-5m-3 8v-5m-8-3h5"/>',
    spoiler:'<path d="M3 15h18M6 15l2-5h8l3 5M5 8h14M7 8l1-3h8l1 3"/>',
    exhaust:'<path d="M4 7h9a3 3 0 0 1 0 6H9a3 3 0 0 0 0 6h11"/><path d="M17 16h3v6"/>',
    harness:'<path d="M6 4 18 20M18 4 6 20"/><path d="M9 9h6v6H9z"/>',
    parts:'<path d="m14 6 4-3 3 3-3 4-3-1-4 4 1 3-4 4-3-3 4-4 3 1 4-4z"/>',
    paint:'<path d="M12 3s-6 6.4-6 11a6 6 0 0 0 12 0c0-4.6-6-11-6-11z"/><path d="M9 15a3 3 0 0 0 3 3"/>',
    headlight:'<path d="M5 6h7a6 6 0 0 1 0 12H5z"/><path d="m17 8 3-2m-2 6h4m-5 4 3 2"/>',
    tint:'<rect x="4" y="5" width="16" height="14" rx="2"/><path d="m7 16 9-9m-2 12 7-7"/>',
    neon:'<path d="M4 15a8 8 0 0 1 16 0M3 18h18"/><path d="M8 5 6 3m10 2 2-2m-6 3V3"/>',
    plate:'<rect x="3" y="6" width="18" height="12" rx="2"/><path d="M7 10h10m-10 4h6"/>',
    cash:'<rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="12" cy="12" r="3"/><path d="M7 9h.01M17 15h.01"/>',
    rebuild:'<path d="M14 6a5 5 0 0 0-6 6L3 17l4 4 5-5a5 5 0 0 0 6-6l-3 3-4-4z"/>'
  };
  function iconKey(key){
    key=String(key || '').toLowerCase().replace(/[^a-z0-9]/g,'');
    if(key.indexOf('brake')!==-1) return 'brakes';
    if(key.indexOf('trans')!==-1) return 'transmission';
    if(key.indexOf('susp')!==-1) return 'suspension';
    if(key.indexOf('armor')!==-1 || key.indexOf('armour')!==-1) return 'armor';
    if(key.indexOf('turbo')!==-1) return 'turbo';
    if(key.indexOf('wheel')!==-1 || key.indexOf('tyre')!==-1 || key.indexOf('tire')!==-1) return 'wheel';
    if(key.indexOf('spoiler')!==-1 || key.indexOf('wing')!==-1) return 'spoiler';
    if(key.indexOf('exhaust')!==-1) return 'exhaust';
    if(key.indexOf('harness')!==-1) return 'harness';
    if(key.indexOf('engine')!==-1) return 'engine';
    if(key.indexOf('headlight')!==-1 || key.indexOf('light')!==-1) return 'headlight';
    if(key.indexOf('tint')!==-1 || key.indexOf('window')!==-1) return 'tint';
    if(key.indexOf('neon')!==-1 || key.indexOf('underlight')!==-1) return 'neon';
    if(key.indexOf('plate')!==-1) return 'plate';
    if(key.indexOf('paint')!==-1 || key.indexOf('color')!==-1 || key.indexOf('colour')!==-1) return 'paint';
    if(key.indexOf('rebuild')!==-1 || key.indexOf('repair')!==-1) return 'rebuild';
    return Object.prototype.hasOwnProperty.call(iconPaths,key) ? key : 'parts';
  }
  function iconSvg(key){ return '<svg viewBox="0 0 24 24" aria-hidden="true">'+iconPaths[iconKey(key)]+'</svg>'; }
  function esc(value){
    return String(value == null ? '' : value).replace(/[&<>"']/g,function(c){
      return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c];
    });
  }
  function own(obj,key){ return obj && Object.prototype.hasOwnProperty.call(obj,key); }
  function balance(){ return D && D.balances ? number(D.balances[account]) : 0; }

  function slotByKey(key){
    if(!D) return null;
    for(var i=0;i<(D.slots || []).length;i++) if(D.slots[i].key===key) return D.slots[i];
    return null;
  }

  function setMeter(id,value){
    var fill=$(id), track=fill && fill.parentNode;
    var percent=Math.max(0,Math.min(100,number(value)));
    if(fill) fill.style.width=percent+'%';
    if(track) track.setAttribute('aria-valuenow',String(Math.round(percent)));
  }

  function renderPerformance(){
    if(!D) return;
    var panel=$('performancePanel');
    if(!panel) return;
    var speeds=D.speeds || [];
    var visible=speeds.length>0;
    panel.hidden=!visible;
    if(!visible) return;

    var engine=slotByKey('engine'), brakes=slotByKey('brakes'), perf=D.performance || {};
    var engineChoice=engine?(selected.slots && own(selected.slots,'engine')?selected.slots.engine:engine.current):number(perf.engineLevel)-1;
    var brakesChoice=brakes?(selected.slots && own(selected.slots,'brakes')?selected.slots.brakes:brakes.current):number(perf.brakesLevel)-1;
    var engineLevel=Math.max(0,engineChoice+1), brakesLevel=Math.max(0,brakesChoice+1);
    var engineMax=engine?Math.max(0,engine.options.length-1):number(perf.engineMax);
    var brakesMax=brakes?Math.max(0,brakes.options.length-1):number(perf.brakesMax);
    var speedLevel=Math.max(0,Math.min(speeds.length-1,engineLevel));
    if(D.shop!=='chip' && perf.engineLevel!=null) speedLevel=Math.max(0,Math.min(speeds.length-1,number(perf.engineLevel)));
    var speed=number(speeds[speedLevel]), maxSpeed=0;
    for(var i=0;i<speeds.length;i++) maxSpeed=Math.max(maxSpeed,number(speeds[i]));
    setMeter('statSpeedBar',maxSpeed>0?(speed/maxSpeed)*100:0);
    setMeter('statEngineBar',engineMax>0?(engineLevel/engineMax)*100:0);
    setMeter('statBrakesBar',brakesMax>0?(brakesLevel/brakesMax)*100:0);
  }
  function stopVehicleDrag(){
    if(!vehicleDragActive) return;
    vehicleDragActive=false;
    inspectViewport.classList.remove('dragging');
    post('mouseup',{});
  }

  inspectViewport.addEventListener('mousedown',function(event){
    if(event.button!==0 || !D || isProcessing || vehicleDragActive) return;
    event.preventDefault();
    vehicleDragActive=true;
    inspectViewport.classList.add('dragging');
    post('mousedown',{});
  });
  window.addEventListener('mouseup',stopVehicleDrag);
  document.addEventListener('mouseleave',stopVehicleDrag);
  window.addEventListener('blur',stopVehicleDrag);

  function categories(){
    var list = [];
    var i;
    if(!D) return list;
    if(D.shop === 'chip'){
      for(i=0;i<(D.slots || []).length;i++) list.push({id:'slot:'+D.slots[i].key,label:D.slots[i].label,kind:'slot',ref:D.slots[i]});
      if(D.tyres) list.push({id:'tyres',label:D.tyres.label,kind:'tyres'});
      for(i=0;i<(D.toggles || []).length;i++) list.push({id:'toggle:'+D.toggles[i].key,label:D.toggles[i].label,kind:'toggle',ref:D.toggles[i]});
      if(D.harness) list.push({id:'harness',label:D.harness.label,kind:'harness'});
      if(D.engine) list.push({id:'engine',label:'Engine Rebuild',kind:'engine'});
    }else if(D.shop === 'livery'){
      for(i=0;i<(D.slots || []).length;i++) list.push({id:'slot:'+D.slots[i].key,label:D.slots[i].label,kind:'slot',ref:D.slots[i]});
    }else{
      for(i=0;i<(D.slots || []).length;i++) list.push({id:'slot:'+D.slots[i].key,label:D.slots[i].label,kind:'slot',ref:D.slots[i]});
      for(i=0;i<(D.toggles || []).length;i++) list.push({id:'toggle:'+D.toggles[i].key,label:D.toggles[i].label,kind:'toggle',ref:D.toggles[i]});
      list.push({id:'paint',label:'Primary Colour',kind:'paint'});
      list.push({id:'paint2',label:'Secondary Colour',kind:'paint2'});
      list.push({id:'wheelcol',label:'Wheel Colour',kind:'wheelcol'});
      list.push({id:'headlight',label:'Headlights',kind:'headlight'});
      list.push({id:'tint',label:'Window Tint',kind:'tint'});
      list.push({id:'neon',label:'Neons',kind:'neon'});
      list.push({id:'plate',label:'Plate Style',kind:'plate'});
    }
    return list;
  }

  function currentChoice(category){
    var ref, value, level, current;
    if(category.kind === 'slot'){
      ref = category.ref;
      value = selected.slots && own(selected.slots,ref.key) ? selected.slots[ref.key] : ref.current;
      level = value < 0 ? 0 : value + 1;
      return {text:level ? 'LV '+level : 'STOCK',changed:selected.slots && own(selected.slots,ref.key) && value !== ref.current};
    }
    if(category.kind === 'tyres'){
      value = own(selected,'tyres') ? selected.tyres : D.tyres.current;
      return {text:value ? 'LV '+value : 'STOCK',changed:own(selected,'tyres') && value !== D.tyres.current};
    }
    if(category.kind === 'toggle'){
      ref = category.ref;
      value = selected.toggles && own(selected.toggles,ref.key) ? selected.toggles[ref.key] : ref.current;
      return {text:value ? 'ON' : 'OFF',changed:selected.toggles && own(selected.toggles,ref.key) && value !== ref.current};
    }
    if(category.kind === 'harness') return {text:D.harness.installed ? 'FITTED' : '',changed:false};
    if(category.kind === 'engine') return {text:D.engine.missing > 0 ? 'DAMAGED' : 'OK',changed:false};
    current = false;
    if(category.kind === 'paint') current = own(selected,'color') && selected.color !== D.currentPrimary;
    if(category.kind === 'paint2') current = own(selected,'color2') && selected.color2 !== D.currentSecondary;
    if(category.kind === 'wheelcol') current = own(selected,'wheelcol') && selected.wheelcol !== D.currentWheelColor;
    if(category.kind === 'headlight') current = own(selected,'headlight') && selected.headlight !== D.currentHeadlight;
    if(category.kind === 'tint') current = own(selected,'tint') && selected.tint !== D.currentTint;
    if(category.kind === 'plate') current = own(selected,'plate') && selected.plate !== D.currentPlate;
    if(category.kind === 'neon') current = own(selected,'neon') && selected.neon !== D.currentNeon;
    return {text:'',changed:current};
  }

  function estimatedCost(){
    var total = 0;
    var i, slot, choice, option, toggle, prices;
    if(!D) return total;

    for(i=0;i<(D.slots || []).length;i++){
      slot = D.slots[i];
      if(selected.slots && own(selected.slots,slot.key) && selected.slots[slot.key] !== slot.current){
        choice = selected.slots[slot.key];
        option = null;
        for(var j=0;j<slot.options.length;j++) if(slot.options[j].index === choice){ option = slot.options[j]; break; }
        if(option) total += number(option.price);
      }
    }

    if(D.tyres && own(selected,'tyres') && selected.tyres !== D.tyres.current){
      for(i=0;i<D.tyres.options.length;i++) if(D.tyres.options[i].index === selected.tyres) total += number(D.tyres.options[i].price);
    }

    for(i=0;i<(D.toggles || []).length;i++){
      toggle = D.toggles[i];
      if(selected.toggles && own(selected.toggles,toggle.key) && selected.toggles[toggle.key] !== toggle.current && selected.toggles[toggle.key] === true){
        total += number(toggle.price);
      }
    }

    if(D.shop === 'workshop'){
      prices = D.prices || {};
      if(own(selected,'color') && selected.color !== D.currentPrimary) total += number(prices.respray);
      if(own(selected,'color2') && selected.color2 !== D.currentSecondary) total += number(prices.respray);
      if(own(selected,'wheelcol') && selected.wheelcol !== D.currentWheelColor) total += number(prices.wheelColor);
      if(own(selected,'headlight') && selected.headlight !== D.currentHeadlight) total += number(prices.headlight);
      if(own(selected,'tint') && selected.tint !== D.currentTint) total += number(prices.tint);
      if(own(selected,'plate') && selected.plate !== D.currentPlate) total += number(prices.plate);
      if(own(selected,'neon') && selected.neon !== D.currentNeon && selected.neon === true) total += number(prices.neon);
    }
    return Math.max(0,Math.floor(total));
  }

  function hasChanges(){
    var changes = collectChanges();
    if(Object.keys(changes.slots || {}).length) return true;
    if(Object.keys(changes.toggles || {}).length) return true;
    return ['tyres','color','color2','wheelcol','headlight','tint','plate','neon','neonColor'].some(function(field){ return own(changes,field); });
  }

  function collectChanges(){
    var out = {slots:{},toggles:{}};
    var i, key;
    if(!D) return out;
    if(selected.slots){
      for(i=0;i<(D.slots || []).length;i++){
        key=D.slots[i].key;
        if(own(selected.slots,key) && selected.slots[key]!==D.slots[i].current) out.slots[key]=selected.slots[key];
      }
    }
    if(selected.toggles){
      for(i=0;i<(D.toggles || []).length;i++){
        key=D.toggles[i].key;
        if(own(selected.toggles,key) && selected.toggles[key]!==D.toggles[i].current) out.toggles[key]=selected.toggles[key];
      }
    }
    var originals={tyres:D.tyres && D.tyres.current,color:D.currentPrimary,color2:D.currentSecondary,wheelcol:D.currentWheelColor,headlight:D.currentHeadlight,tint:D.currentTint,plate:D.currentPlate,neon:D.currentNeon};
    var fields=['tyres','color','color2','wheelcol','headlight','tint','plate','neon'];
    for(i=0;i<fields.length;i++) if(own(selected,fields[i]) && String(selected[fields[i]])!==String(originals[fields[i]])) out[fields[i]]=selected[fields[i]];
    if(own(selected,'neonColor')){
      var current=D.currentNeonColor || {}, chosen=selected.neonColor || {};
      if(number(current.r)!==number(chosen.r) || number(current.g)!==number(chosen.g) || number(current.b)!==number(chosen.b)) out.neonColor=chosen;
    }
    return out;
  }

  function renderPayment(){
    var box = $('paymentOptions');
    if(!box || !D) return;
    var cost = estimatedCost();
    var amount = number(D.balances && D.balances.cash);
    box.innerHTML = '<div class="payment-option cash-only '+(cost>amount?'short':'')+'">'+
      '<span class="cash-icon">'+iconSvg('cash')+'</span><span class="payment-copy"><strong>Cash only</strong><small>Available balance</small></span>'+
      '<b>$'+money(amount)+'</b></div>';
  }

  function refreshCheckout(){
    if(!D) return;
    var cost = estimatedCost();
    var changed = hasChanges();
    var broke = cost > balance();
    $('totalValue').textContent = '$' + money(cost);
    $('totalValue').className = broke ? 'broke' : '';
    $('btnBuy').disabled = isProcessing || !changed || broke;
    $('buyText').textContent = broke ? 'Not enough funds' : (changed ? (cost > 0 ? 'Pay $'+money(cost) : 'Save free changes') : 'No changes');
    renderPayment();
    renderPerformance();
    renderCategories();
    var list=categories();
    for(var i=0;i<list.length;i++) if(list[i].id===activeCategory){ $('paneIndex').textContent=panePosition(list[i]); break; }
  }

  function categoryOptionCount(category){
    if(category.kind==='slot') return Math.max(0,(category.ref.options || []).length-1);
    if(category.kind==='tyres') return Math.max(0,(D.tyres.options || []).length-1);
    if(category.kind==='toggle' || category.kind==='neon') return 1;
    if(category.kind==='paint' || category.kind==='paint2' || category.kind==='wheelcol') return (D.colors || []).length;
    if(category.kind==='headlight') return (D.headlightColors || []).length;
    if(category.kind==='tint') return (D.tints || []).length;
    if(category.kind==='plate') return (D.plateStyles || []).length;
    return 1;
  }

  function panePosition(category){
    var options=[], value, position=-1, i;
    if(category.kind==='slot'){
      options=category.ref.options || [];
      value=selected.slots && own(selected.slots,category.ref.key)?selected.slots[category.ref.key]:category.ref.current;
      for(i=0;i<options.length;i++) if(options[i].index===value){position=i;break;}
    }else if(category.kind==='tyres'){
      options=D.tyres.options || [];
      value=own(selected,'tyres')?selected.tyres:D.tyres.current;
      for(i=0;i<options.length;i++) if(options[i].index===value){position=i;break;}
    }else if(category.kind==='paint' || category.kind==='paint2' || category.kind==='wheelcol' || category.kind==='headlight'){
      options=category.kind==='headlight'?(D.headlightColors || []):(D.colors || []);
      var key=category.kind==='paint'?'color':(category.kind==='paint2'?'color2':(category.kind==='wheelcol'?'wheelcol':'headlight'));
      value=own(selected,key)?selected[key]:(category.kind==='paint'?D.currentPrimary:(category.kind==='paint2'?D.currentSecondary:(category.kind==='wheelcol'?D.currentWheelColor:D.currentHeadlight)));
      for(i=0;i<options.length;i++) if(number(options[i][0])===number(value)){position=i;break;}
    }else if(category.kind==='tint' || category.kind==='plate'){
      options=category.kind==='tint'?(D.tints || []):(D.plateStyles || []);
      value=category.kind==='tint'?(own(selected,'tint')?selected.tint:D.currentTint):(own(selected,'plate')?selected.plate:D.currentPlate);
      for(i=0;i<options.length;i++) if(number(options[i][0])===number(value)){position=i;break;}
    }else if(category.kind==='toggle'){
      var toggle=category.ref, enabled=selected.toggles && own(selected.toggles,toggle.key)?selected.toggles[toggle.key]:toggle.current;
      return (enabled?2:1)+' / 2';
    }else if(category.kind==='neon'){
      return ((own(selected,'neon')?selected.neon:D.currentNeon)?2:1)+' / 2';
    }else if(category.kind==='harness' || category.kind==='engine'){
      return '1 / 1';
    }
    return options.length?(Math.max(0,position)+1)+' / '+options.length:'—';
  }

  function renderCategories(){
    var box = $('categoryList');
    if(!box || !D) return;
    var list = categories();
    if(!activeCategory && list.length) activeCategory = list[0].id;
    var found = false;
    for(var f=0;f<list.length;f++) if(list[f].id === activeCategory) found = true;
    if(!found && list.length) activeCategory = list[0].id;
    var query=String(categorySearch || '').trim().toLowerCase();
    var visible=[], html='';
    for(var i=0;i<list.length;i++){
      if(query && String(list[i].label || '').toLowerCase().indexOf(query)===-1) continue;
      visible.push(list[i]);
    }
    for(i=0;i<visible.length;i++){
      var state = currentChoice(visible[i]);
      var categoryIcon=visible[i].kind==='slot'?visible[i].ref.key:(visible[i].kind==='toggle'?visible[i].ref.key:visible[i].kind);
      html += '<button class="category-item '+(visible[i].id===activeCategory?'active ':'')+(state.changed?'changed':'')+'" data-category="'+esc(visible[i].id)+'">'+
        '<span class="category-icon">'+iconSvg(categoryIcon)+'</span><span class="category-label">'+esc(visible[i].label)+'</span><span class="category-count">'+(state.changed?'IN BASKET':categoryOptionCount(visible[i]))+'</span></button>';
    }
    if(!visible.length) html='<div class="category-empty">No categories found</div>';
    box.innerHTML = html;
    var buttons = box.querySelectorAll('[data-category]');
    for(i=0;i<buttons.length;i++) buttons[i].onclick = function(){ activeCategory=this.getAttribute('data-category'); renderCategories(); renderPane(); };
  }

  var categorySearchInput=$('categorySearch');
  if(categorySearchInput) categorySearchInput.addEventListener('input',function(){ categorySearch=this.value || ''; renderCategories(); });
  function optionCard(option,current,attributes,level,icon){
    var chosen = option._selected === true;
    var fitted = option.index === current;
    var priceLabel=fitted?'Free':(number(option.price)>0?'$'+money(option.price):'Free');
    var badge=chosen&&!fitted?'IN BASKET':(fitted?'EQUIPPED':'');
    return '<button class="card '+(chosen?'selected ':'')+(fitted?'fitted':'')+'" '+attributes+'>'+
      '<span class="card-art">'+iconSvg(icon || 'parts')+'</span><span class="card-copy"><span class="card-level">'+esc(level)+'</span>'+
      '<span class="card-name">'+esc(option.label)+'</span>'+(badge?'<span class="card-badge">'+badge+'</span>':'')+'</span>'+
      '<span class="card-price'+(fitted?' fitted':'')+'">'+priceLabel+'</span></button>';
  }

  function colourSwatches(list,key,current){
    var html = '<div class="swatches with-labels">';
    for(var i=0;i<list.length;i++){
      var item = list[i], index = number(item[0]), name = item[1], colour = item[2] || '#333';
      var selectedValue = own(selected,key) ? selected[key] : current;
      html += '<button class="swatch '+(selectedValue===index?'active':'')+'" style="background:'+esc(colour)+'" data-colour-key="'+esc(key)+'" data-colour-value="'+index+'"><span>'+esc(name)+'</span></button>';
    }
    return html + '</div>';
  }

  function renderPane(){
    if(!D) return;
    var list = categories(), category = null;
    for(var i=0;i<list.length;i++) if(list[i].id === activeCategory) category = list[i];
    if(!category && list.length) category = list[0];
    if(!category) return;
    $('paneTitle').textContent = category.label;
    $('paneIndex').textContent = panePosition(category);
    var sub = 'Select an upgrade';
    var html = '';

    if(category.kind === 'slot'){
      var slot = category.ref;
      var choice = selected.slots && own(selected.slots,slot.key) ? selected.slots[slot.key] : slot.current;
      sub = slot.modType === 11 ? 'Server-priced performance upgrade with live speed preview' : (slot.key === 'livery' ? 'Preview liveries before purchasing' : 'Preview parts before purchasing');
      html = '<div class="cards">';
      for(i=0;i<slot.options.length;i++){
        var opt = slot.options[i]; opt._selected = opt.index === choice;
        html += optionCard(opt,slot.current,'data-slot="'+esc(slot.key)+'" data-mod-type="'+slot.modType+'" data-index="'+opt.index+'"',opt.index<0?'STOCK':'LV '+(opt.index+1),slot.key);
      }
      html += '</div>';
      if(slot.modType === 11 && D.speeds && D.speeds.length){
        var level = choice < 0 ? 0 : choice + 1;
        var stock = number(D.speeds[0]);
        var tuned = number(D.speeds[level] || stock);
        var gain = stock > 0 ? Math.round(((tuned-stock)/stock)*100) : 0;
        html += '<div class="speed-card"><div class="speed-row"><div><span class="speed-label">STOCK</span><div class="speed-value">'+money(stock)+' km/h</div></div><div class="speed-arrow">→</div><div><span class="speed-label">SELECTED</span><div class="speed-value accent">'+money(tuned)+' km/h</div></div>'+(gain>0?'<span class="gain-pill">+'+gain+'%</span>':'')+'</div><div class="speed-bars">';
        var top = Math.max(1,number(D.speeds[D.speeds.length-1])-stock);
        for(i=0;i<D.speeds.length;i++){
          var pct = Math.max(12,Math.min(100,18+((number(D.speeds[i])-stock)/top)*82));
          html += '<div class="speed-bar '+(i<=level?'on':'')+'" style="height:'+pct+'%"></div>';
        }
        html += '</div></div>';
      }
    }else if(category.kind === 'tyres'){
      sub = 'Grip upgrades. Higher levels include stronger tyre protection.';
      var tyreChoice = own(selected,'tyres') ? selected.tyres : D.tyres.current;
      html = '<div class="cards">';
      for(i=0;i<D.tyres.options.length;i++){
        var tyre = D.tyres.options[i]; tyre._selected = tyre.index === tyreChoice;
        html += optionCard(tyre,D.tyres.current,'data-tyre="'+tyre.index+'"',tyre.index===0?'STOCK':'LV '+tyre.index,'wheel');
      }
      html += '</div>';
    }else if(category.kind === 'toggle'){
      var toggle = category.ref;
      var toggleValue = selected.toggles && own(selected.toggles,toggle.key) ? selected.toggles[toggle.key] : toggle.current;
      sub = 'Enable or remove this upgrade';
      html = '<div class="toggle-card '+(toggleValue?'enabled':'')+'"><div class="toggle-copy"><h3>'+esc(toggle.label)+'</h3><p>Changes are validated and saved by the server after payment.</p><div class="toggle-price">'+(toggle.current?'Currently fitted':'$'+money(toggle.price))+'</div></div><label class="switch"><input type="checkbox" data-toggle="'+esc(toggle.key)+'" data-mod-type="'+toggle.modType+'" '+(toggleValue?'checked':'')+'><span class="switch-track"></span></label></div>';
    }else if(category.kind === 'harness'){
      sub = 'Prevents crash ejection when fitted';
      html = '<div class="service-card"><h3>'+esc(D.harness.label)+'</h3><p>Permanent safety equipment saved to this vehicle.</p><div class="service-price"><span>INSTALLATION</span><strong>'+(D.harness.installed?'Fitted':'$'+money(D.harness.price))+'</strong></div>'+(D.harness.installed?'<span class="installed-pill">ALREADY INSTALLED</span>':'<button id="btnHarness" class="secondary-button" type="button" '+(number(D.harness.price)>balance()?'disabled':'')+'>'+(number(D.harness.price)>balance()?'Not enough funds':'Install racing harness')+'</button>')+'</div>';
    }else if(category.kind === 'engine'){
      var health = number(D.engine.health), percent = Math.max(0,Math.min(100,health/10));
      var colour = percent>60?'var(--success)':(percent>30?'var(--warning)':'var(--danger)');
      sub = D.engine.missing>0 ? 'Restores the engine through a server-authorised rebuild' : 'Engine is already in perfect condition';
      html = '<div class="service-card"><h3>Engine condition</h3><p>Engine repair pricing is calculated from live server-side health.</p><div class="health-bar"><div class="health-fill" style="width:'+percent+'%;background:'+colour+'"></div></div><div class="health-numbers"><span>Condition</span><strong>'+Math.floor(health)+' / 1000</strong></div>'+(D.engine.missing>0?'<div class="service-price"><span>REBUILD COST</span><strong>$'+money(D.engine.price)+'</strong></div><button id="btnEngine" class="secondary-button" type="button" '+(number(D.engine.price)>balance()?'disabled':'')+'>'+(number(D.engine.price)>balance()?'Not enough funds':'Rebuild engine')+'</button>':'<div class="service-price"><span>STATUS</span><strong>Perfect</strong></div>')+'</div>';
    }else if(category.kind === 'paint'){
      sub = '$'+money(D.prices.respray)+' per colour change'; html = colourSwatches(D.colors || [],'color',D.currentPrimary);
    }else if(category.kind === 'paint2'){
      sub = '$'+money(D.prices.respray)+' per colour change'; html = colourSwatches(D.colors || [],'color2',D.currentSecondary);
    }else if(category.kind === 'wheelcol'){
      sub = '$'+money(D.prices.wheelColor)+' per colour change'; html = colourSwatches(D.colors || [],'wheelcol',D.currentWheelColor);
    }else if(category.kind === 'headlight'){
      sub = '$'+money(D.prices.headlight)+' per colour change'; html = colourSwatches(D.headlightColors || [],'headlight',D.currentHeadlight);
    }else if(category.kind === 'tint'){
      sub = '$'+money(D.prices.tint)+' per tint change'; html = '<div class="cards">';
      for(i=0;i<(D.tints || []).length;i++){
        var tint=D.tints[i], tintIndex=number(tint[0]), tintChoice=own(selected,'tint')?selected.tint:D.currentTint;
        html += '<button class="card '+(tintChoice===tintIndex?'selected ':'')+(D.currentTint===tintIndex?'fitted':'')+'" data-tint="'+tintIndex+'"><span class="card-art">'+iconSvg('tint')+'</span><span class="card-copy"><span class="card-level">WINDOW TINT</span><span class="card-name">'+esc(tint[1])+'</span>'+(tintChoice===tintIndex&&tintChoice!==D.currentTint?'<span class="card-badge">IN BASKET</span>':(D.currentTint===tintIndex?'<span class="card-badge">EQUIPPED</span>':''))+'</span><span class="card-price'+(D.currentTint===tintIndex?' fitted':'')+'">'+(D.currentTint===tintIndex?'Free':'$'+money(D.prices.tint))+'</span></button>';
      }
      html += '</div>';
    }else if(category.kind === 'plate'){
      sub = '$'+money(D.prices.plate)+' per plate style'; html = '<div class="cards">';
      for(i=0;i<(D.plateStyles || []).length;i++){
        var plate=D.plateStyles[i], plateIndex=number(plate[0]), plateChoice=own(selected,'plate')?selected.plate:D.currentPlate;
        html += '<button class="card '+(plateChoice===plateIndex?'selected ':'')+(D.currentPlate===plateIndex?'fitted':'')+'" data-plate="'+plateIndex+'"><span class="card-art">'+iconSvg('plate')+'</span><span class="card-copy"><span class="card-level">PLATE STYLE</span><span class="card-name">'+esc(plate[1])+'</span>'+(plateChoice===plateIndex&&plateChoice!==D.currentPlate?'<span class="card-badge">IN BASKET</span>':(D.currentPlate===plateIndex?'<span class="card-badge">EQUIPPED</span>':''))+'</span><span class="card-price'+(D.currentPlate===plateIndex?' fitted':'')+'">'+(D.currentPlate===plateIndex?'Free':'$'+money(D.prices.plate))+'</span></button>';
      }
      html += '</div>';
    }else if(category.kind === 'neon'){
      sub = '$'+money(D.prices.neon)+' for the neon kit';
      var neonOn = own(selected,'neon') ? selected.neon : D.currentNeon;
      html = '<div class="toggle-card '+(neonOn?'enabled':'')+'"><div class="toggle-copy"><h3>Neon kit</h3><p>Four-sided underglow with persistent colour.</p><div class="toggle-price">'+(D.currentNeon?'Currently fitted':'$'+money(D.prices.neon))+'</div></div><label class="switch"><input id="neonToggle" type="checkbox" '+(neonOn?'checked':'')+'><span class="switch-track"></span></label></div>';
      if(neonOn){
        html += '<div class="swatches with-labels" style="margin-top:14px">';
        for(i=0;i<(D.neonColors || []).length;i++){
          var neon=D.neonColors[i], rgb={r:number(neon[1]),g:number(neon[2]),b:number(neon[3])};
          var currentNeon = own(selected,'neonColor') ? selected.neonColor : D.currentNeonColor;
          var isActive = currentNeon && number(currentNeon.r)===rgb.r && number(currentNeon.g)===rgb.g && number(currentNeon.b)===rgb.b;
          html += '<button class="swatch '+(isActive?'active':'')+'" style="background:rgb('+rgb.r+','+rgb.g+','+rgb.b+')" data-neon-r="'+rgb.r+'" data-neon-g="'+rgb.g+'" data-neon-b="'+rgb.b+'"><span>'+esc(neon[0])+'</span></button>';
        }
        html += '</div>';
      }
    }

    $('paneSub').textContent = sub;
    $('paneBody').innerHTML = html;
    wirePane();
  }

  function valueLabel(list,value,fallback){
    for(var i=0;i<(list || []).length;i++) if(number(list[i][0])===number(value)) return String(list[i][1] || fallback);
    return fallback;
  }

  function changeSummary(){
    var items=[], i, slot, value, option, toggle, fields;
    if(!D) return items;
    for(i=0;i<(D.slots || []).length;i++){
      slot=D.slots[i];
      if(!selected.slots || !own(selected.slots,slot.key) || selected.slots[slot.key]===slot.current) continue;
      value=selected.slots[slot.key]; option=null;
      for(var s=0;s<(slot.options || []).length;s++) if(slot.options[s].index===value){option=slot.options[s];break;}
      items.push(slot.label+': '+(option?option.label:'Selected option'));
    }
    if(D.tyres && own(selected,'tyres') && selected.tyres!==D.tyres.current){
      option=null;
      for(i=0;i<(D.tyres.options || []).length;i++) if(D.tyres.options[i].index===selected.tyres){option=D.tyres.options[i];break;}
      items.push(D.tyres.label+': '+(option?option.label:'Selected level'));
    }
    for(i=0;i<(D.toggles || []).length;i++){
      toggle=D.toggles[i];
      if(selected.toggles && own(selected.toggles,toggle.key) && selected.toggles[toggle.key]!==toggle.current) items.push(toggle.label+': '+(selected.toggles[toggle.key]?'Enabled':'Removed'));
    }
    fields=[
      ['color','Primary colour',D.currentPrimary,D.colors],
      ['color2','Secondary colour',D.currentSecondary,D.colors],
      ['wheelcol','Wheel colour',D.currentWheelColor,D.colors],
      ['headlight','Headlight colour',D.currentHeadlight,D.headlightColors],
      ['tint','Window tint',D.currentTint,D.tints],
      ['plate','Plate style',D.currentPlate,D.plateStyles]
    ];
    for(i=0;i<fields.length;i++){
      var field=fields[i];
      if(own(selected,field[0]) && String(selected[field[0]])!==String(field[2])) items.push(field[1]+': '+valueLabel(field[3],selected[field[0]],'Option '+selected[field[0]]));
    }
    if(own(selected,'neon') && selected.neon!==D.currentNeon) items.push('Underglow: '+(selected.neon?'Enabled':'Removed'));
    if(own(selected,'neonColor')){
      var neonColor=selected.neonColor;
      var currentColor=D.currentNeonColor || {};
      if(number(currentColor.r)===number(neonColor.r) && number(currentColor.g)===number(neonColor.g) && number(currentColor.b)===number(neonColor.b)) neonColor=null;
      if(!neonColor) return items;
      var neonName='Custom colour';
      for(i=0;i<(D.neonColors || []).length;i++) if(number(D.neonColors[i][1])===number(neonColor.r) && number(D.neonColors[i][2])===number(neonColor.g) && number(D.neonColors[i][3])===number(neonColor.b)){neonName=D.neonColors[i][0];break;}
      items.push('Underglow colour: '+neonName);
    }
    return items;
  }

  function openConfirmation(action){
    if(!D || isProcessing) return;
    var cost=0, title='CONFIRM PURCHASE', message='', consequence='', confirmText='CONFIRM';
    if(action==='purchase'){
      if(!hasChanges()) return;
      cost=estimatedCost();
      if(cost>balance()) return;
      var changes=changeSummary(), shown=changes.slice(0,4).join(' · ');
      if(changes.length>4) shown+=' · +'+(changes.length-4)+' more';
      title='CONFIRM PURCHASE'; confirmText=cost>0?'PURCHASE MODS':'SAVE CHANGES';
      message='Apply these changes to '+(D.vehicleName || 'this vehicle')+': '+(shown || 'Selected vehicle customisation')+'.';
      consequence='This will charge $'+money(cost)+' from your '+account+' balance. The server rechecks the purchase before applying it.';
    }else if(action==='harness'){
      if(!D.harness || D.harness.installed) return;
      cost=number(D.harness.price);
      if(cost>balance()) return;
      title='CONFIRM INSTALLATION'; confirmText='INSTALL HARNESS';
      message='Install '+(D.harness.label || 'the racing harness')+' in '+(D.vehicleName || 'this vehicle')+'.';
      consequence='This charges $'+money(cost)+' from your '+account+' balance. The harness is saved to this vehicle after server approval.';
    }else if(action==='engine'){
      if(!D.engine || number(D.engine.missing)<=0) return;
      cost=number(D.engine.price);
      if(cost>balance()) return;
      title='CONFIRM ENGINE REBUILD'; confirmText='REBUILD ENGINE';
      message='Rebuild the damaged engine in '+(D.vehicleName || 'this vehicle')+'.';
      consequence='This charges $'+money(cost)+' from your '+account+' balance. The engine condition and final price are checked by the server.';
    }else return;

    pendingAction=action;
    $('confirmTitle').textContent=title;
    $('confirmMessage').textContent=message;
    $('confirmConsequence').textContent=consequence;
    $('btnConfirmPurchase').textContent=confirmText;
    $('btnConfirmPurchase').disabled=false;
    $('confirmModal').classList.remove('hidden');
    requestAnimationFrame(function(){ $('btnCancelPurchase').focus(); });
  }

  function closeConfirmation(restoreFocus){
    $('confirmModal').classList.add('hidden');
    pendingAction=null;
    if(restoreFocus && D && !isProcessing) $('btnBuy').focus();
  }

  function submitConfirmedAction(){
    if(!D || isProcessing || !pendingAction) return;
    var action=pendingAction;
    if(action==='purchase' && (!hasChanges() || estimatedCost()>balance())) return closeConfirmation(true);
    if(action==='harness' && (!D.harness || D.harness.installed || number(D.harness.price)>balance())) return closeConfirmation(true);
    if(action==='engine' && (!D.engine || number(D.engine.missing)<=0 || number(D.engine.price)>balance())) return closeConfirmation(true);
    closeConfirmation(false);
    if(action==='purchase'){
      setProcessing(true,'Securing purchase...');
      post('purchase',{account:account,changes:collectChanges()});
    }else if(action==='harness'){
      setProcessing(true,'Installing harness...');
      post('installHarness',{account:account});
    }else if(action==='engine'){
      setProcessing(true,'Authorising rebuild...');
      post('repairEngine',{account:account});
    }
  }

  $('btnConfirmPurchase').onclick=submitConfirmedAction;
  $('btnCancelPurchase').onclick=function(){ if(!isProcessing) closeConfirmation(true); };
  $('confirmModal').addEventListener('click',function(event){
    if(event.target && event.target.getAttribute('data-confirm-dismiss')==='true' && !isProcessing) closeConfirmation(true);
  });

  function wirePane(){
    var i, nodes;
    nodes = document.querySelectorAll('[data-slot]');
    for(i=0;i<nodes.length;i++) nodes[i].onclick = function(){
      selected.slots = selected.slots || {};
      var slotKey=this.getAttribute('data-slot'), slot=null;
      for(var j=0;j<(D.slots || []).length;j++) if(D.slots[j].key===slotKey){slot=D.slots[j];break;}
      var index=number(this.getAttribute('data-index'));
      selected.slots[slotKey] = index;
      if(slot && slot.nativeLivery) post('preview',{kind:'livery',value:index});
      else post('preview',{kind:'mod',modType:number(this.getAttribute('data-mod-type')),index:index});
      renderPane(); refreshCheckout();
    };
    nodes = document.querySelectorAll('[data-tyre]');
    for(i=0;i<nodes.length;i++) nodes[i].onclick = function(){ selected.tyres=number(this.getAttribute('data-tyre')); post('preview',{kind:'tyres',value:selected.tyres}); renderPane(); refreshCheckout(); };
    nodes = document.querySelectorAll('[data-toggle]');
    for(i=0;i<nodes.length;i++) nodes[i].onchange = function(){
      selected.toggles = selected.toggles || {};
      var toggleKey = this.getAttribute('data-toggle');
      selected.toggles[toggleKey] = this.checked;
      var toggleCard=this.closest('.toggle-card');
      if(toggleCard) toggleCard.classList.toggle('enabled',this.checked);
      post('preview',{kind:'toggle',modType:number(this.getAttribute('data-mod-type')),value:this.checked});
      if(toggleKey === 'xenon' && !this.checked && own(selected,'headlight') && selected.headlight >= 0){
        selected.headlight = -1;
        post('preview',{kind:'headlight',value:-1});
      }
      refreshCheckout();
    };
    nodes = document.querySelectorAll('[data-colour-key]');
    for(i=0;i<nodes.length;i++) nodes[i].onclick = function(){
      var key=this.getAttribute('data-colour-key'), value=number(this.getAttribute('data-colour-value'));
      selected[key]=value;
      if(key === 'headlight' && value >= 0){
        selected.toggles = selected.toggles || {};
        selected.toggles.xenon = true;
      }
      var kinds={color:'color',color2:'color2',wheelcol:'wheelColor',headlight:'headlight'};
      post('preview',{kind:kinds[key] || key,value:value}); renderPane(); refreshCheckout();
    };
    nodes = document.querySelectorAll('[data-tint]');
    for(i=0;i<nodes.length;i++) nodes[i].onclick = function(){ selected.tint=number(this.getAttribute('data-tint')); post('preview',{kind:'tint',value:selected.tint}); renderPane(); refreshCheckout(); };
    nodes = document.querySelectorAll('[data-plate]');
    for(i=0;i<nodes.length;i++) nodes[i].onclick = function(){ selected.plate=number(this.getAttribute('data-plate')); post('preview',{kind:'plate',value:selected.plate}); renderPane(); refreshCheckout(); };
    var neonToggle=$('neonToggle');
    if(neonToggle) neonToggle.onchange=function(){ selected.neon=this.checked; post('preview',{kind:'neon',value:this.checked}); renderPane(); refreshCheckout(); };
    nodes = document.querySelectorAll('[data-neon-r]');
    for(i=0;i<nodes.length;i++) nodes[i].onclick = function(){ selected.neonColor={r:number(this.getAttribute('data-neon-r')),g:number(this.getAttribute('data-neon-g')),b:number(this.getAttribute('data-neon-b'))}; post('preview',{kind:'neonColor',value:selected.neonColor}); renderPane(); refreshCheckout(); };
    var harness=$('btnHarness'); if(harness) harness.onclick=function(){ openConfirmation('harness'); };
    var engine=$('btnEngine'); if(engine) engine.onclick=function(){ openConfirmation('engine'); };
  }

  function renderCamera(){
    var box=$('cameraList'); if(!box || !D) return;
    var presets=D.cameraPresets || [];
    var html='';
    for(var i=0;i<presets.length;i++) html+='<button class="camera-button '+(i+1===activeCamera?'active':'')+'" data-camera="'+(i+1)+'">'+esc(presets[i].label || ('View '+(i+1)))+'</button>';
    box.innerHTML=html;
    var buttons=box.querySelectorAll('[data-camera]');
    for(i=0;i<buttons.length;i++) buttons[i].onclick=function(){
      var all=box.querySelectorAll('[data-camera]'); for(var j=0;j<all.length;j++) all[j].classList.remove('active');
      this.classList.add('active'); activeCamera=number(this.getAttribute('data-camera')); post('camPreset',{index:activeCamera});
    };
  }

  function setProcessing(value,message){
    isProcessing=value===true;
    $('processing').classList.toggle('hidden',!isProcessing);
    $('processing').setAttribute('aria-hidden',isProcessing?'false':'true');
    $('btnConfirmPurchase').disabled=isProcessing;
    if(message) $('processingText').textContent=message;
    refreshCheckout();
  }

  function showToast(message,kind){
    var toast=$('toast');
    if(toastTimer) clearTimeout(toastTimer);
    $('toastMessage').textContent=String(message || '');
    toast.className='toast '+(kind==='error'?'error':'');
    toast.classList.remove('hidden');
    toastTimer=setTimeout(function(){ toast.classList.add('hidden'); },4000);
  }

  function openShop(data){
    D=data || {};
    selected={};
    activeCategory=null;
    isProcessing=false;
    pendingAction=null;
    activeCamera=2;
    categorySearch='';
    if($('categorySearch')) $('categorySearch').value='';
    $('confirmModal').classList.add('hidden');
    account='cash';
    $('shopTitle').textContent=D.shopLabel || 'Tuning';
    $('shopSub').textContent=D.shopSub || 'Secure vehicle customisation';
    $('vehicleName').textContent=D.vehicleName || 'Vehicle';
    $('vehiclePlate').textContent=D.plate || 'NO PLATE';
    renderCamera(); renderCategories(); renderPane(); refreshCheckout();
    root.classList.remove('hidden');
    root.setAttribute('aria-hidden','false');
    setProcessing(false);
    requestAnimationFrame(function(){ requestAnimationFrame(function(){ post('uiRendered',{}); }); });
  }

  function closeShop(){
    stopVehicleDrag();
    closeConfirmation(false);
    root.classList.add('hidden'); root.setAttribute('aria-hidden','true');
    D=null; selected={}; activeCategory=null; isProcessing=false;
  }

  $('btnBuy').onclick=function(){
    if(!D || isProcessing || !hasChanges()) return;
    var cost=estimatedCost();
    if(cost>balance()) return;
    openConfirmation('purchase');
  };
  $('btnClose').onclick=function(){ if(!isProcessing){ closeShop(); post('close',{}); } };

  document.addEventListener('keydown',function(event){
    if((event.key==='Escape' || event.key==='Backspace') && D && !isProcessing){
      event.preventDefault();
      if(!$('confirmModal').classList.contains('hidden')) closeConfirmation(true);
      else { closeShop(); post('close',{}); }
    }
  });

  window.addEventListener('message',function(event){
    var message=event.data || {};
    if(message.action==='open'){
      openShop(message.data || {});
    }else if(message.action==='close'){
      closeShop();
    }else if(message.action==='processing'){
      setProcessing(message.value===true,message.message || 'Processing...');
    }else if(message.action==='toast'){
      showToast(message.message,message.kind);
    }
  });

})();
