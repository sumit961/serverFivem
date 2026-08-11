const app = document.getElementById('app');
const dialogue = document.getElementById('dialogue');
const servicePanel = document.getElementById('servicePanel');
const res = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cm-doctor';

const post = (name, data = {}) => fetch(`https://${res}/${name}`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(data),
}).then((response) => response.json());

const esc = (value) => String(value ?? '').replace(/[&<>'"]/g, (character) => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;',
})[character]);

let state = null;

function close() {
  app.hidden = true;
  dialogue.hidden = false;
  servicePanel.hidden = true;
  post('close');
}

function services() {
  return {
    treatment: state?.services?.treatment !== false,
    pharmacy: state?.services?.pharmacy !== false,
    medicineRun: state?.services?.medicineRun === true,
  };
}

function stockAvailable() {
  return state?.stock?.ready === true && Number(state?.stock?.current || 0) > 0;
}

function renderStock() {
  const stock = state?.stock || {};
  const enabled = services();
  document.getElementById('runCard').hidden =
    !enabled.medicineRun || (stock.low !== true && !stock.myRun);
  const percent = Math.max(0, Math.min(100, Number(stock.percent || 0)));
  document.getElementById('stockPercent').textContent = stock.ready ? `${percent}%` : '...';
  document.getElementById('stockUnits').textContent =
    `${Number(stock.current || 0)} / ${Number(stock.maximum || 100)} units`;
  document.getElementById('stockFill').style.width = `${percent}%`;

  const stockMessage = document.getElementById('stockMessage');
  if (!stock.ready) {
    stockMessage.textContent = 'Medicine stock is still loading.';
  } else if (stock.low) {
    stockMessage.textContent =
      `Low stock. An EMS supply run is available at ${Number(stock.triggerPercent || 40)}% or below.`;
  } else {
    stockMessage.textContent =
      `Stock is healthy. The supply task unlocks at ${Number(stock.triggerPercent || 40)}%.`;
  }

  const runButton = document.getElementById('takeMedicineRun');
  runButton.disabled = stock.runAvailable !== true;
  document.getElementById('runInfo').textContent = stock.runAvailable
    ? 'Take the marked supply truck, load medicine at one random Humane Labs point, then return it to Pillbox.'
    : (stock.runReason || `This task unlocks when stock reaches ${Number(stock.triggerPercent || 40)}%.`);

  const disabled = !stockAvailable();
  document.getElementById('buyMedkit').disabled = disabled;
  document.querySelectorAll('[data-medicine-buy]').forEach((button) => {
    button.disabled = disabled;
  });
}

function renderMedicines() {
  const medicines = state?.medicines || [];
  document.getElementById('medicineList').innerHTML = medicines.map((medicine, index) => `
    <div class="medicine-row">
      <div class="medicine-row__text">
        <strong>${esc(medicine.label)}</strong>
        <span>${esc(medicine.description || '')}</span>
        <span class="medicine-row__price">$${esc(medicine.price)} each</span>
      </div>
      <div class="buy-row">
        <input type="number" min="1" value="1" data-medicine-qty="${index}">
        <button class="primary" data-medicine-buy="${index}">Buy</button>
      </div>
    </div>`).join('') || '<p class="muted">No medicine is configured.</p>';
}

function render() {
  if (!state) return;
  const enabled = services();
  document.getElementById('doctorName').textContent = state.doctorName || 'Doctor';
  document.getElementById('dialogueName').textContent = state.doctorName || 'Doctor';
  document.getElementById('dialogueSignature').textContent = `— ${state.doctorName || 'Doctor'}`;
  document.getElementById('dialogueRole').textContent =
    state.services?.medicineRun === true ? 'EMS SUPPLY COORDINATOR' : 'CM MEDICAL';
  document.getElementById('dialogueQuote').textContent =
    state.services?.medicineRun === true
      ? 'Hospital supplies keep every response moving. I can show you the current stock and available delivery work.'
      : 'Welcome. I can arrange treatment or help you purchase medical supplies.';
  document.getElementById('hospitalName').textContent = state.hospital?.label || 'MEDICAL CENTER';
  document.getElementById('availableBeds').textContent = String(state.hospital?.availableBeds ?? 0);
  document.getElementById('waitingPatients').textContent = String(state.hospital?.waiting ?? 0);

  document.getElementById('occupancy').hidden = !enabled.treatment;
  document.getElementById('treatmentCard').hidden = !enabled.treatment;
  document.getElementById('medkitCard').hidden = !enabled.pharmacy;
  document.getElementById('medicineCard').hidden = !enabled.pharmacy;
  document.getElementById('runCard').hidden =
    !enabled.medicineRun || (state?.stock?.low !== true && !state?.stock?.myRun);
  document.getElementById('stockCard').hidden = !(enabled.pharmacy || enabled.medicineRun);

  const treatment = state.treatment || {};
  document.getElementById('treatmentLabel').textContent = treatment.label || 'Get treated';
  const seconds = Math.round((treatment.durationMs || 0) / 1000);
  document.getElementById('treatmentInfo').textContent =
    `Reception assigns a free bed and heals you over ${seconds}s. $${state.hospital?.treatmentPrice ?? treatment.price ?? 0}.`;

  const medkit = state.medkit || {};
  document.getElementById('medkitInfo').textContent =
    `${medkit.description || ''} $${medkit.price || 0} each.`;

  renderMedicines();
  renderStock();
}

document.getElementById('close').onclick = close;
document.getElementById('leaveDialogue').onclick = close;
document.getElementById('continueDialogue').onclick = () => {
  dialogue.hidden = true;
  servicePanel.hidden = false;
};

document.getElementById('getTreated').onclick = async () => {
  const button = document.getElementById('getTreated');
  button.disabled = true;
  await post('getTreated');
  button.disabled = false;
};

async function purchase(item, quantity) {
  const result = await post('buyItem', { item, quantity });
  if (result?.stock) {
    state.stock = result.stock;
    renderStock();
  }
}

document.getElementById('buyMedkit').onclick = async () => {
  const quantity = Number(document.getElementById('medkitQty').value || 1);
  await purchase(state.medkit.item, quantity);
};

document.getElementById('medicineList').addEventListener('click', async (event) => {
  const button = event.target.closest('[data-medicine-buy]');
  if (!button || button.disabled) return;
  const index = Number(button.dataset.medicineBuy);
  const medicine = state.medicines[index];
  const qtyInput = document.querySelector(`[data-medicine-qty="${index}"]`);
  const quantity = Number(qtyInput?.value || 1);
  button.disabled = true;
  await purchase(medicine.item, quantity);
  button.disabled = !stockAvailable();
});

document.getElementById('takeMedicineRun').onclick = async () => {
  const button = document.getElementById('takeMedicineRun');
  button.disabled = true;
  const result = await post('takeMedicineRun');
  if (result?.stock) {
    state.stock = result.stock;
    renderStock();
  }
};

window.addEventListener('message', (event) => {
  if (event.data.action === 'open') {
    state = event.data.data;
    app.hidden = false;
    dialogue.hidden = false;
    servicePanel.hidden = true;
    render();
  } else if (event.data.action === 'stock' && state) {
    state.stock = event.data.stock;
    renderStock();
  } else if (event.data.action === 'close') {
    app.hidden = true;
  }
});

window.addEventListener('keydown', (event) => {
  if (event.key === 'Escape' && !app.hidden) close();
});
