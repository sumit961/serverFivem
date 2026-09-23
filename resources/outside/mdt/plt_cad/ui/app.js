window.addEventListener('keyup', (e) => {
    if (e.key === 'Escape') {
        fetch(`https://plt_cad/closeNui`, {
            method: 'POST',
            body: JSON.stringify({})
        });
    }
});

// ── Field input via NUI overlay ───────────────────────────────
let fieldInputOverlay = null;

function nuiPost(endpoint, data) {
    fetch('https://plt_cad/' + endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data || {})
    }).catch(function() {});
}

window.addEventListener('message', function(e) {
    var data = e.data;

    if (data.type === 'fieldInput') {
        showFieldOverlay(data.fieldId, data.label, data.current);
    }
    if (data.type === 'hideFieldInput') {
        hideFieldOverlay();
    }
    if (data.type === 'fieldResult') {
        var el = document.getElementById(data.fieldId);
        if (el && data.value !== null) {
            el.value = data.value;
            el.dispatchEvent(new Event('input', { bubbles: true }));
        }
    }
});

function showFieldOverlay(fieldId, label, current) {
    hideFieldOverlay();

    var overlay = document.createElement('div');
    overlay.id = 'field-input-overlay';
    overlay.style.position = 'fixed';
    overlay.style.inset = '0';
    overlay.style.zIndex = '9999';
    overlay.style.display = 'flex';
    overlay.style.alignItems = 'center';
    overlay.style.justifyContent = 'center';
    overlay.style.background = 'rgba(0,0,0,0.7)';

    var box = document.createElement('div');
    box.style.cssText = 'background:#07101a;border:2px solid #3498db;padding:20px;width:400px;border-radius:4px;font-family:Consolas,monospace;';

    var lbl = document.createElement('div');
    lbl.style.cssText = 'color:#3498db;font-size:11px;font-weight:bold;letter-spacing:1px;margin-bottom:10px;text-transform:uppercase;';
    lbl.innerText = label;

    var inp = document.createElement('input');
    inp.type = 'text';
    inp.id = 'field-overlay-input';
    inp.value = current || '';
    inp.autocomplete = 'off';
    inp.style.cssText = 'width:100%;background:#0a1b2d;border:1px solid #3498db;color:#fff;padding:10px;font-family:inherit;font-size:13px;box-sizing:border-box;outline:none;';

    var hint = document.createElement('div');
    hint.style.cssText = 'color:#5d7a8c;font-size:10px;margin-top:8px;';
    hint.innerText = 'ENTER to confirm  ·  ESC to cancel';

    box.appendChild(lbl);
    box.appendChild(inp);
    box.appendChild(hint);
    overlay.appendChild(box);
    document.body.appendChild(overlay);

    fieldInputOverlay = { overlay: overlay, fieldId: fieldId };

    inp.focus();
    inp.setSelectionRange(inp.value.length, inp.value.length);

    inp.addEventListener('keydown', function(e) {
        if (e.key === 'Enter') {
            e.preventDefault();
            submitFieldOverlay(inp.value);
        } else if (e.key === 'Escape') {
            e.preventDefault();
            cancelFieldOverlay();
        }
    });
}

function hideFieldOverlay() {
    if (fieldInputOverlay) {
        fieldInputOverlay.overlay.remove();
        fieldInputOverlay = null;
    }
}

function submitFieldOverlay(value) {
    var fieldId = fieldInputOverlay ? fieldInputOverlay.fieldId : null;
    hideFieldOverlay();
    nuiPost('closeFieldInput', { fieldId: fieldId, value: value });
}

function cancelFieldOverlay() {
    var fieldId = fieldInputOverlay ? fieldInputOverlay.fieldId : null;
    hideFieldOverlay();
    nuiPost('closeFieldInput', { fieldId: fieldId, value: null });
}

// Intercept clicks on inputs/textareas in DUI to trigger NUI overlay
document.addEventListener('mousedown', function(e) {
    var el = e.target;
    if (el.id === 'field-overlay-input') return;
    if ((el.tagName === 'INPUT' && el.type !== 'hidden') || el.tagName === 'TEXTAREA') {
        e.preventDefault();
        if (!el.id) { el.id = 'field_' + Date.now(); }
        var label = el.getAttribute('placeholder') || 'ENTER TEXT';
        var fg = el.closest('.form-group');
        if (fg) {
            var lbl = fg.querySelector('label');
            if (lbl) label = lbl.innerText;
        }
        nuiPost('openFieldInput', { fieldId: el.id, label: label, current: el.value || '' });
    }
});



