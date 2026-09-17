(() => {
  const app = document.getElementById('app');
  const police = location.pathname.includes('/police/');
  const overview = app.querySelector('#overviewView') || app.querySelector('[data-view="overview"]');
  const identity = overview?.querySelector('.org-identity-card');
  if (identity) {
    const hero = document.createElement('article'); hero.className = 'command-hero';
    identity.before(hero); hero.appendChild(identity);
    const stats = identity.querySelector('.command-stats');
    if (stats) hero.after(stats);
    const caption = document.createElement('small'); caption.className = 'hero-kicker'; caption.id = 'heroOrganization'; caption.textContent = 'YOUR ORGANISATION';
    identity.querySelector('.org-identity-copy')?.prepend(caption);
    const portrait = app.querySelector('.law-record-rail__portrait');
    if (portrait) { portrait.classList.add('command-hero-art'); hero.appendChild(portrait); }
  }
  const intros = police ? [['members','Personnel','Your people. One team.'],['ranks','Chain of command','Manage rank levels and inspect access.'],['fleet','Motor pool','Assigned vehicles and parking access.'],['logs','Activity record','Review recent organisation activity.']] : [['roster','Personnel','Your people. One team.'],['ranks','Chain of command','Manage rank levels and inspect access.'],['fleet','Motor pool','Assigned vehicles and parking access.'],['logs','Activity record','Review recent organisation activity.'],['logistics','Supply operations','Coordinate orders and review delivery history.']];
  for (const [id,title,description] of intros) {
    const view = police ? app.querySelector(`[data-view="${id}"]`) : document.getElementById(id+'View');
    if (!view) continue;
    const head = document.createElement('div'); head.className = 'page-intro';
    const tag = document.createElement('small'); tag.textContent = 'ORGANISATION / '+title.toUpperCase();
    const heading = document.createElement('h2'); heading.textContent = title;
    const copy = document.createElement('p'); copy.textContent = description;
    head.append(tag,heading,copy); view.prepend(head);
  }
  window.addEventListener('message', event => {
    const d = event.data || {};
    if (d.data && ['open','dashboard','refresh'].includes(d.action)) {
      const caption = document.getElementById('heroOrganization');
      if (caption) caption.textContent = d.data.organization?.label || d.data.organization?.name || 'YOUR ORGANISATION';
    }
  });
  for (const [input,button] of [['lawMdtCitizenQuery','lawMdtCitizenSearch'],['lawMdtPlateQuery','lawMdtVehicleSearch']]) {
    document.getElementById(input)?.addEventListener('keydown',e=>{if(e.key==='Enter'){e.preventDefault();document.getElementById(button)?.click()}});
  }
  if (police) {
    const card = document.querySelector('.police-quick-menu-card');
    if (card) {
      const kicker = document.createElement('small'); kicker.className = 'quick-menu-kicker'; kicker.textContent = 'FIELD OPERATIONS'; card.prepend(kicker);
      const close = document.createElement('button'); close.className = 'quick-menu-close'; close.type = 'button'; close.setAttribute('aria-label','Close quick actions'); close.textContent = '×';
      close.onclick=()=>{closeQuickMenuOverlay();post('quickMenuClosed')}; card.prepend(close);
      const footer = document.createElement('div'); footer.className = 'quick-menu-footer'; footer.innerHTML='<kbd>ESC</kbd><span>Return to the field</span>'; card.append(footer);
    }
  }
})();
