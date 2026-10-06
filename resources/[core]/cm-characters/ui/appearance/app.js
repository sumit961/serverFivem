// cm-characters appearance UI controller
// Adapted from vms_charcreator
//
// PHASE 4C: player-facing categories are FACE / HAIR / EYES / CLOTHING —
// a fixed UI taxonomy layered on top of the UNCHANGED Lua data shape
// (items.parents / items.face / items.hairs / items.clothes). Native calls,
// field names and the appearanceChange contract are untouched; only how
// controls are grouped and labeled for the player changed. Rendering
// (DOM/markup) is kept separate from the NUI-post helpers (postChange/
// changeCamera) — every renderer below calls into those same two helpers,
// never duplicating fetch() calls.

let currentValue = {};
let items = {};
let clotheSets = {};
let disabledValues = {};
let handsUpKey = null;
let direction = "";
let charId = null;
let canCancel = false;
let currentServiceMode = null;

// ── Category taxonomy ───────────────────────────────────────────────────
// Each UI category maps to one or more Lua "items" groups. enabled() decides
// whether the nav button appears at all (mirrors the old per-Lua-category
// visibility, just regrouped) — service modes (gender/surgery/barber) only
// ever populate a subset of these, so most categories naturally disappear.
const CATEGORY_DEFS = [
    {
        key: 'face',
        label: 'FACE',
        enabled: () => {
            const p = items['parents'] || {};
            const f = items['face'] || {};
            const hasParents = !!(p.sex || p.parents || p.face_md_weight || p.skin_md_weight);
            const hasFace = Object.keys(f).some((k) => k !== 'eye_color' && f[k]);
            return hasParents || hasFace;
        },
        render: renderFacePanelImpl
    },
    {
        key: 'hair',
        label: 'HAIR',
        enabled: () => Object.values(items['hairs'] || {}).some(Boolean),
        render: renderHairPanelImpl
    },
    {
        key: 'eyes',
        label: 'EYES',
        enabled: () => !!(items['face'] && items['face'].eye_color),
        render: renderEyesPanelImpl
    },
    {
        key: 'clothing',
        label: 'CLOTHING',
        enabled: () => Object.values(items['clothes'] || {}).some(Boolean),
        render: renderClothingPanelImpl
    }
];

function renderCategories() {
    $('.categories').empty();
    CATEGORY_DEFS.forEach((def) => {
        if (def.enabled()) {
            $('.categories').append(`<div class="categoryBtn" data-type="${def.key}">${def.label}</div>`);
        }
    });

    if (currentServiceMode === 'barber' || $('.categories .categoryBtn').length <= 1) {
        $('.categories').hide();
    } else {
        $('.categories').show();
    }
}