const app = document.getElementById('app');
const cursor = document.getElementById('cursor');

console.log('CAD UI Loaded');

// Helper to send sync events to the client
function syncInteraction(data) {
    // Explicitly use the resource name for DUI compatibility
    fetch(`https://plt_cad/syncInteraction`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data)
    }).catch(err => console.log('Sync error:', err));
}

let lastCallIds = new Set();
let callHistory = [];
let activeFlashes = {}; // Tracking active flashes with timestamps
let isInitialLoad = true; // Added: Prevent flashing everything on restart

window.addEventListener('message', (event) => {
    const data = event.data;
    
    if (data.type === 'show') {
        app.style.display = data.state ? 'flex' : 'none';
        if (data.state) {
            document.body.classList.add('mode-2d');
            cursor.style.display = 'none';
        } else {
            document.body.classList.remove('mode-2d');
        }
    }

    if (data.type === 'dui_cursor') {
        document.body.classList.remove('mode-2d'); // Ensure 3D mode if cursor is active
        if (data.show) {
            cursor.style.display = 'block';
            cursor.style.left = (data.u * 100) + '%';
            cursor.style.top = (data.v * 100) + '%';
        } else {
            cursor.style.display = 'none';
        }
    }

    if (data.type === 'changePage') {
        internalChangePage(data.pageId, true);
        if (data.pageId === 'records') {
            syncInteraction({ type: 'getRecords' });
        }
    }

    if (data.type === 'searchCitizen') {
        internalSearchCitizen(data.query, true);
    }

    if (data.type === 'vehicleResult') {
        updateVehicleResults(data.plate, data.owner, data.model, data.bolo);
    }

    if (data.type === 'callDetails') {
        updateCallDetails(data.details);
    }

    if (data.type === 'setup') {
        const name = data.name || 'UNKNOWN';
        document.getElementById('my-name-store').value = name;

        if (data.headerLeft) document.getElementById('header-left').innerText = data.headerLeft;
        if (data.headerRight) document.getElementById('header-right').innerText = data.headerRight;

        // Ensure UI is visible for DUI/Initial load
        app.style.display = 'flex';
    }

    if (data.type === 'updateData') {
        if (data.officers) updateUnitTable(data.officers);
        if (data.calls) {
            updateCallsTable(data.calls);
            isInitialLoad = false; // First load finished
        }
        
        // Update local current-status if we are in the list
        const myName = document.getElementById('my-name-store').value;
        if (data.officers) {
            const me = data.officers.find(o => o.name === myName);
            if (me) {
                setStatus(me.status, true);
            }
        }
    }

    if (data.type === 'setStatus') {
        setStatus(data.status, true);
    }
});

function updateUnitTable(officers) {
    const tbody = document.getElementById('unit-table-body');
    if (!tbody) return;
    
    tbody.innerHTML = '';
    
    officers.forEach(off => {
        const tr = document.createElement('tr');
        tr.className = 'status-row-' + off.status;
        
        tr.innerHTML = `
            <td>${off.name}</td>
            <td>${off.unit}</td>
            <td>${off.status}</td>
            <td>${off.agency}</td>
            <td>${off.source === undefined ? 'OFFLINE' : '(MDC) ACTIVE'}</td>
        `;
        tbody.appendChild(tr);
    });
}

