(() => {
  const status = document.createElement('div'); status.id = 'cmRequestStatus'; status.hidden = true; status.setAttribute('role','status'); document.body.appendChild(status);
  let clicked = null, pending = 0, timer;
  const counts = new WeakMap();
  document.addEventListener('click',event=>{clicked=event.target.closest('button');queueMicrotask(()=>clicked=null)},true);
  window.cmRequest = async (url,data) => {
    const button = clicked, controller = new AbortController();
    if(button){counts.set(button,(counts.get(button)||0)+1);button.setAttribute('aria-busy','true')}
    pending++;clearTimeout(timer);status.hidden=false;status.textContent='Working…';
    const timeout=setTimeout(()=>controller.abort(),45000);
    try{
      const response=await fetch(url,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data),signal:controller.signal});
      if(!response.ok)throw new Error(`Request failed (${response.status}).`);
      const result=await response.json();
      if(result?.ok===false){status.textContent=result.error||result.message||'The action could not be completed.';}
      else status.textContent='Updated';
      return result;
    }catch(error){const message=error.name==='AbortError'?'Response timed out. Check the result before trying the action again.':'Connection failed. Please check your connection and try again.';status.textContent=message;return {ok:false,error:message};}
    finally{clearTimeout(timeout);pending--;if(button){const n=(counts.get(button)||1)-1;counts.set(button,n);if(!n)button.removeAttribute('aria-busy')}if(!pending)timer=setTimeout(()=>status.hidden=true,3500)}
  };
})();
