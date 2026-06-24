// cm-characters appearance UI controller
// Adapted from vms_charcreator

let currentValue = { clotheset: { min: 0, value: -1, max: 0 } };
let items = {};
let clotheSets = {};
let disabledValues = {};
let handsUpKey = null;
let direction = "";
let charId = null;

// Listen for NUI messages
window.addEventListener('message', function(event) {
    const item = event.data;

    if (item.action === "openAppearance") {
        // FIX: Show appearance container, hide slots
        document.getElementById('appearance-ui').style.display = 'block';
        document.getElementById('app').classList.add('hidden');
        
        $('.categories').empty();
        $('.panel').empty();

        document.getElementById("rotate-input").value = (item.currentRotate || 0).toString();
        document.getElementById("distance-input").value = (item.currentDistance || 30).toString();

        $('#headerName').text(translate.create_character);
        $('#headerCategory').text(translate.select_category);
        $('#height-text').text(translate.height);
        $('#rotate-text').text(translate.rotate);
        $('#distance-text').text(translate.distance);
        $('#save').text(translate.save);

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

        if (item.categories) {
            if (item.categories['parents']) {
                $('.categories').append(`<div class="parents categoryBtn" data-type="parents">DNA</div>`);
            }
            if (item.categories['face']) {
                $('.categories').append(`<div class="face categoryBtn" data-type="face">FACE</div>`);
            }
            if (item.categories['clothes']) {
                $('.categories').append(`<div class="clothes categoryBtn" data-type="clothes">FIT</div>`);
            }
            if (item.categories['clothesets']) {
                $('.categories').append(`<div class="clothesets categoryBtn" data-type="clothesets">SET</div>`);
            }
            if (item.categories['hairs']) {
                $('.categories').append(`<div class="hairs categoryBtn" data-type="hairs">HAIR</div>`);
            }
            if (item.categories['makeup']) {
                $('.categories').append(`<div class="makeup categoryBtn" data-type="makeup">MAKE</div>`);
            }
        }

        setTimeout(() => {
            const firstCategory = document.querySelector('.categoryBtn');
            if (firstCategory) firstCategory.click();
        }, 80);

        for (const [key, value] of Object.entries(item.data || {})) {
            // ClockMate starter clothing limit:
            // hard-limit T-Shirt, Torso, Pants and Shoes sliders to max 2.
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
    }

    if (item.action === 'updateSecondValue') {
        const range = document.getElementById(`${item.secondItem}-range`);
        if (range) {
            range.max = item.secondValue;
            range.value = 0;
        }
        const valEl = document.getElementById(`${item.secondItem}-value`);
        if (valEl) valEl.innerHTML = 0;
        const maxEl = document.getElementById(`${item.secondItem}-max`);
        if (maxEl) maxEl.innerHTML = item.secondValue;
    }

    if (item.action === 'updateInputs') {
        const distInput = document.getElementById("distance-input");
        if (distInput) distInput.value = (item.fov || 30).toString();
    }
});

// Category click handler
$(document).on('click', '.categoryBtn', function(e) {
    $('.categoryBtn').removeClass('active');
    $(this).addClass('active');
    $('.panel').empty();
    const type = $(this).data("type");
    $('#headerCategory').html(translate.category[type] || type.toUpperCase());
    changeCamera(type);

    let values = '';

    switch(type) {
        case "parents":
            values = buildParentsPanel();
            break;
        case "face":
            values = buildFacePanel();
            break;
        case "clothes":
            values = buildClothesPanel();
            break;
        case "clothesets":
            values = buildClotheSetsPanel();
            break;
        case "hairs":
            values = buildHairPanel();
            break;
        case "makeup":
            values = buildMakeupPanel();
            break;
    }

    $('.panel').html(values);
});

// Build Parents Panel
function buildParentsPanel() {
    let values = '';

    if (items['parents'] && items['parents'].sex) {
        values += createRangeBlock(translate.title_sex, translate.sub_sex, 'sex');
    }
    if (items['parents'] && items['parents'].parents) {
        values += `
            <div class="item-block">
                <p class="item-title">${translate.title_parents}</p>
                <div class="item-bar">
                    <div class="second-item-bar">
                        <div class="item-option">
                            <div class="parent-photo" id="mom-photo" style="background: linear-gradient(135deg, #ff6b6b, #ee5a24);"></div>
                            <p class="item-subname">${translate.sub_mom}</p>
                            <div class="item-suboptions">
                                <div class="item-suboptions-values left-arrow" onclick="previous('mom')">‹</div>
                                <div class="item-suboptions-values"><p class="item-label" id="mom-label">${translate.parentsNames.mom[currentValue['mom'].value] || 'Unknown'}</p></div>
                                <div class="item-suboptions-values right-arrow" onclick="next('mom')">›</div>
                            </div>
                        </div>
                        <div class="item-option">
                            <div class="parent-photo" id="dad-photo" style="background: linear-gradient(135deg, #4834d4, #686de0);"></div>
                            <p class="item-subname">${translate.sub_dad}</p>
                            <div class="item-suboptions">
                                <div class="item-suboptions-values left-arrow" onclick="previous('dad')">‹</div>
                                <div class="item-suboptions-values"><p class="item-label" id="dad-label">${translate.parentsNames.dad[currentValue['dad'].value] || 'Unknown'}</p></div>
                                <div class="item-suboptions-values right-arrow" onclick="next('dad')">›</div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>`;
    }
    if (items['parents'] && items['parents'].face_md_weight) {
        values += createRangeBlock(translate.title_resemblance, translate.sub_face_md_weight, 'face_md_weight');
    }
    if (items['parents'] && items['parents'].skin_md_weight) {
        values += createRangeBlock(translate.title_skin_md_weight, translate.sub_skin_md_weight, 'skin_md_weight');
    }

    return values;
}

// Build Face Panel
function buildFacePanel() {
    let values = '';

    if (items['face'] && items['face'].neck_thickness) {
        values += createRangeBlock(translate.title_neck_thickness, translate.sub_neck_thickness, 'neck_thickness');
    }
    if (items['face'] && items['face'].age) {
        values += createDoubleRangeBlock(translate.title_ageing, translate.sub_age_1, 'age_1', translate.sub_age_2, 'age_2');
    }
    if (items['face'] && items['face'].eyebrows) {
        values += createDoubleRangeBlock(translate.title_eyebrow, translate.sub_eyebrows_5, 'eyebrows_5', translate.sub_eyebrows_6, 'eyebrows_6');
    }
    if (items['face'] && items['face'].nose) {
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
    if (items['face'] && items['face'].cheeks) {
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
    if (items['face'] && items['face'].lip_thickness) {
        values += createRangeBlock(translate.title_lips, translate.sub_lip_thickness, 'lip_thickness');
    }
    if (items['face'] && items['face'].jaw) {
        values += createDoubleRangeBlock(translate.title_jaw, translate.sub_jaw_1, 'jaw_1', translate.sub_jaw_2, 'jaw_2');
    }
    if (items['face'] && items['face'].chin) {
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
    if (items['face'] && items['face'].eye_color) {
        values += `
            <div class="item-block">
                <p class="item-title">${translate.title_eye_color}</p>
                <div class="item-bar">
                    <p class="item-subname">${translate.sub_eye_color}</p>
                    <div class="color-selector-bar">
                        <div class="item-sub-color-selector" style="background: #d2d6d3;" onclick="changeColor('eye_color', 0)">✓</div>
                        <div class="item-sub-color-selector" style="background: #5c6e36;" onclick="changeColor('eye_color', 45)">✓</div>
                        <div class="item-sub-color-selector" style="background: #1f400f;" onclick="changeColor('eye_color', 2)">✓</div>
                        <div class="item-sub-color-selector" style="background: #8fcbeb;" onclick="changeColor('eye_color', 3)">✓</div>
                        <div class="item-sub-color-selector" style="background: #2e6b94;" onclick="changeColor('eye_color', 4)">✓</div>
                        <div class="item-sub-color-selector" style="background: #27c07d;" onclick="changeColor('eye_color', 6)">✓</div>
                        <div class="item-sub-color-selector" style="background: #947647;" onclick="changeColor('eye_color', 31)">✓</div>
                        <div class="item-sub-color-selector" style="background: #593b0a;" onclick="changeColor('eye_color', 30)">✓</div>
                        <div class="item-sub-color-selector" style="background: #2e2316;" onclick="changeColor('eye_color', 24)">✓</div>
                        <div class="item-sub-color-selector" style="background: #9b9b9b;" onclick="changeColor('eye_color', 9)">✓</div>
                        <div class="item-sub-color-selector" style="background: #5f5f5f;" onclick="changeColor('eye_color', 10)">✓</div>
                        <div class="item-sub-color-selector" style="background: #0e0e0e;" onclick="changeColor('eye_color', 12)">✓</div>
                    </div>
                </div>
            </div>`;
    }
    if (items['face'] && items['face'].blemishes) {
        values += createDoubleRangeBlock(translate.title_blemishes, translate.sub_blemishes_1, 'blemishes_1', translate.sub_blemishes_2, 'blemishes_2');
    }
    if (items['face'] && items['face'].complexion) {
        values += createDoubleRangeBlock(translate.title_complexion, translate.sub_complexion_1, 'complexion_1', translate.sub_complexion_2, 'complexion_2');
    }
    if (items['face'] && items['face'].sun) {
        values += createDoubleRangeBlock(translate.title_sun, translate.sub_sun_1, 'sun_1', translate.sub_sun_2, 'sun_2');
    }
    if (items['face'] && items['face'].moles) {
        values += createDoubleRangeBlock(translate.title_moles, translate.sub_moles_1, 'moles_1', translate.sub_moles_2, 'moles_2');
    }

    return values;
}

// Build Clothes Panel
function buildClothesPanel() {
    let values = '';
    const clothItems = ['tshirt', 'torso', 'arms', 'pants', 'shoes', 'decals', 'mask', 'bproof', 'chain', 'helmet', 'glasses', 'watches', 'bracelets', 'bags', 'ears'];

    const titles = {
        tshirt: translate.title_tshirt, torso: translate.title_torso, arms: translate.title_arms,
        pants: translate.title_pants, shoes: translate.title_shoes, decals: translate.title_decals,
        mask: translate.title_mask, bproof: translate.title_bproof, chain: translate.title_chain,
        helmet: translate.title_helmet, glasses: translate.title_glasses, watches: translate.title_watches,
        bracelets: translate.title_bracelets, bags: translate.title_bags, ears: translate.title_ears
    };

    const subs1 = {
        tshirt: translate.sub_tshirt_1, torso: translate.sub_torso_1, arms: translate.sub_arms,
        pants: translate.sub_pants_1, shoes: translate.sub_shoes_1, decals: translate.sub_decals_1,
        mask: translate.sub_mask_1, bproof: translate.sub_bproof_1, chain: translate.sub_chain_1,
        helmet: translate.sub_helmet_1, glasses: translate.sub_glasses_1, watches: translate.sub_watches_1,
        bracelets: translate.sub_bracelets_1, bags: translate.sub_bags_1, ears: translate.sub_ears_1
    };

    const subs2 = {
        tshirt: translate.sub_tshirt_2, torso: translate.sub_torso_2, arms: translate.sub_arms_2,
        pants: translate.sub_pants_2, shoes: translate.sub_shoes_2, decals: translate.sub_decals_2,
        mask: translate.sub_mask_2, bproof: translate.sub_bproof_2, chain: translate.sub_chain_2,
        helmet: translate.sub_helmet_2, glasses: translate.sub_glasses_2, watches: translate.sub_watches_2,
        bracelets: translate.sub_bracelets_2, bags: translate.sub_bags_2, ears: translate.sub_ears_2
    };

    for (const item of clothItems) {
        if (items['clothes'] && items['clothes'][item]) {
            const key1 = item + '_1';
            const key2 = item + '_2';
            values += `
                <div class="item-block">
                    <p class="item-title">${titles[item]}</p>
                    <div class="item-bar">
                        <div class="second-item-bar">
                            ${createRangeInput(subs1[item], key1)}
                            ${createRangeInput(subs2[item], key2)}
                        </div>
                    </div>
                </div>`;
        }
    }

    return values;
}

// Build ClotheSets Panel
function buildClotheSetsPanel() {
    return `
        <div class="item-block">
            <p class="item-title">${translate.title_clothesets}</p>
            <div class="item-bar">
                <div class="second-item-bar">
                    <div class="item-option">
                        <p class="item-subname">${translate.sub_clotheset}</p>
                        <div class="item-suboptions">
                            <div class="item-suboptions-values left-arrow" onclick="previousClotheSets()">‹</div>
                            <div class="item-suboptions-values"><p class="item-label" id="clotheset-label">${(currentValue['clotheset'] && clotheSets[currentValue['clotheset'].value]) ? clotheSets[currentValue['clotheset'].value].name : 'NONE'}</p></div>
                            <div class="item-suboptions-values right-arrow" onclick="nextClotheSets()">›</div>
                        </div>
                    </div>
                </div>
            </div>
        </div>`;
}

// Build Hair Panel
function buildHairPanel() {
    let values = '';

    if (items['hairs'] && items['hairs'].hair) {
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
    if (items['hairs'] && items['hairs'].beard) {
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
    if (items['hairs'] && items['hairs'].eyebrow) {
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
    if (items['hairs'] && items['hairs'].chesthair) {
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

// Build Makeup Panel
function buildMakeupPanel() {
    let values = '';

    if (items['makeup'] && items['makeup'].makeup) {
        values += `
            <div class="item-block">
                <p class="item-title">${translate.title_makeup}</p>
                <div class="item-bar">
                    <div class="second-item-bar">
                        ${createRangeInput(translate.sub_makeup_1, 'makeup_1')}
                        ${createRangeInput(translate.sub_makeup_2, 'makeup_2')}
                    </div>
                    <p class="item-subname">${translate.sub_makeup_3}</p>
                    <div class="color-selector-bar">
                        ${buildMakeupColors('makeup_3')}
                    </div>
                </div>
            </div>`;
    }
    if (items['makeup'] && items['makeup'].blush) {
        values += `
            <div class="item-block">
                <p class="item-title">${translate.title_blush}</p>
                <div class="item-bar">
                    <div class="second-item-bar">
                        ${createRangeInput(translate.sub_blush_1, 'blush_1')}
                        ${createRangeInput(translate.sub_blush_2, 'blush_2')}
                    </div>
                    <p class="item-subname">${translate.sub_blush_3}</p>
                    <div class="color-selector-bar">
                        ${buildBlushColors('blush_3')}
                    </div>
                </div>
            </div>`;
    }
    if (items['makeup'] && items['makeup'].lipstick) {
        values += `
            <div class="item-block">
                <p class="item-title">${translate.title_lipstick}</p>
                <div class="item-bar">
                    <div class="second-item-bar">
                        ${createRangeInput(translate.sub_lipstick_1, 'lipstick_1')}
                        ${createRangeInput(translate.sub_lipstick_2, 'lipstick_2')}
                    </div>
                    <p class="item-subname">${translate.sub_lipstick_3}</p>
                    <div class="color-selector-bar">
                        ${buildLipstickColors('lipstick_3')}
                    </div>
                </div>
            </div>`;
    }

    return values;
}

// Helper: Create range input HTML
function createRangeInput(subname, item) {
    const cv = currentValue[item];
    if (!cv) return '';
    return `
        <div class="item-option">
            <div class="item-values">
                <p class="item-subname">${subname}</p>
                <p class="item-value" id="${item}-value">${cv.value}</p>
            </div>
            <div class="item-suboptions">
                <input type="range" min="${cv.min}" max="${cv.max}" value="${cv.value}" data-excluded="${cv.excluded ? cv.excluded.join(',') : ''}" class="input-value-radius" id="${item}-range" oninput="changeRange('${item}')">
            </div>
        </div>`;
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

// Helper: Build hair color selectors
function buildHairColors(item) {
    const colors = [
        [0, '#060606'], [2, '#303230'], [3, '#1e0f0a'], [4, '#4e2a1d'], [58, '#42332d'], [18, '#EA3C11'],
        [8, '#8b6444'], [10, '#c4ab75'], [21, '#c21111'], [27, '#696969'], [28, '#a8a8a8'], [34, '#ff0178'],
        [35, '#fc9aff'], [37, '#185579'], [38, '#11288f'], [39, '#269b60'], [43, '#32ad13'], [46, '#eec614']
    ];
    return colors.map(c => `<div class="item-sub-color-selector" style="background: ${c[1]};" onclick="changeColor('${item}', ${c[0]})">✓</div>`).join('');
}

// Helper: Build makeup colors
function buildMakeupColors(item) {
    const colors = [
        [17, '#e775a4'], [18, '#de3e81'], [24, '#cf0813'], [0, '#992532'], [20, '#712739'], [56, '#180e0e'],
        [45, '#ffdd26'], [47, '#f78a27'], [37, '#25c2d2'], [34, '#1d4ea7'], [40, '#1b9c32'], [32, '#6d1a9d']
    ];
    return colors.map(c => `<div class="item-sub-color-selector" style="background: ${c[1]};" onclick="changeColor('${item}', ${c[0]})">✓</div>`).join('');
}

// Helper: Build blush colors
function buildBlushColors(item) {
    const colors = [
        [18, '#de3e81'], [20, '#712739'], [21, '#4f1f2a'], [7, '#a4645d'], [13, '#a84c33'], [24, '#cf0813']
    ];
    return colors.map(c => `<div class="item-sub-color-selector" style="background: ${c[1]};" onclick="changeColor('${item}', ${c[0]})">✓</div>`).join('');
}

// Helper: Build lipstick colors
function buildLipstickColors(item) {
    const colors = [
        [54, '#880302'], [53, '#ff0505'], [51, '#d1593c'], [34, '#eb4b93'], [38, '#023974'], [39, '#3fa16a']
    ];
    return colors.map(c => `<div class="item-sub-color-selector" style="background: ${c[1]};" onclick="changeColor('${item}', ${c[0]})">✓</div>`).join('');
}

// Navigation functions
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

function previousClotheSets() {
    if (clotheSets[currentValue['clotheset'].value - 1]) {
        currentValue['clotheset'].value -= 1;
        $('#clotheset-label').html(clotheSets[currentValue['clotheset'].value].name);
    }
    postChange('clotheset', currentValue['clotheset'].value);
}

function nextClotheSets() {
    if (clotheSets[currentValue['clotheset'].value + 1]) {
        currentValue['clotheset'].value += 1;
        $('#clotheset-label').html(clotheSets[currentValue['clotheset'].value].name);
    }
    postChange('clotheset', currentValue['clotheset'].value);
}

function changeColor(item, dataId) {
    postChange(item, dataId);
    currentValue[item].value = dataId;
}

function changeRange(item) {
    let inputValue = parseInt($(`#${item}-range`).val());
    let result = inputValue;
    const excluded = $(`#${item}-range`).data('excluded');

    if (excluded) {
        const excludedValues = excluded.split(',').map(Number).filter(n => !isNaN(n));
        if (excludedValues.includes(inputValue)) {
            result = findClosestValue(inputValue, excludedValues);
            $(`#${item}-range`).val(result);
        }
    }

    if (result !== currentValue[item].value) {
        currentValue[item].value = result;
        postChange(item, Number(result));
        $(`#${item}-value`).html(currentValue[item].value);
    }
}

function findClosestValue(value, excludedValues) {
    let closestValue = value;
    while (excludedValues.includes(closestValue)) {
        if (direction === "left") closestValue--;
        else closestValue++;
    }
    return closestValue;
}

function postChange(type, newValue) {
    fetch(`https://${GetParentResourceName()}/appearanceChange`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ type, new: newValue })
    });
}

function changeCamera(type) {
    fetch(`https://${GetParentResourceName()}/appearanceCamera`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ type })
    });
}

function changeHeight() {
    const height = document.getElementById('height-input').value;
    fetch(`https://${GetParentResourceName()}/appearanceHeight`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ height })
    });
}

function changeRotate() {
    const rotate = document.getElementById('rotate-input').value;
    fetch(`https://${GetParentResourceName()}/appearanceRotate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ rotate })
    });
}

function changeDistance() {
    const distance = document.getElementById('distance-input').value;
    fetch(`https://${GetParentResourceName()}/appearanceDistance`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ distance })
    });
}

function handsUp() {
    fetch(`https://${GetParentResourceName()}/appearanceHandsUp`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    });
}

function saveAppearance() {
    fetch(`https://${GetParentResourceName()}/appearanceSave`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ charId })
    });
    document.getElementById('appearance-ui').style.display = 'none';
}

// Keyboard handling
$(document).on("keydown", function(event) {
    if (event.keyCode === 37) direction = "left";
    else if (event.keyCode === 39) direction = "right";
    else if (event.key === handsUpKey) handsUp();
});