function updateCallsTable(calls) {
    const tbody = document.getElementById('calls-table-body');
    const histBody = document.getElementById('history-table-body');
    if (!tbody || !histBody) return;
    
    tbody.innerHTML = '';
    
    // Add to history list if unique
    calls.forEach(call => {
        if (!callHistory.find(c => c.id === call.id)) {
            callHistory.unshift(call); // Newest at top
        }
    });
    
    // Update history table
    histBody.innerHTML = '';
    callHistory.forEach(call => {
        const tr = document.createElement('tr');
        tr.style.cursor = 'pointer';
        tr.onclick = () => showCallDetails(call.id);
        const nature = (call.code ? call.code + ' ' : '') + (call.title || '911 CALL');
        const assigned = Array.isArray(call.assigned) ? call.assigned.join(', ') : (call.assigned || 'NONE');
        tr.innerHTML = `<td>${call.id}</td><td>${nature}</td><td>${call.location}</td><td>${call.status}</td><td>${assigned}</td>`;
        histBody.appendChild(tr);
    });

    // Update active table
    // Explicitly sort by ID descending to ensure newest is at the top
    const sortedCalls = [...calls].sort((a, b) => b.id - a.id);
    const now = Date.now();
    const flashDuration = 15000; // 15 seconds

    sortedCalls.forEach(call => {
        const tr = document.createElement('tr');
        tr.style.cursor = 'pointer';
        tr.onclick = () => showCallDetails(call.id);
        
        const callIdStr = String(call.id);
        const isActuallyNew = !lastCallIds.has(call.id);
        
        // If it's brand new AND not the first load, start the flash timer
        if (isActuallyNew && !activeFlashes[callIdStr] && !isInitialLoad) {
            activeFlashes[callIdStr] = now;
        }

        const nature = (call.code ? call.code + ' ' : '') + (call.title || '911 CALL');
        const assigned = Array.isArray(call.assigned) ? call.assigned.join(', ') : (call.assigned || 'NONE');
        
        if (call.status === 'RESOLVED' || call.status === 'DONE') {
            tr.className = 'row-resolved';
        } else if (assigned === 'NONE') {
            tr.className = 'row-active'; // Red if no one is assigned
        } else {
            tr.className = 'row-pending'; // Orange if at least one unit is assigned
        }

        // Check if this call should still be flashing
        if (activeFlashes[callIdStr]) {
            const elapsed = now - activeFlashes[callIdStr];
            if (elapsed < flashDuration) {
                tr.classList.add('new-call-flash');
            } else {
                // Time's up, stop flashing
                delete activeFlashes[callIdStr];
            }
        }
        
        tr.innerHTML = `
            <td>${call.id}</td>
            <td>${nature}</td>
            <td>${call.location}</td>
            <td>${call.status}</td>
            <td>${assigned}</td>
        `;
        tbody.appendChild(tr);
    });

    // Store IDs for next update
    lastCallIds = new Set(calls.map(c => c.id));
}

let currentCallId = null;

function showCallDetails(callId) {
    currentCallId = callId;
    changePage('call-details');
    syncInteraction({ type: 'getCallDetails', callId: callId });
}

function updateCallDetails(det) {
    document.getElementById('det-title').innerText = `CALL DETAILS #${det.id}`;
    document.getElementById('det-nature').innerText = (det.code ? det.code + ' ' : '') + (det.title || 'UNKNOWN');
    document.getElementById('det-location').innerText = det.location || 'UNKNOWN';
    document.getElementById('det-status').innerText = det.status || 'UNKNOWN';
    document.getElementById('det-coords').innerText = det.coords ? `${Math.round(det.coords.x)}, ${Math.round(det.coords.y)}, ${Math.round(det.coords.z)}` : 'N/A';
    document.getElementById('det-info').innerText = det.info || 'NO ADDITIONAL INFORMATION PROVIDED';
    
    const assignBtn = document.getElementById('assign-btn');
    if (assignBtn) {
        assignBtn.onclick = () => {
            console.log('Assigning unit to call:', det.id);
            syncInteraction({ type: 'assignCall', callId: det.id });
            // Visual feedback
            assignBtn.innerText = 'ASSIGNING...';
            assignBtn.disabled = true;
            setTimeout(() => {
                assignBtn.innerText = 'ASSIGN UNIT';
                assignBtn.disabled = false;
            }, 2000);
        };
    }

    const resolveBtn = document.getElementById('resolve-btn');
    if (resolveBtn) {
        if (det.status === 'RESOLVED' || det.status === 'DONE') {
            resolveBtn.style.display = 'none';
        } else {
            resolveBtn.style.display = 'block';
            resolveBtn.onclick = () => {
                console.log('Resolving call:', det.id);
                syncInteraction({ type: 'resolveCall', callId: det.id });
                resolveBtn.innerText = 'RESOLVING...';
                resolveBtn.disabled = true;
                setTimeout(() => {
                    resolveBtn.style.display = 'none';
                    resolveBtn.disabled = false;
                    resolveBtn.innerText = 'RESOLVE CALL';
                }, 1000);
            };
        }
    }
}

