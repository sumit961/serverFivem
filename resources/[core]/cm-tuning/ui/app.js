(function(){
  'use strict';

  var root = document.getElementById('root');
  var interaction = document.getElementById('interaction');
  var D = null;
  var selected = {};
  var account = 'cash';
  var activeCategory = null;
  var isProcessing = false;
  var toastTimer = null;

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
  function esc(value){
    return String(value == null ? '' : value).replace(/[&<>"']/g,function(c){
      return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c];
    });
  }
  function own(obj,key){ return obj && Object.prototype.hasOwnProperty.call(obj,key); }
  function balance(){ return D && D.balances ? number(D.balances[account]) : 0; }

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
    var fields = ['tyres','color','color2','wheelcol','headlight','tint','plate','neon','neonColor'];
    for(var i=0;i<fields.length;i++) if(own(changes,fields[i])) return true;
    return false;
  }

  function collectChanges(){
    var out = {slots:{},toggles:{}};
    var key;
    if(selected.slots){ for(key in selected.slots) if(own(selected.slots,key)) out.slots[key] = selected.slots[key]; }
    if(selected.toggles){ for(key in selected.toggles) if(own(selected.toggles,key)) out.toggles[key] = selected.toggles[key]; }
    var fields = ['tyres','color','color2','wheelcol','headlight','tint','plate','neon','neonColor'];
    for(var i=0;i<fields.length;i++) if(own(selected,fields[i])) out[fields[i]] = selected[fields[i]];
    return out;
  }

  function renderPayment(){
    var box = $('paymentOptions');
    if(!box || !D) return;
    var options = [];
    if(D.allowCash !== false) options.push(['cash','Cash']);
    if(D.allowBank !== false) options.push(['bank','Bank']);
    var cost = estimatedCost();
    var html = '';
    for(var i=0;i<options.length;i++){
      var key = options[i][0], label = options[i][1], amount = number(D.balances && D.balances[key]);
      html += '<button class="payment-option '+(account===key?'active ':'')+(cost>amount?'short':'')+'" data-account="'+key+'">'+
        '<span>'+label+'</span><strong>$'+money(amount)+'</strong></button>';
    }
    box.innerHTML = html;
    var buttons = box.querySelectorAll('[data-account]');
    for(i=0;i<buttons.length;i++) buttons[i].onclick = function(){ account = this.getAttribute('data-account'); refreshCheckout(); };
  }

  function refreshCheckout(){
    if(!D) return;
    var cost = estimatedCost();
    var changed = hasChanges();
    var broke = cost > balance();
    $('totalValue').textContent = '$' + money(cost);
    $('totalValue').className = broke ? 'broke' : '';
    $('btnBuy').disabled = isProcessing || !changed || broke;
    $('buyText').textContent = broke ? 'Not enough funds' : (changed ? (cost > 0 ? 'Purchase upgrades' : 'Save free changes') : 'No changes');
    renderPayment();
    renderCategories();
  }

  function renderCategories(){
    var box = $('categoryList');
    if(!box || !D) return;
    var list = categories();
    if(!activeCategory && list.length) activeCategory = list[0].id;
    var found = false;
    for(var f=0;f<list.length;f++) if(list[f].id === activeCategory) found = true;
    if(!found && list.length) activeCategory = list[0].id;
    var html = '';
    for(var i=0;i<list.length;i++){
      var state = currentChoice(list[i]);
      html += '<button class="category-item '+(list[i].id===activeCategory?'active ':'')+(state.changed?'changed':'')+'" data-category="'+esc(list[i].id)+'">'+
        '<span>'+esc(list[i].label)+'</span>'+(state.text?'<span class="category-state">'+esc(state.text)+'</span>':'')+'</button>';
    }
    box.innerHTML = html;
    var buttons = box.querySelectorAll('[data-category]');
    for(i=0;i<buttons.length;i++) buttons[i].onclick = function(){ activeCategory=this.getAttribute('data-category'); renderCategories(); renderPane(); };
  }

  function optionCard(option,current,attributes,level){
    var chosen = option._selected === true;
    var fitted = option.index === current;
    return '<button class="card '+(chosen?'selected ':'')+(fitted?'fitted':'')+'" '+attributes+'>'+
      '<span class="card-level">'+esc(level)+'</span><span class="card-name">'+esc(option.label)+'</span>'+
      '<span class="card-price '+(fitted?'fitted':'')+'">'+(fitted?'Fitted':(number(option.price)>0?'$'+money(option.price):'Free'))+'</span></button>';
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
    var sub = 'Select an upgrade';
    var html = '';

    if(category.kind === 'slot'){
      var slot = category.ref;
      var choice = selected.slots && own(selected.slots,slot.key) ? selected.slots[slot.key] : slot.current;
      sub = slot.modType === 11 ? 'Server-priced performance upgrade with live speed preview' : 'Preview parts before purchasing';
      html = '<div class="cards">';
      for(i=0;i<slot.options.length;i++){
        var opt = slot.options[i]; opt._selected = opt.index === choice;
        html += optionCard(opt,slot.current,'data-slot="'+esc(slot.key)+'" data-mod-type="'+slot.modType+'" data-index="'+opt.index+'"',opt.index<0?'STOCK':'LV '+(opt.index+1));
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
        html += optionCard(tyre,D.tyres.current,'data-tyre="'+tyre.index+'"',tyre.index===0?'STOCK':'LV '+tyre.index);
      }
      html += '</div>';
    }else if(category.kind === 'toggle'){
      var toggle = category.ref;
      var toggleValue = selected.toggles && own(selected.toggles,toggle.key) ? selected.toggles[toggle.key] : toggle.current;
      sub = 'Enable or remove this upgrade';
      html = '<div class="toggle-card"><div class="toggle-copy"><h3>'+esc(toggle.label)+'</h3><p>Changes are validated and saved by the server after payment.</p><div class="toggle-price">'+(toggle.current?'Currently fitted':'$'+money(toggle.price))+'</div></div><label class="switch"><input type="checkbox" data-toggle="'+esc(toggle.key)+'" data-mod-type="'+toggle.modType+'" '+(toggleValue?'checked':'')+'><span class="switch-track"></span></label></div>';
    }else if(category.kind === 'harness'){
      sub = 'Prevents crash ejection when fitted';
      html = '<div class="service-card"><h3>'+esc(D.harness.label)+'</h3><p>Permanent safety equipment saved to this vehicle.</p><div class="service-price"><span>INSTALLATION</span><strong>'+(D.harness.installed?'Fitted':'$'+money(D.harness.price))+'</strong></div>'+(D.harness.installed?'<span class="installed-pill">ALREADY INSTALLED</span>':'<button id="btnHarness" class="secondary-button" type="button">Install racing harness</button>')+'</div>';
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
        html += '<button class="card '+(tintChoice===tintIndex?'selected ':'')+(D.currentTint===tintIndex?'fitted':'')+'" data-tint="'+tintIndex+'"><span class="card-level">TINT</span><span class="card-name">'+esc(tint[1])+'</span><span class="card-price '+(D.currentTint===tintIndex?'fitted':'')+'">'+(D.currentTint===tintIndex?'Fitted':'$'+money(D.prices.tint))+'</span></button>';
      }
      html += '</div>';
    }else if(category.kind === 'plate'){
      sub = '$'+money(D.prices.plate)+' per plate style'; html = '<div class="cards">';
      for(i=0;i<(D.plateStyles || []).length;i++){
        var plate=D.plateStyles[i], plateIndex=number(plate[0]), plateChoice=own(selected,'plate')?selected.plate:D.currentPlate;
        html += '<button class="card '+(plateChoice===plateIndex?'selected ':'')+(D.currentPlate===plateIndex?'fitted':'')+'" data-plate="'+plateIndex+'"><span class="card-level">PLATE</span><span class="card-name">'+esc(plate[1])+'</span><span class="card-price '+(D.currentPlate===plateIndex?'fitted':'')+'">'+(D.currentPlate===plateIndex?'Fitted':'$'+money(D.prices.plate))+'</span></button>';
      }
      html += '</div>';
    }else if(category.kind === 'neon'){
      sub = '$'+money(D.prices.neon)+' for the neon kit';
      var neonOn = own(selected,'neon') ? selected.neon : D.currentNeon;
      html = '<div class="toggle-card"><div class="toggle-copy"><h3>Neon kit</h3><p>Four-sided underglow with persistent colour.</p><div class="toggle-price">'+(D.currentNeon?'Currently fitted':'$'+money(D.prices.neon))+'</div></div><label class="switch"><input id="neonToggle" type="checkbox" '+(neonOn?'checked':'')+'><span class="switch-track"></span></label></div>';
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

  function wirePane(){
    var i, nodes;
    nodes = document.querySelectorAll('[data-slot]');
    for(i=0;i<nodes.length;i++) nodes[i].onclick = function(){
      selected.slots = selected.slots || {};
      selected.slots[this.getAttribute('data-slot')] = number(this.getAttribute('data-index'));
      post('preview',{kind:'mod',modType:number(this.getAttribute('data-mod-type')),index:number(this.getAttribute('data-index'))});
      renderPane(); refreshCheckout();
    };
    nodes = document.querySelectorAll('[data-tyre]');
    for(i=0;i<nodes.length;i++) nodes[i].onclick = function(){ selected.tyres=number(this.getAttribute('data-tyre')); post('preview',{kind:'tyres',value:selected.tyres}); renderPane(); refreshCheckout(); };
    nodes = document.querySelectorAll('[data-toggle]');
    for(i=0;i<nodes.length;i++) nodes[i].onchange = function(){
      selected.toggles = selected.toggles || {};
      var toggleKey = this.getAttribute('data-toggle');
      selected.toggles[toggleKey] = this.checked;
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
    var harness=$('btnHarness'); if(harness) harness.onclick=function(){ if(!isProcessing){ setProcessing(true,'Installing harness...'); post('installHarness',{account:account}); } };
    var engine=$('btnEngine'); if(engine) engine.onclick=function(){ if(!isProcessing){ setProcessing(true,'Authorising rebuild...'); post('repairEngine',{account:account}); } };
  }

  function renderCamera(){
    var box=$('cameraList'); if(!box || !D) return;
    var presets=D.cameraPresets || [];
    var html='';
    for(var i=0;i<presets.length;i++) html+='<button class="camera-button '+(i===1?'active':'')+'" data-camera="'+(i+1)+'">'+esc(presets[i].label || ('View '+(i+1)))+'</button>';
    box.innerHTML=html;
    var buttons=box.querySelectorAll('[data-camera]');
    for(i=0;i<buttons.length;i++) buttons[i].onclick=function(){
      var all=box.querySelectorAll('[data-camera]'); for(var j=0;j<all.length;j++) all[j].classList.remove('active');
      this.classList.add('active'); post('camPreset',{index:number(this.getAttribute('data-camera'))});
    };
  }

  function setProcessing(value,message){
    isProcessing=value===true;
    $('processing').classList.toggle('hidden',!isProcessing);
    $('processing').setAttribute('aria-hidden',isProcessing?'false':'true');
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
    account=(D.defaultAccount==='bank' && D.allowBank!==false)?'bank':'cash';
    if(account==='cash' && D.allowCash===false) account='bank';
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
    root.classList.add('hidden'); root.setAttribute('aria-hidden','true');
    D=null; selected={}; activeCategory=null; isProcessing=false;
  }

  $('btnBuy').onclick=function(){
    if(!D || isProcessing || !hasChanges()) return;
    var cost=estimatedCost();
    if(cost>balance()) return;
    setProcessing(true,'Securing purchase...');
    post('purchase',{account:account,changes:collectChanges()});
  };
  $('btnClose').onclick=function(){ if(!isProcessing){ closeShop(); post('close',{}); } };

  document.addEventListener('keydown',function(event){
    if((event.key==='Escape' || event.key==='Backspace') && D && !isProcessing){
      event.preventDefault(); closeShop(); post('close',{});
    }
  });

  window.addEventListener('message',function(event){
    var message=event.data || {};
    if(message.action==='interaction'){
      if(message.show){
        $('interactionKey').textContent=message.key || 'E';
        $('interactionTitle').textContent=message.title || 'CM MOTORWORKS';
        $('interactionLabel').textContent=message.label || 'Open tuning shop';
        $('interactionHint').textContent=message.hint || '';
        interaction.classList.remove('hidden'); interaction.setAttribute('aria-hidden','false');
      }else{
        interaction.classList.add('hidden'); interaction.setAttribute('aria-hidden','true');
      }
    }else if(message.action==='open'){
      interaction.classList.add('hidden'); openShop(message.data || {});
    }else if(message.action==='close'){
      closeShop();
    }else if(message.action==='processing'){
      setProcessing(message.value===true,message.message || 'Processing...');
    }else if(message.action==='toast'){
      showToast(message.message,message.kind);
    }
  });

  post('uiReady',{});
  setInterval(function(){ if(!D) post('uiReady',{}); },2000);
})();