// Listen for NUI messages
window.addEventListener('message', function(event) {
    const item = event.data;

    if (item.action === "openAppearance") {
        document.getElementById('appearance-ui').style.display = 'block';
        document.getElementById('app').classList.add('hidden');

        $('.panel').empty();
        currentServiceMode = item.serviceMode || null;

        if (item.serviceMode === 'barber') {
            $('#headerName').text('BARBER STUDIO');
            $('#headerCategory').text('HAIR & GROOMING');
            const cost = Number(item.serviceCost) || 100;
            $('#save').text('STYLE & PAY ($' + cost + ')');
            if ($('#cancel-text').length) $('#cancel-text').text('LEAVE WITHOUT EDIT');
            $('#cancel-btn').show();
            canCancel = true;
        } else {
            $('#headerName').text(translate.create_character || 'CREATE CHARACTER');
            $('#headerCategory').text(translate.select_category);
            $('#save').text(translate.save || 'SAVE & CONTINUE');
            if ($('#cancel-text').length) $('#cancel-text').text(translate.cancel || 'BACK');
            if (item.enableCancelButtonUI) {
                $('#cancel-btn').show();
                canCancel = true;
            } else {
                $('#cancel-btn').hide();
                canCancel = false;
            }
        }

        if (item.clotheSets) clotheSets = item.clotheSets;
        if (item.items) items = item.items;
        if (item.disabledValues) disabledValues = item.disabledValues;
        handsUpKey = item.handsUpKey;
        charId = item.charId;

        if (item.enableHandsUpButton) {
            $('.hands-up').show();
        } else {
            $('.hands-up').hide();
        }

        for (const [key, value] of Object.entries(item.data || {})) {
            // Starter clothing limit: hard-limit T-Shirt/Torso/Pants/Shoes
            // sliders to the curated 2-choice presets, never the full range.
            let hardMax = value.max;
            if (['tshirt_1', 'torso_1', 'pants_1', 'shoes_1'].includes(key)) {
                hardMax = 2;
            }

            currentValue[key] = {
                value: Math.min(Number(value.value) || 0, hardMax),
                min: value.min,
                max: hardMax,
                excluded: []
            };
        }

        for (const [k, v] of Object.entries(currentValue)) {
            if (disabledValues[k]) {
                for (const [_k, _v] of Object.entries(disabledValues[k])) {
                    v.excluded.push(_v);
                }
            }
        }

        renderCategories();

        setTimeout(() => {
            const firstCategory = document.querySelector('.categoryBtn');
            if (firstCategory) firstCategory.click();
        }, 80);
    }

    if (item.action === 'updateSecondValue') {
        if (currentValue[item.secondItem]) {
            currentValue[item.secondItem].max = item.secondValue;
            currentValue[item.secondItem].value = 0;
        }
        const range = document.getElementById(`${item.secondItem}-range`);
        if (range) {
            range.max = item.secondValue;
            range.value = 0;
        }
        const valEl = document.getElementById(`${item.secondItem}-value`);
        if (valEl) valEl.innerHTML = 0;
        const maxEl = document.getElementById(`${item.secondItem}-max`);
        if (maxEl) maxEl.innerHTML = item.secondValue;
        const stepEl = document.getElementById(`${item.secondItem}-stepper-label`);
        if (stepEl) stepEl.innerHTML = `0 <span class="stepper-max">/ ${item.secondValue}</span>`;
    }

    if (item.action === 'setValue') {
        if (currentValue[item.item]) {
            currentValue[item.item].value = item.value;
            const range = document.getElementById(`${item.item}-range`);
            if (range) range.value = item.value;
            const valEl = document.getElementById(`${item.item}-value`);
            if (valEl) valEl.innerHTML = item.value;
            const stepEl = document.getElementById(`${item.item}-stepper-label`);
            if (stepEl) stepEl.innerHTML = `${item.value} <span class="stepper-max">/ ${currentValue[item.item].max}</span>`;
        }
    }
});

// Category click handler (event delegation — categoryBtn elements are
// generated dynamically by renderCategories() above)
$(document).on('click', '.categoryBtn', function() {
    $('.categoryBtn').removeClass('active');
    $(this).addClass('active');
    $('.panel').empty();
    const type = $(this).data("type");
    $('#headerCategory').html(translate.category[type] || type.toUpperCase());
    changeCamera(type);

    const def = CATEGORY_DEFS.find((d) => d.key === type);
    $('.panel').html(def ? def.render() : '');
    refreshSelectedSwatches();
});

// Marks the currently-selected color swatch in every rendered color grid
// (yellow ring + center dot), based on currentValue[field].value.
function refreshSelectedSwatches() {
    document.querySelectorAll('.item-sub-color-selector[data-field]').forEach(el => {
        const field = el.dataset.field;
        const cv = currentValue[field];
        const isSelected = cv && String(el.dataset.colorId) === String(cv.value);
        el.classList.toggle('selected', !!isSelected);
    });
}

function sectionHeader(label) {
    return `<p class="item-section-title">${label}</p>`;
}