function internalChangePage(pageId, isSync) {
    document.querySelectorAll('.page').forEach(p => p.style.display = 'none');
    document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
    
    const targetPage = document.getElementById(pageId);
    if (targetPage) {
        targetPage.style.display = 'flex';
        // Add active class to the corresponding nav item
        const navItem = document.getElementById('nav-' + pageId);
        if (navItem) navItem.classList.add('active');
    }
    
    if (!isSync) {
        syncInteraction({ type: 'changePage', pageId: pageId });
    }
}

function setStatus(status, isSync) {
    const statusText = document.getElementById('current-status');
    if (statusText) {
        statusText.innerText = status;
        
        if (status === 'AVAILABLE') statusText.style.color = '#4caf50';
        else if (status === 'BUSY') statusText.style.color = '#ffeb3b';
        else if (status === 'UNAVAILABLE') statusText.style.color = '#f44336';
        else if (status === 'TRAINING') statusText.style.color = '#2196f3';
    }

    if (!isSync) {
        syncInteraction({ type: 'setStatus', status: status });
    }
}

function changePage(pageId) {
    internalChangePage(pageId, false);
    if (pageId === 'records') {
        syncInteraction({ type: 'getRecords' });
    }
}

function internalSearchCitizen(query, isSync) {
    document.getElementById('citizen-query').value = query;
    console.log('Searching for:', query);
    document.getElementById('search-results').innerHTML = `<p>Searching for ${query}... (Connect to server for real data)</p>`;
    
    // Switch to citizen search page
    internalChangePage('search', true);

    if (!isSync) {
        syncInteraction({ type: 'searchCitizen', query: query });
    }
}

function searchCitizen() {
    const query = document.getElementById('citizen-query').value;
    internalSearchCitizen(query, false);
}

function searchVehicle() {
    changePage('vehicle-search');
}

function startScan() {
    document.getElementById('scan-btn').style.display = 'none';
    document.getElementById('vehicle-results').style.display = 'none';
    document.getElementById('loading-indicator').style.display = 'block';
    
    // 5 second delay for "realism"
    setTimeout(() => {
        document.getElementById('loading-indicator').style.display = 'none';
        document.getElementById('scan-btn').style.display = 'block';
        syncInteraction({ type: 'scanVehicle' });
    }, 5000);
}

function updateVehicleResults(plate, owner, model, bolo) {
    const results = document.getElementById('vehicle-results');
    if (!results) return; // Prevent errors if not on vehicle page
    results.style.display = 'block';
    
    document.getElementById('scanned-plate').innerText = plate || 'NO VEHICLE FOUND';
    const ownerInfo = document.getElementById('owner-info');
    
    if (plate) {
        let boloHtml = '';
        if (bolo) {
            boloHtml = `
                <div style="background: rgba(244, 67, 54, 0.15); border: 1px solid #f44336; border-radius: 3px; padding: 6px; margin-top: 10px; animation: pulse 2s infinite;">
                    <p style="color: #f44336; font-weight: bold; margin-bottom: 2px; font-size: 14px;">⚠️ ALPR HIT: BOLO DETECTED</p>
                    <p style="font-size: 13px; margin-bottom: 2px;">TITLE: ${bolo.title || 'N/A'}</p>
                    <p style="font-size: 13px;">REASON: ${bolo.description || 'N/A'}</p>
                </div>
            `;
        }

        ownerInfo.innerHTML = `
            <div class="result-details" style="font-size: 15px;">
                <p style="margin-bottom: 5px;">MODEL: <span style="color: #fff; font-weight: bold;">${model || 'UNKNOWN'}</span></p>
                <p style="margin-bottom: 5px;">OWNER: <span style="color: #fff; font-weight: bold;">${owner || 'UNREGISTERED'}</span></p>
                ${boloHtml}
                <p style="margin-top: 10px; color: #4caf50; font-size: 11px; opacity: 0.8;">>>> INQUIRY COMPLETED <<<</p>
            </div>
        `;
    } else {
        ownerInfo.innerHTML = '<p style="color: #f44336; font-weight: bold; font-size: 16px; text-align: center; margin-top: 10px;">FAILED TO SCAN PLATE - NO VEHICLE IN RANGE</p>';
    }
}

