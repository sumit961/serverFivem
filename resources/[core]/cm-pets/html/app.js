const app = document.getElementById('app');
const content = document.getElementById('content');
const status = document.getElementById('status');
const closeButton = document.getElementById('close');
let state = { pet: null, active: false, mode: 'follow', center: null, adoptable: [] };

const post = (name, payload = {}) => fetch(`https://${GetParentResourceName()}/${name}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload)
}).catch(() => null);

const setStatus = (message, error = false) => {
    status.textContent = message || '';
    status.classList.toggle('error', error);
};

const button = (label, action, className = '', payload = {}) => {
    const el = document.createElement('button');
    el.type = 'button'; el.className = `action ${className}`; el.textContent = label;
    el.addEventListener('click', () => post('action', { action, ...payload }));
    return el;
};

function renderAdoption() {
    if (!state.center || !Array.isArray(state.adoptable)) return null;
    const section = document.createElement('section'); section.className = 'adoption-section';
    const heading = document.createElement('div'); heading.className = 'section-heading';
    const title = document.createElement('h2'); title.textContent = state.center.displayName || 'Adoption Center';
    const subtitle = document.createElement('p'); subtitle.textContent = 'Choose one cosmetic companion. Adoption does not summon it.';
    heading.append(title, subtitle); section.appendChild(heading);

    const list = document.createElement('div'); list.className = 'adoption-list';
    if (state.adoptable.length === 0) {
        const empty = document.createElement('p'); empty.className = 'empty compact'; empty.textContent = 'No enabled pets are available here.';
        list.appendChild(empty);
    } else {
        state.adoptable.forEach((candidate) => {
            const card = document.createElement('article'); card.className = 'adoption-card';
            const copy = document.createElement('div');
            const name = document.createElement('h3'); name.textContent = candidate.displayName;
            const species = document.createElement('p'); species.textContent = `${candidate.species} · ${candidate.description || 'Cosmetic companion'}`;
            copy.append(name, species);
            const adopt = button(state.pet ? 'Owned' : 'Adopt', 'adopt', state.pet ? 'disabled' : 'primary', { typeId: candidate.typeId });
            adopt.disabled = Boolean(state.pet);
            card.append(copy, adopt); list.appendChild(card);
        });
    }
    section.appendChild(list);
    return section;
}

function renderOwned() {
    const section = document.createElement('section'); section.className = 'owned-section';
    const label = document.createElement('p'); label.className = 'section-label'; label.textContent = 'CURRENT PET';
    section.appendChild(label);
    if (!state.pet) {
        const empty = document.createElement('div'); empty.className = 'empty';
        empty.textContent = state.center ? 'No pet is owned yet.' : 'You do not currently own an enabled companion pet.';
        section.appendChild(empty); return section;
    }

    const card = document.createElement('article'); card.className = 'pet-card';
    const top = document.createElement('div'); top.className = 'pet-card__top';
    const copy = document.createElement('div');
    const title = document.createElement('h2'); title.textContent = state.pet.name;
    const description = document.createElement('p'); description.textContent = `${state.pet.displayName} · ${state.pet.species}`;
    copy.append(title, description);
    const badge = document.createElement('span'); badge.className = 'badge'; badge.textContent = state.active ? 'Summoned' : 'Hidden';
    top.append(copy, badge); card.appendChild(top);

    if (state.pet.revoked || !state.pet.enabled || state.pet.typeEnabled === false) {
        const unavailable = document.createElement('p'); unavailable.className = 'warning';
        unavailable.textContent = 'This pet is currently unavailable. Contact an administrator.';
        card.appendChild(unavailable); section.appendChild(card); return section;
    }

    const controls = document.createElement('div'); controls.className = 'row';
    controls.appendChild(button(state.active ? 'Hide' : 'Summon', state.active ? 'hide' : 'summon', 'primary'));
    controls.appendChild(button('Follow', 'follow', state.mode === 'follow' ? 'active' : ''));
    controls.appendChild(button('Stay', 'stay', state.mode === 'stay' ? 'active' : ''));
    card.appendChild(controls);

    const rename = document.createElement('form'); rename.className = 'rename';
    const input = document.createElement('input'); input.maxLength = 32; input.value = state.pet.name; input.placeholder = 'Pet name'; input.setAttribute('aria-label', 'Pet name');
    const save = document.createElement('button'); save.type = 'submit'; save.className = 'action'; save.textContent = 'Rename';
    rename.append(input, save); rename.addEventListener('submit', (event) => { event.preventDefault(); post('rename', { name: input.value }); });
    card.appendChild(rename); section.appendChild(card); return section;
}

function render() {
    content.replaceChildren();
    const adoption = renderAdoption();
    if (adoption) content.appendChild(adoption);
    content.appendChild(renderOwned());
}

window.addEventListener('message', (event) => {
    const data = event.data || {};
    if (data.action === 'open') {
        state = { pet: data.pet || null, active: data.active === true, mode: data.mode || 'follow', center: data.center || null, adoptable: Array.isArray(data.adoptable) ? data.adoptable : [] };
        app.classList.add('is-open'); app.setAttribute('aria-hidden', 'false'); render(); setStatus('');
    } else if (data.action === 'close') {
        app.classList.remove('is-open'); app.setAttribute('aria-hidden', 'true');
    } else if (data.action === 'state') {
        state = {
            ...state,
            pet: data.pet !== undefined ? data.pet : state.pet,
            active: data.active === true,
            mode: data.mode || state.mode,
        };
        render(); setStatus(data.message || '');
    }
});

closeButton.addEventListener('click', () => post('close'));
document.addEventListener('keydown', (event) => { if (event.key === 'Escape') { event.preventDefault(); post('close'); } });