// FACE — combines the old "parents" (heritage/skin) and "face" (minus eye
// color, which now lives under its own EYES tab) categories into one tab
// with HERITAGE / SKIN / FACIAL FEATURES sections. Reads the exact same
// items.parents/items.face flags Lua already sends — no data model change.
function renderFacePanelImpl() {
    let values = '';
    const p = items['parents'] || {};
    const f = items['face'] || {};

    // Gender-service mode only: change an EXISTING character's sex. First-time
    // creation already picked gender on Basic Identity — showing it again
    // here would be a second, inconsistent gender-switch path.
    if (p.sex && currentServiceMode === 'gender') {
        values += sectionHeader('GENDER');
        values += createRangeBlock(translate.title_sex, translate.sub_sex, 'sex');
    }

    if (p.parents) {
        values += sectionHeader('HERITAGE');
        values += `
            <div class="item-block">
                <div class="item-bar">
                    <div class="second-item-bar">
                        <div class="item-option">
                            <p class="item-subname">${translate.sub_mom}</p>
                            <div class="item-suboptions">
                                <div class="item-suboptions-values parent-nav-btn" data-item="mom" data-dir="-1">‹</div>
                                <div class="item-suboptions-values"><p class="item-label" id="mom-label">${translate.parentsNames.mom[currentValue['mom'].value] || 'Unknown'}</p></div>
                                <div class="item-suboptions-values parent-nav-btn" data-item="mom" data-dir="1">›</div>
                            </div>
                        </div>
                        <div class="item-option">
                            <p class="item-subname">${translate.sub_dad}</p>
                            <div class="item-suboptions">
                                <div class="item-suboptions-values parent-nav-btn" data-item="dad" data-dir="-1">‹</div>
                                <div class="item-suboptions-values"><p class="item-label" id="dad-label">${translate.parentsNames.dad[currentValue['dad'].value] || 'Unknown'}</p></div>
                                <div class="item-suboptions-values parent-nav-btn" data-item="dad" data-dir="1">›</div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>`;
    }

    if (p.face_md_weight || p.skin_md_weight) {
        values += sectionHeader('SKIN');
        if (p.face_md_weight) values += createRangeBlock(translate.title_resemblance, translate.sub_face_md_weight, 'face_md_weight');
        if (p.skin_md_weight) values += createRangeBlock(translate.title_skin_md_weight, translate.sub_skin_md_weight, 'skin_md_weight');
    }

    const hasFeatures = f.neck_thickness || f.age || f.eyebrows || f.nose || f.cheeks || f.lip_thickness || f.jaw || f.chin || f.blemishes || f.complexion || f.sun || f.moles;
    if (hasFeatures) {
        values += sectionHeader('FACIAL FEATURES');

        if (f.nose) {
            values += `
                <div class="item-block">
                    <p class="item-title">${translate.title_nose}</p>
                    <div class="item-bar">
                        <div class="second-item-bar">
                            ${createRangeInput(translate.sub_nose_1, 'nose_1')}
                            ${createRangeInput(translate.sub_nose_2, 'nose_2')}
                        </div>
                        <div class="second-item-bar">
                            ${createRangeInput(translate.sub_nose_3, 'nose_3')}
                            ${createRangeInput(translate.sub_nose_4, 'nose_4')}
                        </div>
                        <div class="second-item-bar">
                            ${createRangeInput(translate.sub_nose_5, 'nose_5')}
                            ${createRangeInput(translate.sub_nose_6, 'nose_6')}
                        </div>
                    </div>
                </div>`;
        }
        if (f.eyebrows) {
            values += createDoubleRangeBlock(translate.title_eyebrow, translate.sub_eyebrows_5, 'eyebrows_5', translate.sub_eyebrows_6, 'eyebrows_6');
        }
        if (f.cheeks) {
            values += `
                <div class="item-block">
                    <p class="item-title">${translate.title_cheekbones}</p>
                    <div class="item-bar">
                        <div class="second-item-bar">
                            ${createRangeInput(translate.sub_cheeks_1, 'cheeks_1')}
                            ${createRangeInput(translate.sub_cheeks_2, 'cheeks_2')}
                        </div>
                        <div class="second-item-bar">
                            ${createRangeInput(translate.sub_cheeks_3, 'cheeks_3')}
                        </div>
                    </div>
                </div>`;
        }
        if (f.lip_thickness) {
            values += createRangeBlock(translate.title_lips, translate.sub_lip_thickness, 'lip_thickness');
        }
        if (f.jaw) {
            values += createDoubleRangeBlock(translate.title_jaw, translate.sub_jaw_1, 'jaw_1', translate.sub_jaw_2, 'jaw_2');
        }
        if (f.chin) {
            values += `
                <div class="item-block">
                    <p class="item-title">${translate.title_chin}</p>
                    <div class="item-bar">
                        <div class="second-item-bar">
                            ${createRangeInput(translate.sub_chin_1, 'chin_1')}
                            ${createRangeInput(translate.sub_chin_2, 'chin_2')}
                        </div>
                        <div class="second-item-bar">
                            ${createRangeInput(translate.sub_chin_3, 'chin_3')}
                            ${createRangeInput(translate.sub_chin_4, 'chin_4')}
                        </div>
                    </div>
                </div>`;
        }
        if (f.neck_thickness) {
            values += createRangeBlock(translate.title_neck_thickness, translate.sub_neck_thickness, 'neck_thickness');
        }
        if (f.age) {
            values += createDoubleRangeBlock(translate.title_ageing, translate.sub_age_1, 'age_1', translate.sub_age_2, 'age_2');
        }
        if (f.blemishes) {
            values += createDoubleRangeBlock(translate.title_blemishes, translate.sub_blemishes_1, 'blemishes_1', translate.sub_blemishes_2, 'blemishes_2');
        }
        if (f.complexion) {
            values += createDoubleRangeBlock(translate.title_complexion, translate.sub_complexion_1, 'complexion_1', translate.sub_complexion_2, 'complexion_2');
        }
        if (f.sun) {
            values += createDoubleRangeBlock(translate.title_sun, translate.sub_sun_1, 'sun_1', translate.sub_sun_2, 'sun_2');
        }
        if (f.moles) {
            values += createDoubleRangeBlock(translate.title_moles, translate.sub_moles_1, 'moles_1', translate.sub_moles_2, 'moles_2');
        }
    }

    return values;
}