// Notepad Persistence
const notepadArea = document.getElementById('notepad-area');
if (notepadArea) {
    // Load saved notes
    const savedNotes = localStorage.getItem('plt_cad_notes');
    if (savedNotes) notepadArea.value = savedNotes;

    // Save on input
    notepadArea.addEventListener('input', (e) => {
        localStorage.setItem('plt_cad_notes', e.target.value);
    });
}

function clearNotepad() {
    if (confirm('ARE YOU SURE YOU WANT TO CLEAR ALL FIELD NOTES?')) {
        notepadArea.value = '';
        localStorage.removeItem('plt_cad_notes');
    }
}

// Forms Logic
function openForm(type) {
    const content = document.getElementById('form-content');
    let html = '';

    if (type === 'arrest') {
        html = `
            <div class="table-header" style="margin-bottom:15px; background:#c0392b;">ARREST REPORT - FORM 10-15</div>
            <div class="form-group">
                <label>SUSPECT NAME / CID</label>
                <input type="text" id="f-arrest-name" placeholder="John Doe / 12345">
            </div>
            <div class="form-group">
                <label>CHARGES</label>
                <textarea id="f-arrest-charges" style="width:100%; height:80px;" placeholder="List all criminal charges..."></textarea>
            </div>
            <div class="form-group">
                <label>NARRATIVE / INCIDENT SUMMARY</label>
                <textarea id="f-arrest-narrative" style="width:100%; height:120px;" placeholder="Describe the arrest circumstances..."></textarea>
            </div>
            <button class="action-btn" style="width:100%;" onclick="submitForm('ARREST REPORT', 'arrest')">FILE REPORT</button>
        `;
    } else if (type === 'traffic') {
        html = `
            <div class="table-header" style="margin-bottom:15px; background:#f39c12;">TRAFFIC CITATION - FORM 10-11</div>
            <div class="form-group">
                <label>OPERATOR NAME</label>
                <input type="text" id="f-traffic-name" placeholder="Full Name">
            </div>
            <div class="form-group">
                <label>VEHICLE PLATE</label>
                <input type="text" id="f-traffic-plate" placeholder="ABC 123">
            </div>
            <div class="form-group">
                <label>VIOLATIONS</label>
                <textarea id="f-traffic-violations" style="width:100%; height:80px;" placeholder="Speeding, Illegal U-Turn, etc..."></textarea>
            </div>
            <div class="form-group">
                <label>FINE AMOUNT ($)</label>
                <input type="text" id="f-traffic-fine" placeholder="500">
            </div>
            <button class="action-btn" style="width:100%;" onclick="submitForm('TRAFFIC CITATION', 'traffic')">ISSUE CITATION</button>
        `;
    } else if (type === 'incident') {
        html = `
            <div class="table-header" style="margin-bottom:15px; background:#3498db;">GENERAL INCIDENT REPORT</div>
            <div class="form-group">
                <label>REPORT TITLE</label>
                <input type="text" id="f-incident-title" placeholder="B&E AT BENNYS">
            </div>
            <div class="form-group">
                <label>INVOLVED PARTIES</label>
                <input type="text" id="f-incident-parties" placeholder="Witnesses, Victims, etc.">
            </div>
            <div class="form-group">
                <label>FULL NARRATIVE</label>
                <textarea id="f-incident-narrative" style="width:100%; height:180px;" placeholder="Full details of the incident..."></textarea>
            </div>
            <button class="action-btn" style="width:100%;" onclick="submitForm('INCIDENT REPORT', 'incident')">SAVE REPORT</button>
        `;
    }

    content.innerHTML = html;
}