// EYES — just eye color, pulled out of the old face panel into its own tab.
function renderEyesPanelImpl() {
    const f = items['face'] || {};
    if (!f.eye_color) return '';
    return `
        <div class="item-block">
            <p class="item-title">${translate.title_eye_color}</p>
            <div class="item-bar">
                <p class="item-subname">${translate.sub_eye_color}</p>
                <div class="color-selector-bar">
                    ${buildEyeColors()}
                </div>
            </div>
        </div>`;
}

// HAIR — hairstyle, primary/highlight color, beard/chest-hair where present
// (server already omits beard/chesthair items entirely for female peds —
// see AvailableItems in client/appearance.lua — so there is nothing to hide
// here, it simply never renders).
function renderHairPanelImpl() {
    let values = '';
    const h = items['hairs'] || {};

    if (h.hair) {
        values += `
            <div class="item-block">
                <p class="item-title">${translate.title_hair}</p>
                <div class="item-bar">
                    <div class="second-item-bar">
                        ${createRangeInput(translate.sub_hair_1, 'hair_1')}
                    </div>
                    <p class="item-subname">${translate.sub_hair_color_1}</p>
                    <div class="color-selector-bar">
                        ${buildHairColors('hair_color_1')}
                    </div>
                    <p class="item-subname">${translate.sub_hair_color_2}</p>
                    <div class="color-selector-bar">
                        ${buildHairColors('hair_color_2')}
                    </div>
                </div>
            </div>`;
    }
    if (h.beard) {
        values += `
            <div class="item-block">
                <p class="item-title">${translate.title_beard}</p>
                <div class="item-bar">
                    <div class="second-item-bar">
                        ${createRangeInput(translate.sub_beard_1, 'beard_1')}
                        ${createRangeInput(translate.sub_beard_2, 'beard_2')}
                    </div>
                    <p class="item-subname">${translate.sub_beard_3}</p>
                    <div class="color-selector-bar">
                        ${buildHairColors('beard_3')}
                    </div>
                </div>
            </div>`;
    }
    if (h.eyebrow) {
        values += `
            <div class="item-block">
                <p class="item-title">${translate.title_eyebrow}</p>
                <div class="item-bar">
                    <div class="second-item-bar">
                        ${createRangeInput(translate.sub_eyebrows_1, 'eyebrows_1')}
                        ${createRangeInput(translate.sub_eyebrows_2, 'eyebrows_2')}
                    </div>
                    <p class="item-subname">${translate.sub_eyebrows_3}</p>
                    <div class="color-selector-bar">
                        ${buildHairColors('eyebrows_3')}
                    </div>
                </div>
            </div>`;
    }
    if (h.chesthair) {
        values += `
            <div class="item-block">
                <p class="item-title">${translate.title_chesthair}</p>
                <div class="item-bar">
                    <div class="second-item-bar">
                        ${createRangeInput(translate.sub_chest_1, 'chest_1')}
                        ${createRangeInput(translate.sub_chest_2, 'chest_2')}
                    </div>
                    <p class="item-subname">${translate.sub_chest_3}</p>
                    <div class="color-selector-bar">
                        ${buildHairColors('chest_3')}
                    </div>
                </div>
            </div>`;
    }

    return values;
}

// CLOTHING — curated starter presets only (torso/pants/shoes; texture/tshirt
// fields are locked to 0 server-side and skipped here — see
// client/appearance.lua's appearanceChange 'torso_2'/'pants_2'/etc branch).
// This never becomes the full clothing store: items['clothes'] only ever
// contains torso/pants/shoes from Lua.
function renderClothingPanelImpl() {
    let values = '';
    const c = items['clothes'] || {};
    const slots = [
        { key: 'torso', title: translate.title_torso, sub: translate.sub_torso_1 },
        { key: 'pants', title: translate.title_pants, sub: translate.sub_pants_1 },
        { key: 'shoes', title: translate.title_shoes, sub: translate.sub_shoes_1 }
    ];

    for (const slot of slots) {
        if (c[slot.key]) {
            values += `
                <div class="item-block">
                    <p class="item-title">${slot.title}</p>
                    <div class="item-bar">
                        <div class="second-item-bar">
                            ${createRangeInput(slot.sub, slot.key + '_1')}
                        </div>
                    </div>
                </div>`;
        }
    }

    return values;
}

// Helper: Create button stepper input HTML
function createRangeInput(subname, item) {
    const cv = currentValue[item];
    if (!cv) return '';
    return `
        <div class="item-option">
            <div class="item-values">
                <p class="item-subname">${subname}</p>
                <p class="item-value" id="${item}-value">${cv.value}</p>
            </div>
            <div class="item-suboptions stepper-controls">
                <button type="button" class="stepper-btn" data-action="step" data-item="${item}" data-dir="-1">◀</button>
                <span class="stepper-label" id="${item}-stepper-label">${cv.value} <span class="stepper-max">/ ${cv.max}</span></span>
                <button type="button" class="stepper-btn" data-action="step" data-item="${item}" data-dir="1">▶</button>
                <input type="hidden" id="${item}-range" value="${cv.value}">
            </div>
        </div>`;
}

function stepItem(item, dir) {
    if (!currentValue[item]) return;
    let val = Number(currentValue[item].value);
    if (isNaN(val)) val = 0;
    const min = Number(currentValue[item].min) || 0;
    const max = Number(currentValue[item].max) || 0;

    val += dir;
    if (val < min) val = max;
    else if (val > max) val = min;

    currentValue[item].value = val;
    postChange(item, val);

    $(`#${item}-value`).html(val);
    $(`#${item}-stepper-label`).html(`${val} <span class="stepper-max">/ ${max}</span>`);
    $(`#${item}-range`).val(val);
}

// Helper: Create single range block
function createRangeBlock(title, subname, item) {
    return `
        <div class="item-block">
            <p class="item-title">${title}</p>
            <div class="item-bar">
                <div class="second-item-bar">
                    ${createRangeInput(subname, item)}
                </div>
            </div>
        </div>`;
}

// Helper: Create double range block
function createDoubleRangeBlock(title, sub1, item1, sub2, item2) {
    return `
        <div class="item-block">
            <p class="item-title">${title}</p>
            <div class="item-bar">
                <div class="second-item-bar">
                    ${createRangeInput(sub1, item1)}
                    ${createRangeInput(sub2, item2)}
                </div>
            </div>
        </div>`;
}

// Helper: render a swatch grid. Each swatch carries data-field/data-color-id
// so refreshSelectedSwatches() can mark whichever one matches currentValue,
// and so the delegated click handler below knows what to change.
function buildColorSwatches(item, colors) {
    return colors.map(c => `<div class="item-sub-color-selector" data-field="${item}" data-color-id="${c[0]}" style="background: ${c[1]};"></div>`).join('');
}