function submitForm(typeName, typeId) {
    const myName = document.getElementById('my-name-store').value;
    let formData = {
        type: typeId,
        typeName: typeName,
        officer: myName,
        data: {}
    };

    if (typeId === 'arrest') {
        formData.data.name = document.getElementById('f-arrest-name').value;
        formData.data.charges = document.getElementById('f-arrest-charges').value;
        formData.data.narrative = document.getElementById('f-arrest-narrative').value;
        formData.subject = formData.data.name;
    } else if (typeId === 'traffic') {
        formData.data.name = document.getElementById('f-traffic-name').value;
        formData.data.plate = document.getElementById('f-traffic-plate').value;
        formData.data.violations = document.getElementById('f-traffic-violations').value;
        formData.data.fine = document.getElementById('f-traffic-fine').value;
        formData.subject = `${formData.data.name} (${formData.data.plate})`;
    } else if (typeId === 'incident') {
        formData.data.title = document.getElementById('f-incident-title').value;
        formData.data.parties = document.getElementById('f-incident-parties').value;
        formData.data.narrative = document.getElementById('f-incident-narrative').value;
        formData.subject = formData.data.title;
    }

    syncInteraction({ type: 'submitForm', formData: formData });

    const content = document.getElementById('form-content');
    content.innerHTML = `
        <div style="text-align: center; color: #4caf50; margin-top: 50px;">
            <svg width="64" height="64" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/></svg>
            <h3 style="margin-top: 20px;">${typeName} FILED SUCCESSFULLY</h3>
            <p style="color: #5d7a8c; font-size: 13px;">THE DATA HAS BEEN TRANSMITTED TO CENTRAL DISPATCH</p>
            <button class="action-btn" style="margin-top: 20px;" onclick="internalChangePage('dashboard', true)">RETURN TO DASHBOARD</button>
        </div>
    `;
}

function updateRecordsTable(records) {
    const tbody = document.getElementById('records-table-body');
    if (!tbody) return;
    tbody.innerHTML = '';

    records.forEach(rec => {
        const tr = document.createElement('tr');
        const date = new Date(rec.created_at).toLocaleDateString();
        tr.innerHTML = `
            <td>${date}</td>
            <td style="font-weight: bold; color: #3498db;">${rec.type.toUpperCase()}</td>
            <td>${rec.officer}</td>
            <td style="color: #9abedb;">${rec.subject || 'N/A'}</td>
            <td style="text-align: center;">
                <button class="action-btn" style="padding: 12px 15px; font-size: 15px; font-weight: bold; width: 100%; border-color: #3498db; background: rgba(52, 152, 219, 0.15);" onclick="viewRecord(${rec.id})">VIEW</button>
            </td>
        `;
        tbody.appendChild(tr);
    });
}

function viewRecord(id) {
    syncInteraction({ type: 'getRecordDetails', recordId: id });
}

window.addEventListener('message', (event) => {
    // ... existing message handling ...
    if (event.data.type === 'recordsData') {
        updateRecordsTable(event.data.records);
    }

    if (event.data.type === 'recordDetails') {
        showRecordDetails(event.data.details);
    }
});

function showRecordDetails(rec) {
    const content = document.getElementById('form-content');
    changePage('forms');
    
    let detailHtml = `<div class="table-header" style="margin-bottom:15px; background:#1a2a3a;">RECORD #${rec.id} - ${rec.type.toUpperCase()}</div>`;
    detailHtml += `<div style="font-size: 13px; color: #9abedb; margin-bottom: 15px;">FILED BY ${rec.officer} ON ${new Date(rec.created_at).toLocaleString()}</div>`;
    
    const data = JSON.parse(rec.data);
    for (const [key, val] of Object.entries(data)) {
        detailHtml += `
            <div class="form-group">
                <label>${key.toUpperCase()}</label>
                <div style="background: rgba(0,0,0,0.3); padding: 10px; border: 1px solid #1a2a3a; color: #fff; white-space: pre-wrap;">${val}</div>
            </div>
        `;
    }
    detailHtml += `<button class="action-btn" style="width:100%; margin-top: 10px;" onclick="internalChangePage('records', true)">BACK TO RECORDS</button>`;
    
    content.innerHTML = detailHtml;
}

// Update time
setInterval(() => {
    const now = new Date();
    document.getElementById('time').innerText = now.toLocaleTimeString();
}, 1000);