// Helper: Build eye colors
// Valid native range for SetPedEyeColor is 0-31 (see GetMaxVals().eye_color
// == 31 in client/appearance.lua). id 45 used to be listed here -- clicking
// it silently did nothing since it's outside the native's valid range and
// the game clamps/ignores it. Removed rather than guessed-replaced.
function buildEyeColors() {
    const colors = [
        [0, '#d2d6d3'], [1, '#5c6e36'], [2, '#1f400f'], [3, '#8fcbeb'], [4, '#2e6b94'], [6, '#27c07d'],
        [31, '#947647'], [30, '#593b0a'], [24, '#2e2316'], [9, '#9b9b9b'], [10, '#5f5f5f'], [12, '#0e0e0e']
    ];
    return buildColorSwatches('eye_color', colors);
}

// Helper: Build hair color selectors
function buildHairColors(item) {
    const colors = [
        [0, '#060606'], [2, '#303230'], [3, '#1e0f0a'], [4, '#4e2a1d'], [58, '#42332d'], [18, '#EA3C11'],
        [8, '#8b6444'], [10, '#c4ab75'], [21, '#c21111'], [27, '#696969'], [28, '#a8a8a8'], [34, '#ff0178'],
        [35, '#fc9aff'], [37, '#185579'], [38, '#11288f'], [39, '#269b60'], [43, '#32ad13'], [46, '#eec614']
    ];
    return buildColorSwatches(item, colors);
}

// Navigation functions (heritage mom/dad steppers)
function previous(item) {
    if (currentValue[item].value > currentValue[item].min) {
        if (item === 'mom') {
            if (currentValue[item].value === 45) currentValue[item].value = 41;
            else currentValue[item].value -= 1;
            $(`#${item}-label`).text(translate.parentsNames[item][currentValue[item].value]);
        } else if (item === 'dad') {
            if (currentValue[item].value === 42) currentValue[item].value = 20;
            else currentValue[item].value -= 1;
            $(`#${item}-label`).text(translate.parentsNames[item][currentValue[item].value]);
        } else {
            currentValue[item].value -= 1;
            $(`#${item}-value`).html(currentValue[item].value);
        }
    }
    postChange(item, currentValue[item].value);
}

function next(item) {
    if (currentValue[item].value < currentValue[item].max) {
        if (item === 'mom') {
            if (currentValue[item].value === 41) currentValue[item].value = 45;
            else currentValue[item].value += 1;
            $(`#${item}-label`).text(translate.parentsNames[item][currentValue[item].value]);
        } else if (item === 'dad') {
            if (currentValue[item].value === 20) currentValue[item].value = 42;
            else currentValue[item].value += 1;
            $(`#${item}-label`).text(translate.parentsNames[item][currentValue[item].value]);
        } else {
            currentValue[item].value += 1;
            $(`#${item}-value`).html(currentValue[item].value);
        }
    }
    postChange(item, currentValue[item].value);
}

function changeColor(item, dataId) {
    postChange(item, dataId);
    currentValue[item].value = dataId;
    refreshSelectedSwatches();
}

// Delegated handlers for dynamically-generated controls — no onclick=
// strings anywhere in the templates above (see createRangeInput,
// buildColorSwatches, and the heritage mom/dad arrows in renderFacePanelImpl).
$(document).on('click', '.stepper-btn[data-action="step"]', function() {
    stepItem($(this).data('item'), Number($(this).data('dir')));
});

$(document).on('click', '.item-sub-color-selector[data-field]', function() {
    changeColor($(this).data('field'), $(this).data('color-id'));
});

$(document).on('click', '.parent-nav-btn', function() {
    const item = $(this).data('item');
    const dir = Number($(this).data('dir'));
    if (dir < 0) previous(item); else next(item);
});

function postChange(type, newValue) {
    fetch(`https://${GetParentResourceName()}/appearanceChange`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ type, new: newValue })
    }).catch(() => {});
}

function changeCamera(type) {
    fetch(`https://${GetParentResourceName()}/appearanceCamera`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ type })
    }).catch(() => {});
}

function handsUp() {
    fetch(`https://${GetParentResourceName()}/appearanceHandsUp`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    }).catch(() => {});
}

function saveAppearance() {
    fetch(`https://${GetParentResourceName()}/appearanceSave`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ charId })
    }).catch(() => {});
    document.getElementById('appearance-ui').style.display = 'none';
}

function closeAppearance() {
    fetch(`https://${GetParentResourceName()}/appearanceClose`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    }).catch(() => {});
    document.getElementById('appearance-ui').style.display = 'none';
}

const handsUpBtn = document.getElementById('hands-up-btn');
const saveBtn = document.getElementById('save-btn');
const cancelBtn = document.getElementById('cancel-btn');
if (handsUpBtn) handsUpBtn.addEventListener('click', handsUp);
if (saveBtn) {
    saveBtn.addEventListener('click', () => {
        // Disable instantly on submit — block spam, matches server's own
        // saveAppearance rate limit / appearanceSavePending guard.
        saveBtn.disabled = true;
        saveAppearance();
    });
}
if (cancelBtn) cancelBtn.addEventListener('click', closeAppearance);

// Re-enable Save if the server rejects the save (see the 'error' handling in
// ui/app.js's shared message listener, which re-opens this screen on failure).
window.addEventListener('message', function(event) {
    if (event.data && event.data.action === 'openAppearance' && saveBtn) {
        saveBtn.disabled = false;
    }
});

// Keyboard handling - ESC to leave without edit when cancel is available
$(document).on("keydown", function(event) {
    if (event.key === 'Escape' || event.keyCode === 27) {
        const appUi = document.getElementById('appearance-ui');
        if (appUi && appUi.style.display !== 'none' && canCancel) {
            event.preventDefault();
            event.stopPropagation();
            closeAppearance();
            return false;
        }
        event.preventDefault();
        event.stopPropagation();
        return false;
    }
    if (event.keyCode === 37) direction = "left";
    else if (event.keyCode === 39) direction = "right";
    else if (event.key === handsUpKey) handsUp();
});

// Screen drag rotation and zoom (like nv_cloth clothing store)
let isScreenDragging = false;
let screenLastX = 0;
let screenLastY = 0;
let accDragX = 0;
let accDragY = 0;
let dragFlushQueued = false;

function flushDragUpdates() {
    dragFlushQueued = false;
    if (Math.abs(accDragX) > 0.001 || Math.abs(accDragY) > 0.001) {
        fetch(`https://${GetParentResourceName()}/appearanceDrag`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                deltaX: accDragX,
                deltaY: accDragY
            })
        }).catch(() => {});
    }
    accDragX = 0;
    accDragY = 0;
}

function isInteractiveUiElement(target) {
    if (!target || !target.closest) return false;
    return target.closest('.appearance-panel, .appearance-toolbar, .appearance-categories, .categoryBtn, button, input, select, textarea, .item-block, .item-sub-color-selector') !== null;
}

document.addEventListener('mousedown', function(e) {
    if (isInteractiveUiElement(e.target)) return;
    if (e.button === 0) {
        isScreenDragging = true;
        screenLastX = e.clientX;
        screenLastY = e.clientY;
        accDragX = 0;
        accDragY = 0;
        document.body.classList.add('is-dragging');
    }
});

window.addEventListener('mousemove', function(e) {
    if (!isScreenDragging) return;
    const dx = e.clientX - screenLastX;
    const dy = e.clientY - screenLastY;
    screenLastX = e.clientX;
    screenLastY = e.clientY;

    accDragX += -dx * 0.50;
    accDragY += -dy * 0.003;

    if (!dragFlushQueued) {
        dragFlushQueued = true;
        requestAnimationFrame(flushDragUpdates);
    }
});

window.addEventListener('mouseup', function() {
    if (isScreenDragging) {
        isScreenDragging = false;
        document.body.classList.remove('is-dragging');
    }
});

document.addEventListener('wheel', function(e) {
    if (e.target && e.target.closest && e.target.closest('.appearance-panel')) return;
    const delta = (e.deltaY > 0) ? 1.5 : -1.5;
    fetch(`https://${GetParentResourceName()}/appearanceZoom`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ delta: delta })
    }).catch(() => {});
}, { passive: true });

document.addEventListener('dblclick', function(e) {
    if (isInteractiveUiElement(e.target)) return;
    fetch(`https://${GetParentResourceName()}/appearanceResetCam`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    }).catch(() => {});
});
