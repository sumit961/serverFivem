(function () {
  'use strict';

  var root = document.getElementById('bank-root');
  var interaction = document.getElementById('interaction');

  function el(id) {
    return document.getElementById(id);
  }

  function resourceName() {
    return typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cm-bank';
  }

  function post(endpoint, payload) {
    payload = payload || {};
    return fetch('https://' + resourceName() + '/' + endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(payload)
    }).then(function (response) {
      return response.text().then(function (text) {
        if (!text) return { ok: response.ok };
        try { return JSON.parse(text); } catch (_) { return { ok: response.ok }; }
      });
    }).catch(function () {
      return null;
    });
  }

  function formatMoney(value) {
    return Math.max(0, Math.floor(Number(value) || 0)).toLocaleString('en-US');
  }

  function formatTime(date) {
    var h = date.getHours(), m = date.getMinutes();
    return (h < 10 ? '0' : '') + h + ':' + (m < 10 ? '0' : '') + m;
  }

  function formatServerTime(value) {
    if (!value) return '';
    var d = new Date(String(value).replace(' ', 'T'));
    if (isNaN(d.getTime())) return '';
    return formatTime(d);
  }

  var TABS = {
    deposit: { source: 'cash', description: 'Move cash into your bank account.', button: 'Deposit', needsTarget: false, balanceLabel: 'CASH ON HAND' },
    withdraw: { source: 'bank', description: 'Move money from your bank account into cash.', button: 'Withdraw', needsTarget: false, balanceLabel: 'BANK BALANCE' },
    transfer: { source: 'bank', description: 'Send money from your bank account to another player.', button: 'Send', needsTarget: true, balanceLabel: 'BANK BALANCE' }
  };
  var TAB_LIST = ['deposit', 'withdraw', 'transfer', 'payees', 'own'];

  var REQUEST_STATUS_LABEL = {
    pending: 'PENDING', accepted: 'COMPLETED', declined: 'DECLINED',
    cancelled: 'CANCELLED', expired: 'EXPIRED', recovery_required: 'PENDING'
  };

  var KIND_META = {
    deposit: { kind: 'DEPOSIT', tag: '↓', kindClass: 'kind-deposit', sign: 'positive' },
    withdraw: { kind: 'WITHDRAW', tag: '↑', kindClass: 'kind-withdraw', sign: 'negative' },
    transfer_out: { kind: 'TRANSFER OUT', tag: '→', kindClass: 'kind-transfer', sign: 'negative' },
    transfer_in: { kind: 'TRANSFER IN', tag: '←', kindClass: 'kind-received', sign: 'positive' },
    atm_earnings: { kind: 'ATM EARNINGS', tag: '↓', kindClass: 'kind-received', sign: 'positive' },
    atm_sale: { kind: 'ATM SOLD', tag: '↓', kindClass: 'kind-received', sign: 'positive' },
    atm_restock: { kind: 'ATM RESTOCK', tag: '↑', kindClass: 'kind-withdraw', sign: 'negative' }
  };

  var ACTIVITY_LIMIT = 4;
  var AMOUNT_PREFIX = { positive: '+$', negative: '-$', neutral: '$' };

  var STATEMENT_KIND_META = {
    deposit: { label: 'DEPOSIT', sign: 'positive' },
    withdraw: { label: 'WITHDRAWAL', sign: 'negative' },
    transfer_out: { label: 'TRANSFER SENT', sign: 'negative' },
    transfer_in: { label: 'TRANSFER RECEIVED', sign: 'positive' },
    atm_earnings: { label: 'ATM EARNINGS', sign: 'positive' },
    atm_purchase: { label: 'ATM PURCHASE', sign: 'negative' },
    atm_sale: { label: 'ATM SALE', sign: 'positive' },
    atm_restock: { label: 'ATM RESTOCK', sign: 'negative' }
  };

  var ATM_BUSINESS_KIND_META = {
    withdrawal: { label: 'Withdrawal', sign: 'positive' },
    deposit: { label: 'Deposit', sign: 'negative' },
    restock: { label: 'Owner Restock', sign: 'positive' },
    earnings_withdrawal: { label: 'Earnings Withdrawal', sign: 'negative' },
    purchase: { label: 'ATM Purchased', sign: 'neutral' },
    sale: { label: 'ATM Sold', sign: 'neutral' }
  };

  var RESERVE_STATUS_LABEL = {
    operational: 'OPERATIONAL', low: 'LOW CASH', critical: 'CRITICAL CASH',
    out_of_cash: 'OUT OF CASH', disabled: 'DISABLED', pending_verification: 'PENDING VERIFICATION'
  };

  var context = {
    cash: 0, bank: 0, limits: {}, transferLimits: {}, transferSecurity: { largeTransferWarning: 0 },
    today: { moneyIn: 0, moneyOut: 0, feesPaid: 0 },
    thisMonth: { moneyIn: 0, moneyOut: 0, feesPaid: 0 },
    monthlyTransfers: { sentCount: 0, receivedCount: 0, moneySent: 0, moneyReceived: 0 }
  };
  var atmInfo = {
    key: null, id: null, owned: false, isOwner: false, ownerName: null, contact: null, feePercent: 0,
    disabled: false, forSale: true, pendingEarnings: 0,
    cashReserve: 0, cashCapacity: 0, reserveStatus: 'operational', reserveUnlimited: true, ownerReserveContribution: 0
  };
  var ownership = {
    enabled: true, purchasePrice: 0, unownedFeePercent: 2, feeChoices: [1, 2, 3, 4], governmentSellPercent: 80,
    ownedAtmId: null, defaultCashCapacity: 100000, purchaseStartingReserve: 25000
  };
  var panelSource = 'atm';
  var currentTab = 'deposit';
  var submitting = false;
  var atmBusy = false;
  var payeeActionPending = false;
  var toastTimer = null;
  var activity = [];
  var activityFilter = 'all';
  var balanceShown = 0;
  var balanceTween = null;
  var pendingConfirmAction = 'transfer';
  var pendingTransferTargetId = null;

  var recipientLookup = { charId: null, ok: false, name: null, message: '' };
  var pendingLookupTargetId = null;
  var pendingLookupCallback = null;

  var statementsState = { page: 1, totalPages: 1, totalCount: 0, filter: 'all', dateRange: 'all', search: '', rows: [] };
  var statementsSearchTimer = null;

  var businessState = { range: 'today', page: 1, totalPages: 1, totalCount: 0, rows: [] };

  var payees = [];
  var recentPayees = [];
  var payeeLimits = { maxPayees: 30, maxFavourites: 6, nicknameMaxLength: 40 };

  // v1.8.0: session-only quick-amount memory. Never persisted, never
  // restored between character changes (a resource restart resets these
  // along with the rest of the page), and never used to auto-submit.
  var lastDepositAmount = 0;
  var lastWithdrawAmount = 0;

  var pendingLargeTransferAmount = 0;
  var pendingLargeTransferTargetId = 0;
  var lastReceiptTransferTargetId = null;

  function showToast(message, type) {
    type = type || 'success';
    el('toastMessage').textContent = String(message || '');
    el('toast').classList.toggle('error', type === 'error');
    el('toast').classList.remove('hidden');
    if (toastTimer) clearTimeout(toastTimer);
    toastTimer = setTimeout(function () {
      el('toast').classList.add('hidden');
    }, 4200);
  }

  function availableBalance() {
    var tab = TABS[currentTab];
    if (!tab) return 0;
    return Number(context[tab.source]) || 0;
  }

  function animateBalance(target) {
    var from = balanceShown, t0 = Date.now(), dur = 500;
    clearInterval(balanceTween);
    balanceTween = setInterval(function () {
      var p = Math.min(1, (Date.now() - t0) / dur);
      var k = 1 - Math.pow(1 - p, 3);
      balanceShown = from + (target - from) * k;
      el('balanceHero').textContent = '$' + formatMoney(balanceShown);
      if (p >= 1) {
        clearInterval(balanceTween);
        balanceShown = target;
        el('balanceHero').textContent = '$' + formatMoney(balanceShown);
      }
    }, 30);
  }

  function updateClock() {
    el('headerClock').textContent = formatTime(new Date());
  }

  function activityFromRow(row) {
    var meta = KIND_META[row.kind] || { kind: String(row.kind || '').toUpperCase(), tag: '?', kindClass: 'kind-transfer', sign: 'neutral' };
    var arrow = row.kind === 'transfer_out' ? '→ ' : row.kind === 'transfer_in' ? '← ' : '';
    var counterparty = row.counterpartyName ? (arrow + row.counterpartyName) : '';
    if (row.status === 'pending' && row.kind === 'transfer_out') counterparty += (counterparty ? ' ' : '') + '(pending delivery)';
    return {
      kind: meta.kind, tag: meta.tag, kindClass: meta.kindClass, sign: meta.sign,
      amountText: AMOUNT_PREFIX[meta.sign] + formatMoney(row.amount),
      counterparty: counterparty,
      reference: row.transactionId ? ('Ref ' + row.transactionId) : '',
      time: formatServerTime(row.time), fresh: false
    };
  }

  function formatFullDate(value) {
    if (!value) return '';
    var d = new Date(String(value).replace(' ', 'T'));
    if (isNaN(d.getTime())) return '';
    var months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return d.getDate() + ' ' + months[d.getMonth()] + ' ' + d.getFullYear() + ' • ' + formatTime(d);
  }

  function renderToday() {
    var today = context.today || { moneyIn: 0, moneyOut: 0, feesPaid: 0 };
    el('todayIn').textContent = '+$' + formatMoney(today.moneyIn);
    el('todayOut').textContent = '-$' + formatMoney(today.moneyOut);
    el('todayFees').textContent = '$' + formatMoney(today.feesPaid);
  }

  function renderFinancialSummary() {
    var month = context.thisMonth || { moneyIn: 0, moneyOut: 0, feesPaid: 0 };
    el('monthIn').textContent = '+$' + formatMoney(month.moneyIn);
    el('monthOut').textContent = '-$' + formatMoney(month.moneyOut);
    el('monthFees').textContent = '$' + formatMoney(month.feesPaid);

    var flow = month.moneyIn - month.moneyOut;
    var flowEl = el('cashFlowValue');
    flowEl.textContent = (flow >= 0 ? '+$' : '-$') + formatMoney(Math.abs(flow));
    flowEl.className = 'today-value ' + (flow >= 0 ? 'positive' : 'negative');

    var t = context.monthlyTransfers || { sentCount: 0, receivedCount: 0, moneySent: 0, moneyReceived: 0 };
    el('transfersSentCount').textContent = String(t.sentCount);
    el('transfersReceivedCount').textContent = String(t.receivedCount);
    el('transfersMoneySent').textContent = '$' + formatMoney(t.moneySent);
    el('transfersMoneyReceived').textContent = '$' + formatMoney(t.moneyReceived);
  }

  function selectPayeeForTransfer(payee) {
    selectTab('transfer');
    el('targetInput').value = String(payee.recipientCharacterId);
    recipientLookup = { charId: null, ok: false, name: null, message: '' };
    render();
    el('amountInput').focus();
  }

  function renderQuickTransferChips() {
    var row = el('quickTransferRow');
    var favourites = payees.filter(function (p) { return p.isFavourite; });
    if (currentTab !== 'transfer' || favourites.length === 0) {
      row.hidden = true;
      return;
    }
    row.hidden = false;
    var chips = el('quickTransferChips');
    chips.querySelectorAll('.payee-chip').forEach(function (c) { c.remove(); });
    favourites.forEach(function (payee) {
      var chip = document.createElement('button');
      chip.type = 'button';
      chip.className = 'payee-chip';

      var name = document.createElement('span');
      name.className = 'payee-chip-name';
      name.textContent = '★ ' + payee.nickname;
      chip.appendChild(name);

      var id = document.createElement('span');
      id.className = 'payee-chip-id';
      id.textContent = 'ID ' + payee.recipientCharacterId;
      chip.appendChild(id);

      chip.addEventListener('click', function () { selectPayeeForTransfer(payee); });
      chips.appendChild(chip);
    });
  }

  // v1.8.0: up to 5 most-recently-transferred-to Character IDs (server-
  // computed from statement history, no new table). Selecting one only
  // pre-fills the Character ID field — it never submits a transfer.
  function renderRecentPayeesChips() {
    var row = el('recentPayeesRow');
    if (currentTab !== 'transfer' || recentPayees.length === 0) {
      row.hidden = true;
      return;
    }
    row.hidden = false;
    var chips = el('recentPayeesChips');
    chips.querySelectorAll('.payee-chip').forEach(function (c) { c.remove(); });
    recentPayees.forEach(function (entry) {
      var chip = document.createElement('button');
      chip.type = 'button';
      chip.className = 'payee-chip';

      var name = document.createElement('span');
      name.className = 'payee-chip-name';
      name.textContent = 'ID ' + entry.characterId;
      chip.appendChild(name);

      var last = document.createElement('span');
      last.className = 'payee-chip-id';
      last.textContent = 'Last $' + formatMoney(entry.lastAmount);
      chip.appendChild(last);

      chip.addEventListener('click', function () {
        selectPayeeForTransfer({ recipientCharacterId: entry.characterId });
      });
      chips.appendChild(chip);
    });
  }

  // v1.8.0: client-side convenience only — the server always recalculates
  // and enforces the real maximum. Withdraw-at-ATM additionally caps at the
  // ATM's physical reserve, matching what the server will actually allow.
  function maxAmountForCurrentTab() {
    if (currentTab === 'deposit') return Math.floor(context.cash);
    if (currentTab === 'withdraw') {
      var bankMax = Math.floor(context.bank);
      if (panelSource === 'atm' && !atmInfo.reserveUnlimited) {
        return Math.max(0, Math.min(bankMax, Math.floor(atmInfo.cashReserve || 0)));
      }
      return bankMax;
    }
    if (currentTab === 'transfer') return Math.floor(context.bank);
    return 0;
  }

  function renderLastAmountChip() {
    var btn = el('btnLastAmount');
    var lastValue = currentTab === 'deposit' ? lastDepositAmount : currentTab === 'withdraw' ? lastWithdrawAmount : 0;
    if (lastValue > 0) {
      btn.hidden = false;
      btn.textContent = 'Use last amount: $' + formatMoney(lastValue);
    } else {
      btn.hidden = true;
    }
  }

  // v1.8.0: access-context header — makes it immediately clear whether the
  // player is at a fee-free teller or a specific ATM, and (discreetly, only
  // to the owner) whether it's their own machine.
  function renderAccessContext() {
    var yoursBadge = el('accessContextYours');
    if (panelSource === 'teller') {
      el('accessContextTitle').textContent = 'CM BANK';
      el('accessContextSub').textContent = (context.tellerName || 'Bank Teller') + ' — Full Service — No withdrawal fee';
      yoursBadge.hidden = true;
      return;
    }

    var title = atmInfo.id ? ('ATM #' + atmInfo.id) : 'ATM';
    el('accessContextTitle').textContent = title;
    var feeText = atmInfo.owned && atmInfo.isOwner ? 'No fee for you' : (atmInfo.feePercent + '% withdrawal fee');
    var statusText = RESERVE_STATUS_LABEL[atmInfo.reserveStatus] || 'OPERATIONAL';
    el('accessContextSub').textContent = feeText + ' — ' + statusText;
    yoursBadge.hidden = !(atmInfo.owned && atmInfo.isOwner);
  }

  var editingPayeeId = null;

  // v1.8.0: Add/Rename/Favourite/Delete all fire-and-forget through a NUI
  // callback that resolves immediately (the client's cb('ok') runs before
  // the server round-trip finishes) — so `post()`'s own promise can't tell
  // us the operation actually finished. The real answer arrives later as a
  // `payeesResult` message, so double-submit protection has to be a manual
  // flag spanning that whole window, not just the fetch.
  function postPayeeAction(endpoint, payload) {
    if (payeeActionPending) return;
    payeeActionPending = true;
    renderPayees();
    post(endpoint, payload).then(function (response) {
      if (!response) {
        payeeActionPending = false;
        el('btnAddPayee').disabled = false;
        renderPayees();
        showToast('Could not reach the bank server.', 'error');
      }
    });
  }

  function renderPayees() {
    var list = el('payeeList');
    list.querySelectorAll('.payee-row').forEach(function (r) { r.remove(); });
    el('payeeListEmpty').classList.toggle('hidden', payees.length > 0);

    payees.forEach(function (payee) {
      var row = document.createElement('div');
      row.className = 'payee-row';

      if (editingPayeeId === payee.id) {
        var editInput = document.createElement('input');
        editInput.className = 'own-contact-input';
        editInput.type = 'text';
        editInput.maxLength = payeeLimits.nicknameMaxLength;
        editInput.value = payee.nickname;
        editInput.style.flex = '1';
        row.appendChild(editInput);

        var saveBtn = document.createElement('button');
        saveBtn.type = 'button';
        saveBtn.className = 'payee-icon-btn active';
        saveBtn.title = 'Save';
        saveBtn.textContent = '✓';
        saveBtn.disabled = payeeActionPending;
        var commitRename = function () {
          if (payeeActionPending) return;
          var next = editInput.value;
          editingPayeeId = null;
          if (next && next.trim() !== '') postPayeeAction('renamePayee', { payeeId: payee.id, nickname: next });
          else renderPayees();
        };
        saveBtn.addEventListener('click', commitRename);
        editInput.addEventListener('keydown', function (event) {
          if (event.key === 'Enter') commitRename();
          if (event.key === 'Escape') { editingPayeeId = null; renderPayees(); }
        });
        row.appendChild(saveBtn);

        var cancelBtn = document.createElement('button');
        cancelBtn.type = 'button';
        cancelBtn.className = 'payee-icon-btn';
        cancelBtn.title = 'Cancel';
        cancelBtn.textContent = '✕';
        cancelBtn.addEventListener('click', function () { editingPayeeId = null; renderPayees(); });
        row.appendChild(cancelBtn);

        list.appendChild(row);
        editInput.focus();
        return;
      }

      var info = document.createElement('div');
      info.className = 'payee-row-info';
      var name = document.createElement('div');
      name.className = 'payee-row-name';
      name.textContent = (payee.isFavourite ? '★ ' : '') + payee.nickname;
      info.appendChild(name);
      var idLine = document.createElement('div');
      idLine.className = 'payee-row-id';
      idLine.textContent = 'ID ' + payee.recipientCharacterId;
      info.appendChild(idLine);
      row.appendChild(info);

      var actions = document.createElement('div');
      actions.className = 'payee-row-actions';

      var favBtn = document.createElement('button');
      favBtn.type = 'button';
      favBtn.className = 'payee-icon-btn' + (payee.isFavourite ? ' active' : '');
      favBtn.title = payee.isFavourite ? 'Unfavourite' : 'Favourite';
      favBtn.textContent = '★';
      favBtn.disabled = payeeActionPending;
      favBtn.addEventListener('click', function () {
        postPayeeAction('setPayeeFavourite', { payeeId: payee.id, favourite: !payee.isFavourite });
      });
      actions.appendChild(favBtn);

      var renameBtn = document.createElement('button');
      renameBtn.type = 'button';
      renameBtn.className = 'payee-icon-btn';
      renameBtn.title = 'Rename';
      renameBtn.textContent = '✎';
      renameBtn.disabled = payeeActionPending;
      renameBtn.addEventListener('click', function () { if (!payeeActionPending) { editingPayeeId = payee.id; renderPayees(); } });
      actions.appendChild(renameBtn);

      var transferBtn = document.createElement('button');
      transferBtn.type = 'button';
      transferBtn.className = 'payee-icon-btn';
      transferBtn.title = 'Transfer';
      transferBtn.textContent = '→';
      transferBtn.addEventListener('click', function () { selectPayeeForTransfer(payee); });
      actions.appendChild(transferBtn);

      var deleteBtn = document.createElement('button');
      deleteBtn.type = 'button';
      deleteBtn.className = 'payee-icon-btn danger';
      deleteBtn.title = 'Delete';
      deleteBtn.textContent = '✕';
      deleteBtn.disabled = payeeActionPending;
      deleteBtn.addEventListener('click', function () {
        postPayeeAction('deletePayee', { payeeId: payee.id });
      });
      actions.appendChild(deleteBtn);

      row.appendChild(actions);
      list.appendChild(row);
    });

    renderQuickTransferChips();
  }

  function renderActivity() {
    var list = el('activityList');
    var rows = list.querySelectorAll('.activity-row');
    rows.forEach(function (row) { row.remove(); });

    var filtered = activity.filter(function (entry) {
      if (activityFilter === 'in') return entry.sign === 'positive';
      if (activityFilter === 'out') return entry.sign === 'negative';
      return true;
    });

    el('activityEmpty').classList.toggle('hidden', filtered.length > 0);

    filtered.forEach(function (entry) {
      var row = document.createElement('div');
      row.className = 'activity-row' + (entry.fresh ? ' fresh' : '');

      var icon = document.createElement('span');
      icon.className = 'activity-icon ' + entry.kindClass;
      icon.textContent = entry.tag;

      var copy = document.createElement('div');
      copy.className = 'activity-copy';
      var kind = document.createElement('div');
      kind.className = 'activity-kind';
      kind.textContent = entry.kind;
      copy.appendChild(kind);
      if (entry.counterparty) {
        var cp = document.createElement('div');
        cp.className = 'activity-counterparty';
        cp.textContent = entry.counterparty;
        copy.appendChild(cp);
      }
      if (entry.reference) {
        var ref = document.createElement('div');
        ref.className = 'activity-reference';
        ref.textContent = entry.reference;
        ref.title = entry.reference;
        copy.appendChild(ref);
      }

      var amount = document.createElement('span');
      amount.className = 'activity-amount ' + entry.sign;
      amount.textContent = entry.amountText;

      row.appendChild(icon);
      row.appendChild(copy);
      row.appendChild(amount);
      list.appendChild(row);
    });
  }

  function pushActivity(entry) {
    entry.time = formatTime(new Date());
    entry.fresh = true;
    activity.unshift(entry);
    if (activity.length > ACTIVITY_LIMIT) activity.length = ACTIVITY_LIMIT;
    renderActivity();
    setTimeout(function () {
      if (activity[0]) activity[0].fresh = false;
      renderActivity();
    }, 2400);
  }

  function updateAtmStatusBadge() {
    var badge = el('atmStatus');
    if (panelSource === 'teller') {
      badge.hidden = true;
      return;
    }
    if (atmInfo.disabled) {
      badge.hidden = false;
      badge.className = 'atm-status disabled';
      badge.textContent = 'OUT OF SERVICE';
      return;
    }
    var reserveSuffix = '';
    if (!atmInfo.reserveUnlimited && atmInfo.reserveStatus && atmInfo.reserveStatus !== 'operational') {
      reserveSuffix = ' · ' + (RESERVE_STATUS_LABEL[atmInfo.reserveStatus] || atmInfo.reserveStatus);
    }

    if (!atmInfo.owned) {
      if (ownership.unownedFeePercent > 0 || reserveSuffix) {
        badge.hidden = false;
        badge.className = 'atm-status';
        badge.textContent = (ownership.unownedFeePercent > 0 ? (ownership.unownedFeePercent + '% withdrawal fee (unowned)') : 'Unowned') + reserveSuffix;
      } else {
        badge.hidden = true;
      }
      return;
    }
    badge.hidden = false;
    var feeSuffix = atmInfo.feePercent > 0 ? (' · ' + atmInfo.feePercent + '% withdrawal fee') : '';
    if (atmInfo.isOwner) {
      badge.className = 'atm-status owned-by-me';
      badge.textContent = 'You own this ATM' + feeSuffix;
    } else {
      badge.className = 'atm-status owned-by-other';
      badge.textContent = 'Owned by ' + (atmInfo.ownerName || 'someone else') + feeSuffix + reserveSuffix;
    }
  }

  function renderOwnPanel() {
    el('ownUnowned').hidden = true;
    el('ownByOther').hidden = true;
    el('ownByMe').hidden = true;
    el('ownDisabledNotice').hidden = true;

    if (!ownership.enabled) {
      el('ownDisabledNotice').hidden = false;
      return;
    }

    if (!atmInfo.owned) {
      el('ownUnowned').hidden = false;
      el('ownUnownedFee').textContent = String(ownership.unownedFeePercent);
      el('ownPriceValue').textContent = '$' + formatMoney(ownership.purchasePrice);
      el('ownCapacityPreview').textContent = '$' + formatMoney(ownership.defaultCashCapacity);
      el('ownStartingReservePreview').textContent = '$' + formatMoney(ownership.purchaseStartingReserve);

      var notForSale = atmInfo.forSale === false;
      var alreadyOwnsOther = !!ownership.ownedAtmId;
      el('ownNotForSale').hidden = !notForSale;
      el('ownAlreadyOwn').hidden = !alreadyOwnsOther;
      if (alreadyOwnsOther) el('ownAlreadyOwnNumber').textContent = String(ownership.ownedAtmId);
      el('ownPriceValue').parentElement.hidden = notForSale || alreadyOwnsOther;
      el('btnBuyAtm').hidden = notForSale || alreadyOwnsOther;
      el('btnBuyAtm').disabled = atmBusy;
    } else if (atmInfo.isOwner) {
      el('ownByMe').hidden = false;

      var statusEl = el('ownReserveStatus');
      statusEl.className = 'own-status-row status-' + atmInfo.reserveStatus;
      statusEl.textContent = RESERVE_STATUS_LABEL[atmInfo.reserveStatus] || String(atmInfo.reserveStatus).toUpperCase();

      var capacity = Math.max(1, atmInfo.cashCapacity || 1);
      var reservePct = Math.max(0, Math.min(100, Math.round((atmInfo.cashReserve / capacity) * 100)));
      el('ownReservePercent').textContent = reservePct + '%';
      var fill = el('ownReserveFill');
      fill.style.width = reservePct + '%';
      fill.className = 'own-reserve-fill status-' + atmInfo.reserveStatus;
      el('ownReserveValue').textContent = '$' + formatMoney(atmInfo.cashReserve);
      el('ownCapacityValue').textContent = '$' + formatMoney(atmInfo.cashCapacity);

      Array.prototype.forEach.call(document.querySelectorAll('.own-fee-choice'), function (button) {
        var fee = Number(button.getAttribute('data-fee'));
        button.classList.toggle('active', fee === atmInfo.feePercent);
        button.disabled = atmBusy;
      });
      var feePct = atmInfo.feePercent || 0;
      el('ownFeeExample').textContent = feePct > 0
        ? ('At ' + feePct + '%: $1,000 withdrawal = $' + formatMoney(Math.floor(1000 * feePct / 100)) + ' fee · $10,000 withdrawal = $' + formatMoney(Math.floor(10000 * feePct / 100)) + ' fee')
        : '';
      el('ownBalanceValue').textContent = '$' + formatMoney(atmInfo.pendingEarnings);
      el('btnWithdrawEarnings').disabled = atmBusy || atmInfo.pendingEarnings <= 0;
      el('btnToggleRestock').disabled = atmBusy;
      el('btnSubmitRestock').disabled = atmBusy;
      el('btnViewBusiness').disabled = atmBusy;
      if (document.activeElement !== el('ownContactInput')) el('ownContactInput').value = atmInfo.contact || '';
      el('btnSaveContact').disabled = atmBusy;
      el('sellPercentLabel').textContent = String(ownership.governmentSellPercent);
      el('btnSellAtm').disabled = atmBusy;
    } else {
      el('ownByOther').hidden = false;
      el('ownOtherName').textContent = atmInfo.ownerName || 'someone else';
      el('ownOtherContactRow').hidden = !atmInfo.contact;
      el('ownOtherContact').textContent = atmInfo.contact || '';
    }
  }

  function render() {
    el('accountBankValue').textContent = formatMoney(context.bank);
    el('cashValue').textContent = formatMoney(context.cash);

    el('atmNumber').hidden = !atmInfo.id;
    if (atmInfo.id) el('atmNumberValue').textContent = String(atmInfo.id);

    renderAccessContext();
    updateAtmStatusBadge();
    el('atmDisabledBanner').hidden = !atmInfo.disabled;

    var isOwnTab = currentTab === 'own';
    var isPayeesTab = currentTab === 'payees';
    el('transactionForm').hidden = atmInfo.disabled || isOwnTab || isPayeesTab;
    el('ownPanel').hidden = atmInfo.disabled || !isOwnTab;
    el('payeesPanel').hidden = atmInfo.disabled || !isPayeesTab;

    if (isOwnTab || isPayeesTab) {
      el('balanceLabel').textContent = 'BANK BALANCE';
      animateBalance(context.bank);
    } else {
      var heroTab = TABS[currentTab];
      if (heroTab) {
        el('balanceLabel').textContent = heroTab.balanceLabel;
        animateBalance(availableBalance());
      }
    }

    if (atmInfo.disabled) return;

    if (isOwnTab) {
      el('actionLabel').textContent = 'OWNERSHIP';
      el('tabDescription').textContent = 'Buy this ATM or manage its withdrawal fee.';
      renderOwnPanel();
      return;
    }

    if (isPayeesTab) {
      el('actionLabel').textContent = 'SAVED PAYEES';
      el('tabDescription').textContent = 'Save Character IDs with a nickname for faster transfers.';
      return;
    }

    var tab = TABS[currentTab];
    if (!tab) return;
    el('actionLabel').textContent = tab.button.toUpperCase();
    el('tabDescription').textContent = tab.description;
    el('submitButtonText').textContent = submitting ? 'Processing' : tab.button;
    el('targetGroup').hidden = !tab.needsTarget;
    el('noteGroup').hidden = currentTab !== 'transfer';
    if (currentTab === 'transfer') {
      renderQuickTransferChips();
      renderRecentPayeesChips();
    } else {
      el('quickTransferRow').hidden = true;
      el('recentPayeesRow').hidden = true;
    }
    renderLastAmountChip();

    var amount = Number(el('amountInput').value) || 0;
    var fmtEl = el('amountFormatted');
    if (amount > 0) {
      fmtEl.hidden = false;
      fmtEl.textContent = '$' + formatMoney(amount);
    } else {
      fmtEl.hidden = true;
    }
    if (amount > 0) {
      var after = tab.source === 'cash' ? context.bank + amount : context.bank - amount;
      el('afterLabel').textContent = 'Balance after';
      el('availableValue').textContent = '$' + formatMoney(Math.max(0, after));
    } else {
      el('afterLabel').textContent = 'Available';
      el('availableValue').textContent = '$' + formatMoney(availableBalance());
    }

    var status = el('statusLine');
    if (currentTab === 'withdraw' && panelSource !== 'teller' && amount > 0) {
      var withdrawFeePercent = 0;
      if (!atmInfo.owned) withdrawFeePercent = Number(ownership.unownedFeePercent) || 0;
      else if (!atmInfo.isOwner) withdrawFeePercent = Number(atmInfo.feePercent) || 0;
      var feeAmount = Math.floor(amount * withdrawFeePercent / 100);
      var receiveAmount = Math.max(0, amount - feeAmount);
      var pieces = [];
      pieces.push(withdrawFeePercent > 0
        ? ('Withdrawal fee ' + withdrawFeePercent + '% · You receive $' + formatMoney(receiveAmount))
        : 'No withdrawal fee');
      if (!atmInfo.reserveUnlimited && amount > (atmInfo.cashReserve || 0)) {
        pieces.push('This ATM only has $' + formatMoney(atmInfo.cashReserve || 0) + ' available.');
      }
      status.textContent = pieces.join(' — ');
    } else {
      status.textContent = '';
    }

    var insufficient = amount <= 0 || amount > availableBalance();
    var missingTarget = tab.needsTarget && !Number(el('targetInput').value);
    el('btnSubmit').disabled = submitting || insufficient || missingTarget;
  }

  function selectTab(tab) {
    if (tab === 'own' && panelSource === 'teller') return;
    if (tab === 'payees' && panelSource === 'atm') return;
    if (TAB_LIST.indexOf(tab) === -1 || tab === currentTab) return;
    currentTab = tab;
    Array.prototype.forEach.call(document.querySelectorAll('.tab'), function (button) {
      button.classList.toggle('active', button.getAttribute('data-tab') === tab);
    });
    if (tab === 'payees') renderPayees();
    render();
  }

  function setRootVisible(visible) {
    if (visible) {
      root.classList.remove('hidden');
      root.setAttribute('aria-hidden', 'false');
    } else {
      root.classList.add('hidden');
      root.setAttribute('aria-hidden', 'true');
    }
  }

  function openPanel(ctx) {
    ctx = ctx || {};
    context.cash = Number(ctx.cash) || 0;
    context.bank = Number(ctx.bank) || 0;
    context.limits = ctx.limits || {};
    context.transferLimits = ctx.transferLimits || {};
    context.transferSecurity = ctx.transferSecurity || { largeTransferWarning: 0 };
    context.today = ctx.today || { moneyIn: 0, moneyOut: 0, feesPaid: 0 };
    context.thisMonth = ctx.thisMonth || { moneyIn: 0, moneyOut: 0, feesPaid: 0 };
    context.monthlyTransfers = ctx.monthlyTransfers || { sentCount: 0, receivedCount: 0, moneySent: 0, moneyReceived: 0 };
    context.tellerName = ctx.tellerName || null;
    submitting = false;
    atmBusy = false;
    payeeActionPending = false;
    el('btnAddPayee').disabled = false;
    activityFilter = 'all';
    activity = Array.isArray(ctx.transactions) ? ctx.transactions.map(activityFromRow) : [];

    payees = Array.isArray(ctx.payees) ? ctx.payees : [];
    recentPayees = Array.isArray(ctx.recentPayees) ? ctx.recentPayees : [];
    payeeLimits = ctx.payeeLimits || { maxPayees: 30, maxFavourites: 6, nicknameMaxLength: 40 };
    editingPayeeId = null;
    el('payeeCharIdInput').value = '';
    el('payeeNicknameInput').value = '';

    pendingConfirmAction = null;
    pendingTransferTargetId = null;
    recipientLookup = { charId: null, ok: false, name: null, message: '' };
    pendingLookupTargetId = null;
    pendingLookupCallback = null;
    pendingLargeTransferAmount = 0;
    pendingLargeTransferTargetId = 0;
    lastReceiptTransferTargetId = null;
    el('largeTransferModal').classList.add('hidden');
    el('receiptModal').classList.add('hidden');
    el('transactionDetailModal').classList.add('hidden');
    el('financialBody').hidden = true;
    el('btnToggleFinancial').textContent = 'Financial Summary ▾';

    statementsState = { page: 1, totalPages: 1, totalCount: 0, filter: 'all', dateRange: 'all', search: '', rows: [] };
    el('statementsModal').classList.add('hidden');
    el('statementsSearch').value = '';
    Array.prototype.forEach.call(document.querySelectorAll('#statementsFilters .filter-btn'), function (b) {
      b.classList.toggle('active', b.getAttribute('data-filter') === 'all');
    });
    Array.prototype.forEach.call(document.querySelectorAll('#statementsDateFilters .filter-btn'), function (b) {
      b.classList.toggle('active', b.getAttribute('data-date-range') === 'all');
    });

    businessState = { range: 'today', page: 1, totalPages: 1, totalCount: 0, rows: [] };
    el('atmBusinessModal').classList.add('hidden');
    el('restockRow').hidden = true;
    el('restockInput').value = '';
    Array.prototype.forEach.call(document.querySelectorAll('#businessRangeFilters .filter-btn'), function (b) {
      b.classList.toggle('active', b.getAttribute('data-range') === 'today');
    });

    panelSource = ctx.source === 'teller' ? 'teller' : 'atm';
    var ownTabButton = document.querySelector('.tab[data-tab="own"]');
    if (ownTabButton) ownTabButton.hidden = panelSource === 'teller';
    var payeesTabButton = document.querySelector('.tab[data-tab="payees"]');
    if (payeesTabButton) payeesTabButton.hidden = panelSource === 'atm';

    var a = ctx.atm || {};
    atmInfo = {
      key: a.key || null,
      id: a.id || null,
      owned: a.owned === true,
      isOwner: a.isOwner === true,
      ownerName: a.ownerName || null,
      contact: a.contact || null,
      feePercent: Number(a.feePercent) || 0,
      disabled: a.disabled === true,
      forSale: a.forSale !== false,
      pendingEarnings: Number(a.pendingEarnings) || 0,
      cashReserve: Number(a.cashReserve) || 0,
      cashCapacity: Number(a.cashCapacity) || 0,
      reserveStatus: a.reserveStatus || 'operational',
      reserveUnlimited: a.reserveUnlimited !== false,
      ownerReserveContribution: Number(a.ownerReserveContribution) || 0
    };
    var o = ctx.ownership || {};
    ownership = {
      enabled: o.enabled !== false,
      purchasePrice: Number(o.purchasePrice) || 0,
      unownedFeePercent: Number(o.unownedFeePercent) || 0,
      feeChoices: Array.isArray(o.feeChoices) ? o.feeChoices : [1, 2, 3, 4],
      governmentSellPercent: Number(o.governmentSellPercent) || 80,
      ownedAtmId: o.ownedAtmId || null,
      defaultCashCapacity: Number(o.defaultCashCapacity) || 100000,
      purchaseStartingReserve: Number(o.purchaseStartingReserve) || 25000
    };

    el('atm').classList.remove('processing');
    el('toast').classList.add('hidden');
    el('confirmModal').classList.add('hidden');
    el('amountInput').value = '';
    el('targetInput').value = '';
    el('noteInput').value = '';
    Array.prototype.forEach.call(document.querySelectorAll('.filter-btn'), function (b) {
      if (b.closest('#statementsFilters') || b.closest('#businessRangeFilters') || b.closest('#statementsDateFilters')) return;
      b.classList.toggle('active', b.getAttribute('data-filter') === 'all');
    });
    selectTab('deposit');
    renderActivity();
    renderToday();
    renderFinancialSummary();
    balanceShown = availableBalance();
    render();

    interaction.classList.add('hidden');
    interaction.setAttribute('aria-hidden', 'true');
    setRootVisible(true);
  }

  function closePanel(sendClose) {
    setRootVisible(false);
    submitting = false;
    atmBusy = false;
    payeeActionPending = false;
    el('btnAddPayee').disabled = false;
    el('confirmModal').classList.add('hidden');
    el('statementsModal').classList.add('hidden');
    el('atmBusinessModal').classList.add('hidden');
    el('largeTransferModal').classList.add('hidden');
    el('receiptModal').classList.add('hidden');
    el('transactionDetailModal').classList.add('hidden');
    el('restockRow').hidden = true;
    el('restockInput').value = '';
    editingPayeeId = null;
    pendingConfirmAction = null;
    pendingTransferTargetId = null;
    pendingLookupCallback = null;
    pendingLookupTargetId = null;
    pendingLargeTransferAmount = 0;
    pendingLargeTransferTargetId = 0;
    if (sendClose) post('close');
  }

  function updateInteraction(data) {
    if (!data.visible) {
      interaction.classList.add('hidden');
      interaction.setAttribute('aria-hidden', 'true');
      return;
    }
    el('interactionKey').textContent = String(data.key || 'E');
    el('interactionText').textContent = [data.name, data.role].filter(Boolean).join(' · ');
    interaction.classList.remove('hidden');
    interaction.setAttribute('aria-hidden', 'false');
  }

  document.querySelectorAll('.tab').forEach(function (button) {
    button.addEventListener('click', function () {
      selectTab(button.getAttribute('data-tab'));
    });
  });

  document.querySelectorAll('#activityFilters .filter-btn').forEach(function (button) {
    button.addEventListener('click', function () {
      activityFilter = button.getAttribute('data-filter');
      Array.prototype.forEach.call(document.querySelectorAll('#activityFilters .filter-btn'), function (b) {
        b.classList.toggle('active', b === button);
      });
      renderActivity();
    });
  });

  document.querySelectorAll('#quickAmounts .quick-btn').forEach(function (button) {
    button.addEventListener('click', function () {
      var maxAllowed = maxAmountForCurrentTab();
      var next;
      if (button.hasAttribute('data-max')) {
        next = maxAllowed;
      } else {
        var add = Number(button.getAttribute('data-add')) || 0;
        var current = Math.floor(Number(el('amountInput').value) || 0);
        next = Math.min(maxAllowed, current + add);
      }
      el('amountInput').value = next > 0 ? String(next) : '';
      render();
    });
  });

  el('btnLastAmount').addEventListener('click', function () {
    var lastValue = currentTab === 'deposit' ? lastDepositAmount : currentTab === 'withdraw' ? lastWithdrawAmount : 0;
    if (lastValue <= 0) return;
    el('amountInput').value = String(lastValue);
    render();
  });

  el('amountInput').addEventListener('input', render);
  el('targetInput').addEventListener('input', function () {
    recipientLookup = { charId: null, ok: false, name: null, message: '' };
    render();
  });

  function doSubmit() {
    submitting = true;
    el('atm').classList.add('processing');
    render();

    var tab = currentTab;
    var payload = { amount: Math.floor(Number(el('amountInput').value) || 0) };
    if (TABS[tab].needsTarget) {
      payload.targetCharId = Math.floor(Number(el('targetInput').value) || 0);
      payload.note = el('noteInput').value || '';
    }

    post(tab, payload).then(function (response) {
      if (!response) {
        submitting = false;
        el('atm').classList.remove('processing');
        render();
        showToast('Could not reach the bank server.', 'error');
      }
    });
  }

  function setConfirmFeeRow(fee, percent) {
    el('confirmFeeRow').hidden = false;
    el('confirmFeeLabel').textContent = (percent > 0) ? ('Fee (' + percent + '%)') : 'Fee';
    el('confirmFeeValue').textContent = '$' + formatMoney(fee);
  }

  function setConfirmNoteRow(note) {
    note = String(note || '').trim();
    var row = el('confirmNoteRow');
    if (note) {
      row.hidden = false;
      el('confirmNoteValue').textContent = note;
    } else {
      row.hidden = true;
    }
  }

  // Generic itemized breakdown for confirm/receipt/detail modals — used
  // where the fixed fee/note/after rows aren't enough (ATM buy/sell previews,
  // receipts, transaction details). Always built with textContent, never
  // innerHTML, so nothing rendered here can ever inject markup.
  // v1.8.0: clipboard support is inconsistent across FiveM's embedded CEF —
  // try it, but the reference text is always rendered with `user-select:text`
  // (see .ref-selectable) so manual copy always works even if this silently
  // does nothing.
  function copyText(text, btnEl) {
    function showResult(success) {
      if (!btnEl) return;
      btnEl.classList.toggle('copied', success);
      btnEl.textContent = success ? 'Copied' : 'Copy';
      if (success) {
        setTimeout(function () {
          btnEl.classList.remove('copied');
          btnEl.textContent = 'Copy';
        }, 1500);
      }
    }
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(function () { showResult(true); }).catch(function () { showResult(false); });
        return;
      }
    } catch (_) {}
    showResult(false);
  }

  function buildBreakdownRows(container, rows) {
    container.querySelectorAll('.confirm-after-row').forEach(function (r) { r.remove(); });
    rows.forEach(function (row) {
      var line = document.createElement('div');
      line.className = 'confirm-after-row';
      var label = document.createElement('span');
      label.textContent = row.label;
      line.appendChild(label);

      if (row.copyable) {
        var valueRow = document.createElement('span');
        valueRow.className = 'breakdown-value-row';
        var value = document.createElement('b');
        value.className = 'ref-selectable';
        value.textContent = row.value;
        valueRow.appendChild(value);
        var copyBtn = document.createElement('button');
        copyBtn.type = 'button';
        copyBtn.className = 'copy-btn';
        copyBtn.textContent = 'Copy';
        copyBtn.addEventListener('click', function () { copyText(row.value, copyBtn); });
        valueRow.appendChild(copyBtn);
        line.appendChild(valueRow);
      } else {
        var plainValue = document.createElement('b');
        plainValue.textContent = row.value;
        line.appendChild(plainValue);
      }

      container.appendChild(line);
    });
  }

  function setConfirmBreakdown(rows) {
    buildBreakdownRows(el('confirmBreakdown'), rows || []);
  }

  function atmContextLabel() {
    if (panelSource === 'teller') return 'Bank Teller';
    if (!atmInfo.id) return 'ATM';
    if (atmInfo.isOwner) return 'ATM #' + atmInfo.id + ' (Your ATM)';
    if (atmInfo.owned) return 'ATM #' + atmInfo.id + ' (Owned ATM)';
    return 'ATM #' + atmInfo.id + ' (Public ATM)';
  }

  function openConfirmForDeposit(amount) {
    pendingConfirmAction = 'deposit';
    el('confirmTitle').textContent = 'CONFIRM DEPOSIT';
    el('confirmAcceptLabel').textContent = 'Confirm Deposit';
    el('confirmAmount').textContent = '$' + formatMoney(amount);
    el('confirmTo').textContent = 'Cash available: $' + formatMoney(context.cash);
    setConfirmFeeRow(0, 0);
    setConfirmNoteRow(null);
    setConfirmBreakdown([]);
    el('confirmAfterLabel').textContent = 'Bank after deposit';
    el('confirmAfter').textContent = '$' + formatMoney(context.bank + amount);
    el('confirmModal').classList.remove('hidden');
  }

  function openConfirmForWithdraw(amount) {
    var feePercent = 0;
    if (panelSource !== 'teller') {
      if (!atmInfo.owned) feePercent = Number(ownership.unownedFeePercent) || 0;
      else if (!atmInfo.isOwner) feePercent = Number(atmInfo.feePercent) || 0;
    }
    var fee = Math.floor(amount * feePercent / 100);
    var cashReceived = Math.max(0, amount - fee);
    pendingConfirmAction = 'withdraw';
    el('confirmTitle').textContent = 'CONFIRM WITHDRAWAL';
    el('confirmAcceptLabel').textContent = 'Confirm Withdrawal';
    el('confirmAmount').textContent = '$' + formatMoney(amount);
    var toText = atmContextLabel();
    if (!atmInfo.reserveUnlimited && amount > (atmInfo.cashReserve || 0)) {
      toText += ' — only $' + formatMoney(atmInfo.cashReserve || 0) + ' available';
    }
    el('confirmTo').textContent = toText;
    setConfirmFeeRow(fee, feePercent);
    setConfirmNoteRow(null);
    setConfirmBreakdown([]);
    el('confirmAfterLabel').textContent = 'Cash received';
    el('confirmAfter').textContent = '$' + formatMoney(cashReceived);
    el('confirmModal').classList.remove('hidden');
  }

  function openConfirmForTransfer(amount, targetId, recipientName) {
    var feePercent = Number(context.limits && context.limits.transferFeePercent) || 0;
    var fee = Math.floor(amount * feePercent / 100);
    pendingConfirmAction = 'transfer';
    pendingTransferTargetId = targetId;
    el('confirmTitle').textContent = 'CONFIRM TRANSFER';
    el('confirmAcceptLabel').textContent = 'Confirm Transfer';
    el('confirmAmount').textContent = '$' + formatMoney(amount);
    el('confirmTo').textContent = recipientName + ' (Character ID: ' + targetId + ')';
    setConfirmFeeRow(fee, feePercent);
    setConfirmNoteRow(el('noteInput').value);
    setConfirmBreakdown([]);
    el('confirmAfterLabel').textContent = 'Total debited';
    el('confirmAfter').textContent = '$' + formatMoney(amount);
    el('confirmModal').classList.remove('hidden');
  }

  function requestRecipientLookup(targetId, onDone) {
    pendingLookupTargetId = targetId;
    pendingLookupCallback = onDone;
    post('lookupRecipient', { targetCharId: targetId });
  }

  function proceedToTransferConfirm(amount, targetId) {
    if (recipientLookup.ok && recipientLookup.charId === targetId) {
      openConfirmForTransfer(amount, targetId, recipientLookup.name);
      return;
    }
    requestRecipientLookup(targetId, function (result) {
      if (!result.ok) {
        showToast(result.message || 'Character ID not found.', 'error');
        return;
      }
      openConfirmForTransfer(amount, targetId, result.name);
    });
  }

  el('btnSubmit').addEventListener('click', function () {
    if (submitting || el('btnSubmit').disabled) return;
    var amount = Math.floor(Number(el('amountInput').value) || 0);
    if (amount <= 0) return;

    if (currentTab === 'transfer') {
      var targetId = Math.floor(Number(el('targetInput').value) || 0);
      if (targetId <= 0) return;

      var warnThreshold = Number(context.transferSecurity && context.transferSecurity.largeTransferWarning) || 0;
      if (warnThreshold > 0 && amount >= warnThreshold) {
        pendingLargeTransferAmount = amount;
        pendingLargeTransferTargetId = targetId;
        el('largeTransferAmount').textContent = '$' + formatMoney(amount);
        el('largeTransferTargetId').textContent = String(targetId);
        el('largeTransferModal').classList.remove('hidden');
        return;
      }

      proceedToTransferConfirm(amount, targetId);
      return;
    }

    if (currentTab === 'deposit') return openConfirmForDeposit(amount);
    if (currentTab === 'withdraw') return openConfirmForWithdraw(amount);
  });

  el('btnLargeTransferCancel').addEventListener('click', function () {
    el('largeTransferModal').classList.add('hidden');
  });
  el('btnLargeTransferConfirm').addEventListener('click', function () {
    el('largeTransferModal').classList.add('hidden');
    if (pendingLargeTransferAmount > 0 && pendingLargeTransferTargetId > 0) {
      proceedToTransferConfirm(pendingLargeTransferAmount, pendingLargeTransferTargetId);
    }
  });

  el('btnConfirmCancel').addEventListener('click', function () {
    el('confirmModal').classList.add('hidden');
  });
  el('btnConfirmAccept').addEventListener('click', function () {
    el('confirmModal').classList.add('hidden');
    if (pendingConfirmAction === 'sellAtm') {
      doSellAtm();
    } else if (pendingConfirmAction === 'restockAtm') {
      doRestockAtm();
    } else if (pendingConfirmAction === 'buyAtm') {
      doBuyAtm();
    } else {
      doSubmit();
    }
  });

  function doBuyAtm() {
    atmBusy = true;
    render();
    post('buyAtm', {}).then(function (response) {
      if (!response) {
        atmBusy = false;
        render();
        showToast('Could not reach the bank server.', 'error');
      }
    });
  }

  el('btnBuyAtm').addEventListener('click', function () {
    if (atmBusy || el('btnBuyAtm').disabled) return;
    pendingConfirmAction = 'buyAtm';
    el('confirmTitle').textContent = 'BUY ATM' + (atmInfo.id ? (' #' + atmInfo.id) : '');
    el('confirmAcceptLabel').textContent = 'Buy ATM';
    el('confirmAmount').textContent = '$' + formatMoney(ownership.purchasePrice);
    el('confirmTo').textContent = 'Purchase price';
    setConfirmFeeRow(0, 0);
    el('confirmFeeRow').hidden = true;
    setConfirmNoteRow(null);
    setConfirmBreakdown([
      { label: 'Cash Capacity', value: '$' + formatMoney(ownership.defaultCashCapacity) },
      { label: 'Starting Reserve', value: '$' + formatMoney(ownership.purchaseStartingReserve) },
      { label: 'Withdrawal Fee Options', value: ownership.feeChoices.map(function (f) { return f + '%'; }).join(' • ') }
    ]);
    el('confirmAfterLabel').textContent = 'Bank after purchase';
    el('confirmAfter').textContent = '$' + formatMoney(Math.max(0, context.bank - ownership.purchasePrice));
    el('confirmModal').classList.remove('hidden');
  });

  document.querySelectorAll('.own-fee-choice').forEach(function (button) {
    button.addEventListener('click', function () {
      if (atmBusy || button.disabled) return;
      var feePercent = Number(button.getAttribute('data-fee')) || 0;
      atmBusy = true;
      render();
      post('setAtmFee', { feePercent: feePercent }).then(function (response) {
        if (!response) {
          atmBusy = false;
          render();
          showToast('Could not reach the bank server.', 'error');
        }
      });
    });
  });

  el('btnWithdrawEarnings').addEventListener('click', function () {
    if (atmBusy || el('btnWithdrawEarnings').disabled) return;
    atmBusy = true;
    render();
    post('withdrawAtmEarnings', {}).then(function (response) {
      if (!response) {
        atmBusy = false;
        render();
        showToast('Could not reach the bank server.', 'error');
      }
    });
  });

  el('btnSaveContact').addEventListener('click', function () {
    if (atmBusy || el('btnSaveContact').disabled) return;
    atmBusy = true;
    render();
    post('setAtmContact', { contact: el('ownContactInput').value }).then(function (response) {
      if (!response) {
        atmBusy = false;
        render();
        showToast('Could not reach the bank server.', 'error');
      }
    });
  });

  function doSellAtm() {
    atmBusy = true;
    render();
    post('sellAtm', {}).then(function (response) {
      if (!response) {
        atmBusy = false;
        render();
        showToast('Could not reach the bank server.', 'error');
      }
    });
  }

  el('btnSellAtm').addEventListener('click', function () {
    if (atmBusy || el('btnSellAtm').disabled) return;
    var governmentValue = Math.floor(ownership.purchasePrice * ownership.governmentSellPercent / 100);
    var recoverableContribution = Math.min(atmInfo.ownerReserveContribution || 0, atmInfo.cashReserve || 0);
    var payout = governmentValue + (atmInfo.pendingEarnings || 0) + recoverableContribution;
    pendingConfirmAction = 'sellAtm';
    el('confirmTitle').textContent = 'SELL ATM' + (atmInfo.id ? (' #' + atmInfo.id) : '');
    el('confirmAcceptLabel').textContent = 'Sell to Government';
    el('confirmAmount').textContent = '$' + formatMoney(payout);
    el('confirmTo').textContent = 'Selling this ATM removes your ownership permanently. Pending earnings and recoverable contribution are included in the payout below.';
    setConfirmFeeRow(0, 0);
    el('confirmFeeRow').hidden = true;
    setConfirmNoteRow(null);
    setConfirmBreakdown([
      { label: 'Government Value', value: '$' + formatMoney(governmentValue) },
      { label: 'Pending Earnings', value: '$' + formatMoney(atmInfo.pendingEarnings || 0) },
      { label: 'Recoverable Owner Contribution', value: '$' + formatMoney(recoverableContribution) }
    ]);
    el('confirmAfterLabel').textContent = 'TOTAL PAYOUT';
    el('confirmAfter').textContent = '$' + formatMoney(payout);
    el('confirmModal').classList.remove('hidden');
  });

  el('btnToggleRestock').addEventListener('click', function () {
    if (atmBusy) return;
    var row = el('restockRow');
    row.hidden = !row.hidden;
    if (!row.hidden) el('restockInput').focus();
  });

  el('btnRestockMax').addEventListener('click', function () {
    if (atmBusy) return;
    var capacity = Math.max(0, atmInfo.cashCapacity || 0);
    var remaining = Math.max(0, capacity - (atmInfo.cashReserve || 0));
    var maxAllowed = Math.max(0, Math.min(remaining, Math.floor(context.cash)));
    el('restockInput').value = maxAllowed > 0 ? String(maxAllowed) : '';
  });

  el('btnSubmitRestock').addEventListener('click', function () {
    if (atmBusy || el('btnSubmitRestock').disabled) return;
    var amount = Math.floor(Number(el('restockInput').value) || 0);
    if (amount <= 0) return;
    var capacity = Math.max(0, atmInfo.cashCapacity || 0);
    var remaining = Math.max(0, capacity - (atmInfo.cashReserve || 0));
    pendingConfirmAction = 'restockAtm';
    el('confirmTitle').textContent = 'CONFIRM RESTOCK';
    el('confirmAcceptLabel').textContent = 'Add Cash';
    el('confirmAmount').textContent = '$' + formatMoney(amount);
    el('confirmTo').textContent = 'Your cash: $' + formatMoney(context.cash) +
      (amount > remaining ? ' — this ATM only has space for $' + formatMoney(remaining) + ' more.' : '');
    el('confirmFeeRow').hidden = true;
    setConfirmNoteRow(null);
    setConfirmBreakdown([]);
    el('confirmAfterLabel').textContent = 'ATM reserve after';
    el('confirmAfter').textContent = '$' + formatMoney(Math.min(capacity, (atmInfo.cashReserve || 0) + amount));
    el('confirmModal').classList.remove('hidden');
  });

  function doRestockAtm() {
    var amount = Math.floor(Number(el('restockInput').value) || 0);
    if (amount <= 0) return;
    atmBusy = true;
    render();
    post('restockAtm', { amount: amount }).then(function (response) {
      if (!response) {
        atmBusy = false;
        render();
        showToast('Could not reach the bank server.', 'error');
      }
    });
  }

  function fetchBusinessAnalytics() {
    post('fetchAtmAnalytics', { range: businessState.range });
  }

  function fetchBusinessHistory() {
    post('fetchAtmHistory', { page: businessState.page });
  }

  function renderBusinessRow(row) {
    var meta = ATM_BUSINESS_KIND_META[row.kind] || { label: String(row.kind || '').toUpperCase(), sign: 'neutral' };
    var wrap = document.createElement('div');
    wrap.className = 'business-list-row statement-row';

    var head = document.createElement('div');
    head.className = 'statement-kind';
    head.textContent = meta.label;
    wrap.appendChild(head);

    if (row.actorCharacterId != null) {
      var cp = document.createElement('div');
      cp.className = 'statement-line';
      cp.textContent = 'Character #' + row.actorCharacterId;
      wrap.appendChild(cp);
    }

    var amountLine = document.createElement('div');
    amountLine.className = 'statement-line';
    amountLine.textContent = (meta.sign === 'positive' ? '+$' : meta.sign === 'negative' ? '-$' : '$') + formatMoney(row.amount);
    wrap.appendChild(amountLine);

    if (row.feeAmount > 0) {
      var feeLine = document.createElement('div');
      feeLine.className = 'statement-line';
      feeLine.textContent = 'Fee earned: $' + formatMoney(row.feeAmount);
      wrap.appendChild(feeLine);
    }

    var refLine = document.createElement('div');
    refLine.className = 'statement-reference';
    refLine.textContent = 'TX: ' + (row.transactionId || '—');
    wrap.appendChild(refLine);

    var timeLine = document.createElement('div');
    timeLine.className = 'statement-time';
    timeLine.textContent = formatFullDate(row.time);
    wrap.appendChild(timeLine);

    return wrap;
  }

  function renderBusinessHistory() {
    var list = el('businessList');
    Array.prototype.slice.call(list.querySelectorAll('.business-list-row')).forEach(function (r) { r.remove(); });
    el('businessEmpty').classList.toggle('hidden', businessState.rows.length > 0);
    businessState.rows.forEach(function (row) {
      list.appendChild(renderBusinessRow(row));
    });
    el('businessPageLabel').textContent = 'Page ' + businessState.page + ' of ' + businessState.totalPages + ' (' + businessState.totalCount + ' total)';
    el('businessPrev').disabled = businessState.page <= 1;
    el('businessNext').disabled = businessState.page >= businessState.totalPages;
  }

  function renderBusinessMetrics(m) {
    el('metricTransactions').textContent = String(m.transactions || 0);
    el('metricWithdrawalCount').textContent = String(m.withdrawalCount || 0);
    el('metricDepositCount').textContent = String(m.depositCount || 0);
    el('metricCashWithdrawn').textContent = '$' + formatMoney(m.cashWithdrawn || 0);
    el('metricCashDeposited').textContent = '$' + formatMoney(m.cashDeposited || 0);
    el('metricFeeRevenue').textContent = '$' + formatMoney(m.feeRevenue || 0);
    el('metricAvgWithdrawal').textContent = '$' + formatMoney(m.averageWithdrawal || 0);
  }

  el('btnViewBusiness').addEventListener('click', function () {
    if (atmBusy || el('btnViewBusiness').disabled) return;
    el('businessAtmNumber').textContent = String(atmInfo.id || '');
    businessState.page = 1;
    el('atmBusinessModal').classList.remove('hidden');
    fetchBusinessAnalytics();
    fetchBusinessHistory();
  });

  el('btnCloseBusiness').addEventListener('click', function () {
    el('atmBusinessModal').classList.add('hidden');
  });

  document.querySelectorAll('#businessRangeFilters .filter-btn').forEach(function (button) {
    button.addEventListener('click', function () {
      businessState.range = button.getAttribute('data-range');
      Array.prototype.forEach.call(document.querySelectorAll('#businessRangeFilters .filter-btn'), function (b) {
        b.classList.toggle('active', b === button);
      });
      fetchBusinessAnalytics();
    });
  });

  el('businessPrev').addEventListener('click', function () {
    if (businessState.page <= 1) return;
    businessState.page -= 1;
    fetchBusinessHistory();
  });

  el('businessNext').addEventListener('click', function () {
    if (businessState.page >= businessState.totalPages) return;
    businessState.page += 1;
    fetchBusinessHistory();
  });

  el('btnToggleFinancial').addEventListener('click', function () {
    var body = el('financialBody');
    body.hidden = !body.hidden;
    el('btnToggleFinancial').textContent = 'Financial Summary ' + (body.hidden ? '▾' : '▴');
  });

  el('btnAddPayee').addEventListener('click', function () {
    if (payeeActionPending) return;
    var recipientCharId = Math.floor(Number(el('payeeCharIdInput').value) || 0);
    var nickname = el('payeeNicknameInput').value;
    if (recipientCharId <= 0) { showToast('Enter a valid Character ID.', 'error'); return; }
    if (!nickname || !nickname.trim()) { showToast('Enter a nickname for this payee.', 'error'); return; }
    el('btnAddPayee').disabled = true;
    postPayeeAction('addPayee', { recipientCharId: recipientCharId, nickname: nickname });
  });

  el('btnClose').addEventListener('click', function () {
    closePanel(true);
  });

  function statementAmountText(row, meta) {
    var isDebit = meta.sign === 'negative';
    var total = isDebit ? (row.amount + row.feeAmount) : row.amount;
    return (isDebit ? '-$' : meta.sign === 'positive' ? '+$' : '$') + formatMoney(total);
  }

  function renderStatementRow(row) {
    var meta = STATEMENT_KIND_META[row.kind] || { label: String(row.kind || '').toUpperCase(), sign: 'neutral' };
    var wrap = document.createElement('div');
    wrap.className = 'statement-row';
    wrap.addEventListener('click', function () { openTransactionDetail(row); });

    var headRow = document.createElement('div');
    headRow.className = 'statement-header-row';
    var head = document.createElement('div');
    head.className = 'statement-kind';
    head.textContent = meta.label;
    headRow.appendChild(head);
    var headAmount = document.createElement('div');
    headAmount.className = 'statement-header-amount ' + meta.sign;
    headAmount.textContent = statementAmountText(row, meta);
    headRow.appendChild(headAmount);
    wrap.appendChild(headRow);

    if (row.counterpartyName || row.counterpartyCharacterId != null) {
      var verb = row.kind === 'transfer_out' ? 'To' : row.kind === 'transfer_in' ? 'From' : 'With';
      var cp = document.createElement('div');
      cp.className = 'statement-line';
      cp.textContent = verb + ' Character ID ' + (row.counterpartyCharacterId != null ? row.counterpartyCharacterId : '?') +
        (row.counterpartyName ? (' (' + row.counterpartyName + ')') : '');
      wrap.appendChild(cp);
    }

    if (row.description) {
      var noteLine = document.createElement('div');
      noteLine.className = 'statement-line statement-note';
      noteLine.textContent = row.description;
      wrap.appendChild(noteLine);
    }

    var timeLine = document.createElement('div');
    timeLine.className = 'statement-time';
    var statusSuffix = (row.status && row.status !== 'completed') ? (' • ' + row.status.toUpperCase().replace(/_/g, ' ')) : '';
    timeLine.textContent = formatFullDate(row.time) + statusSuffix;
    wrap.appendChild(timeLine);

    var refLine = document.createElement('div');
    refLine.className = 'statement-reference';
    refLine.textContent = 'TX: ' + (row.transactionId || '—');
    wrap.appendChild(refLine);

    return wrap;
  }

  function openTransactionDetail(row) {
    var meta = STATEMENT_KIND_META[row.kind] || { label: String(row.kind || '').toUpperCase(), sign: 'neutral' };
    var isDebit = meta.sign === 'negative';
    var total = isDebit ? (row.amount + row.feeAmount) : row.amount;

    el('detailTitle').textContent = 'TRANSACTION DETAILS';
    el('detailAmount').textContent = statementAmountText(row, meta);

    var rows = [{ label: 'Type', value: meta.label }];
    if (row.counterpartyCharacterId != null) rows.push({ label: 'Character ID', value: String(row.counterpartyCharacterId) });
    rows.push({ label: 'Amount', value: '$' + formatMoney(row.amount) });
    rows.push({ label: 'Fee', value: '$' + formatMoney(row.feeAmount) });
    rows.push({ label: 'Total', value: '$' + formatMoney(total) });
    if (row.description) rows.push({ label: 'Note', value: row.description });
    rows.push({ label: 'Reference', value: row.transactionId || '—', copyable: true });
    var d = row.time ? new Date(String(row.time).replace(' ', 'T')) : null;
    if (d && !isNaN(d.getTime())) {
      var months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      rows.push({ label: 'Date', value: d.getDate() + ' ' + months[d.getMonth()] + ' ' + d.getFullYear() });
      rows.push({ label: 'Time', value: formatTime(d) });
    }
    if (row.status && row.status !== 'completed') rows.push({ label: 'Status', value: row.status.toUpperCase().replace(/_/g, ' ') });

    buildBreakdownRows(el('detailBreakdown'), rows);
    el('transactionDetailModal').classList.remove('hidden');
  }

  el('btnDetailClose').addEventListener('click', function () {
    el('transactionDetailModal').classList.add('hidden');
  });

  function openReceipt(action, result, noteText) {
    var rows = [];
    var title = '', amountText = '$0';

    if (action === 'deposit') {
      title = 'DEPOSIT COMPLETE';
      amountText = '$' + formatMoney(result.amount || 0);
      rows.push({ label: 'Deposited', value: '$' + formatMoney(result.amount || 0) });
      rows.push({ label: 'Fee', value: '$0' });
      rows.push({ label: 'New Bank Balance', value: '$' + formatMoney(context.bank) });
      lastReceiptTransferTargetId = null;
    } else if (action === 'withdraw') {
      title = 'WITHDRAWAL COMPLETE';
      var fee = Number(result.fee) || 0;
      var received = typeof result.received === 'number' ? result.received : Math.max(0, (result.amount || 0) - fee);
      var feePercent = (result.atm && typeof result.atm.feePercent === 'number')
        ? result.atm.feePercent
        : ((result.amount > 0) ? Math.round(fee / result.amount * 100) : 0);
      amountText = '$' + formatMoney(received);
      rows.push({ label: 'Cash Received', value: '$' + formatMoney(received) });
      rows.push({ label: fee > 0 ? ('ATM Fee — ' + feePercent + '%') : 'ATM Fee', value: '$' + formatMoney(fee) });
      rows.push({ label: 'Total Bank Debit', value: '$' + formatMoney(result.amount || 0) });
      rows.push({ label: 'New Bank Balance', value: '$' + formatMoney(context.bank) });
      lastReceiptTransferTargetId = null;
    } else if (action === 'transfer') {
      title = 'TRANSFER COMPLETE';
      amountText = '$' + formatMoney(result.amount || 0);
      rows.push({ label: 'Character ID', value: String(result.targetCharacterId || '') });
      rows.push({ label: 'Amount', value: '$' + formatMoney(result.amount || 0) });
      rows.push({ label: 'Fee', value: '$' + formatMoney(result.transferFee || 0) });
      rows.push({ label: 'Total Debited', value: '$' + formatMoney(result.amount || 0) });
      if (noteText && noteText.trim()) rows.push({ label: 'Note', value: noteText.trim() });
      lastReceiptTransferTargetId = result.targetCharacterId || null;
    } else {
      return;
    }

    rows.push({ label: 'Reference', value: result.transactionId || '—', copyable: true });

    el('receiptTitle').textContent = title;
    el('receiptAmount').textContent = amountText;
    buildBreakdownRows(el('receiptBreakdown'), rows);
    el('receiptReference').textContent = '';
    el('receiptTime').textContent = formatFullDate(new Date().toISOString().slice(0, 19).replace('T', ' '));
    el('btnReceiptAgain').hidden = action !== 'transfer';
    el('receiptModal').classList.remove('hidden');
  }

  el('btnReceiptDone').addEventListener('click', function () {
    el('receiptModal').classList.add('hidden');
  });
  el('btnReceiptAgain').addEventListener('click', function () {
    el('receiptModal').classList.add('hidden');
    if (lastReceiptTransferTargetId) {
      selectPayeeForTransfer({ recipientCharacterId: lastReceiptTransferTargetId });
    }
  });

  function renderStatements() {
    var list = el('statementsList');
    Array.prototype.slice.call(list.querySelectorAll('.statement-row')).forEach(function (r) { r.remove(); });
    el('statementsEmpty').classList.toggle('hidden', statementsState.rows.length > 0);
    statementsState.rows.forEach(function (row) {
      list.appendChild(renderStatementRow(row));
    });
    el('statementsPageLabel').textContent = 'Page ' + statementsState.page + ' of ' + statementsState.totalPages + ' (' + statementsState.totalCount + ' total)';
    el('statementsPrev').disabled = statementsState.page <= 1;
    el('statementsNext').disabled = statementsState.page >= statementsState.totalPages;
  }

  function fetchStatementsPage() {
    post('fetchStatements', {
      page: statementsState.page, filter: statementsState.filter,
      dateRange: statementsState.dateRange, search: statementsState.search
    });
  }

  function openStatements() {
    el('statementsModal').classList.remove('hidden');
    fetchStatementsPage();
  }

  function closeStatements() {
    el('statementsModal').classList.add('hidden');
  }

  el('btnViewAllStatements').addEventListener('click', function () {
    statementsState = { page: 1, totalPages: 1, totalCount: 0, filter: 'all', dateRange: 'all', search: '', rows: [] };
    el('statementsSearch').value = '';
    Array.prototype.forEach.call(document.querySelectorAll('#statementsFilters .filter-btn'), function (b) {
      b.classList.toggle('active', b.getAttribute('data-filter') === 'all');
    });
    Array.prototype.forEach.call(document.querySelectorAll('#statementsDateFilters .filter-btn'), function (b) {
      b.classList.toggle('active', b.getAttribute('data-date-range') === 'all');
    });
    openStatements();
  });

  el('btnCloseStatements').addEventListener('click', closeStatements);

  document.querySelectorAll('#statementsFilters .filter-btn').forEach(function (button) {
    button.addEventListener('click', function () {
      statementsState.filter = button.getAttribute('data-filter');
      Array.prototype.forEach.call(document.querySelectorAll('#statementsFilters .filter-btn'), function (b) {
        b.classList.toggle('active', b === button);
      });
      statementsState.page = 1;
      fetchStatementsPage();
    });
  });

  document.querySelectorAll('#statementsDateFilters .filter-btn').forEach(function (button) {
    button.addEventListener('click', function () {
      statementsState.dateRange = button.getAttribute('data-date-range');
      Array.prototype.forEach.call(document.querySelectorAll('#statementsDateFilters .filter-btn'), function (b) {
        b.classList.toggle('active', b === button);
      });
      statementsState.page = 1;
      fetchStatementsPage();
    });
  });

  el('statementsSearch').addEventListener('input', function () {
    var value = el('statementsSearch').value;
    clearTimeout(statementsSearchTimer);
    statementsSearchTimer = setTimeout(function () {
      statementsState.search = value;
      statementsState.page = 1;
      fetchStatementsPage();
    }, 350);
  });

  el('statementsPrev').addEventListener('click', function () {
    if (statementsState.page <= 1) return;
    statementsState.page -= 1;
    fetchStatementsPage();
  });

  el('statementsNext').addEventListener('click', function () {
    if (statementsState.page >= statementsState.totalPages) return;
    statementsState.page += 1;
    fetchStatementsPage();
  });

  var ESCAPABLE_MODALS = [
    { id: 'statementsModal', close: closeStatements },
    { id: 'atmBusinessModal', close: function () { el('atmBusinessModal').classList.add('hidden'); } },
    { id: 'transactionDetailModal', close: function () { el('transactionDetailModal').classList.add('hidden'); } },
    { id: 'receiptModal', close: function () { el('receiptModal').classList.add('hidden'); } },
    { id: 'largeTransferModal', close: function () { el('largeTransferModal').classList.add('hidden'); } },
    { id: 'confirmModal', close: function () { el('confirmModal').classList.add('hidden'); } }
  ];

  var ENTER_SUBMIT_INPUT_IDS = { amountInput: true, targetInput: true, noteInput: true };

  document.addEventListener('keydown', function (event) {
    if (root.classList.contains('hidden')) return;
    for (var i = 0; i < ESCAPABLE_MODALS.length; i++) {
      var modal = ESCAPABLE_MODALS[i];
      if (!el(modal.id).classList.contains('hidden')) {
        if (event.key === 'Escape') {
          event.preventDefault();
          modal.close();
        }
        return;
      }
    }
    if (event.key === 'Escape' || event.key === 'Backspace') {
      event.preventDefault();
      closePanel(true);
      return;
    }
    // v1.8.0: Enter confirms the active deposit/withdraw/transfer form, only
    // when typing in one of its own fields and only when no modal is open
    // (modals above already return early) — never on a held/repeated key,
    // since the submit button's own `submitting`/disabled guard is what
    // actually prevents a double-fire, not this handler.
    if (event.key === 'Enter' && !event.repeat && ENTER_SUBMIT_INPUT_IDS[event.target && event.target.id]) {
      event.preventDefault();
      var submitBtn = el('btnSubmit');
      if (!submitBtn.hidden && !submitBtn.disabled) submitBtn.click();
    }
  });

  window.addEventListener('message', function (event) {
    var data = event.data || {};

    if (data.action === 'interaction') updateInteraction(data.data || {});
    if (data.action === 'open') openPanel(data.data || {});
    if (data.action === 'close') closePanel(false);

    if (data.action === 'ownershipToggled') {
      ownership.enabled = !!(data.data && data.data.enabled);
      if (!root.classList.contains('hidden')) render();
    }

    if (data.action === 'recipientLookupResult') {
      var lookup = data.data || {};
      recipientLookup = {
        charId: (typeof lookup.targetCharacterId === 'number') ? lookup.targetCharacterId : null,
        ok: !!lookup.ok,
        name: lookup.name || null,
        message: lookup.message || ''
      };
      if (pendingLookupCallback && pendingLookupTargetId === recipientLookup.charId) {
        var lookupCb = pendingLookupCallback;
        pendingLookupCallback = null;
        pendingLookupTargetId = null;
        lookupCb(recipientLookup);
      }
    }

    if (data.action === 'statementsResult') {
      var stResult = data.data || {};
      if (stResult.ok) {
        statementsState.page = stResult.page || 1;
        statementsState.totalPages = stResult.totalPages || 1;
        statementsState.totalCount = stResult.totalCount || 0;
        statementsState.rows = Array.isArray(stResult.rows) ? stResult.rows : [];
        renderStatements();
      } else if (stResult.message) {
        showToast(stResult.message, 'error');
      }
    }

    if (data.action === 'atmAnalyticsResult') {
      var anResult = data.data || {};
      if (anResult.ok) {
        renderBusinessMetrics(anResult);
      } else if (anResult.message) {
        showToast(anResult.message, 'error');
      }
    }

    if (data.action === 'atmHistoryResult') {
      var histResult = data.data || {};
      if (histResult.ok) {
        businessState.page = histResult.page || 1;
        businessState.totalPages = histResult.totalPages || 1;
        businessState.totalCount = histResult.totalCount || 0;
        businessState.rows = Array.isArray(histResult.rows) ? histResult.rows : [];
        renderBusinessHistory();
      } else if (histResult.message) {
        showToast(histResult.message, 'error');
      }
    }

    if (data.action === 'payeesResult') {
      var payeesResult = data.data || {};
      payeeActionPending = false;
      el('btnAddPayee').disabled = false;
      if (Array.isArray(payeesResult.payees)) {
        payees = payeesResult.payees;
      }
      renderPayees();
      if (payeesResult.message) showToast(payeesResult.message, payeesResult.ok ? 'success' : 'error');
    }

    if (data.action === 'actionResult') {
      var result = (data.data && data.data.result) || {};
      var action = data.data && data.data.action;

      if (typeof result.cash === 'number') context.cash = result.cash;
      if (typeof result.bank === 'number') context.bank = result.bank;

      if (action === 'buyAtm' || action === 'setAtmFee' || action === 'withdrawAtmEarnings' || action === 'sellAtm' || action === 'setAtmContact' || action === 'restockAtm') {
        atmBusy = false;
        if (result.ok && result.atm) {
          atmInfo = {
            key: result.atm.key || atmInfo.key,
            id: result.atm.id || atmInfo.id,
            owned: result.atm.owned === true,
            isOwner: result.atm.isOwner === true,
            ownerName: result.atm.ownerName || null,
            contact: result.atm.contact || null,
            feePercent: Number(result.atm.feePercent) || 0,
            disabled: result.atm.disabled === true,
            forSale: result.atm.forSale !== false,
            pendingEarnings: Number(result.atm.pendingEarnings) || 0,
            cashReserve: Number(result.atm.cashReserve) || 0,
            cashCapacity: Number(result.atm.cashCapacity) || 0,
            reserveStatus: result.atm.reserveStatus || 'operational',
            reserveUnlimited: result.atm.reserveUnlimited !== false,
            ownerReserveContribution: Number(result.atm.ownerReserveContribution) || 0
          };
        }
        if (result.ok && action === 'restockAtm') {
          el('restockRow').hidden = true;
          el('restockInput').value = '';
        }
        render();
        showToast(result.message || 'The request could not be completed.', result.ok ? 'success' : 'error');
        return;
      }

      submitting = false;
      el('atm').classList.remove('processing');

      if (action === 'transferReceived') {
        if (result.ok) {
          pushActivity({
            kind: 'TRANSFER IN', tag: '←', kindClass: 'kind-received', sign: 'positive',
            amountText: '+$' + formatMoney(result.amount || 0),
            counterparty: result.senderName ? ('← ' + result.senderName) : '',
            reference: result.transactionId ? ('Ref ' + result.transactionId) : ''
          });
        }
        if (!root.classList.contains('hidden')) render();
        return;
      }

      if (result.ok) {
        if ((action === 'deposit' || action === 'withdraw') && result.atm) {
          atmInfo.cashReserve = Number(result.atm.cashReserve) || 0;
          atmInfo.cashCapacity = Number(result.atm.cashCapacity) || atmInfo.cashCapacity;
          atmInfo.reserveStatus = result.atm.reserveStatus || atmInfo.reserveStatus;
          atmInfo.reserveUnlimited = result.atm.reserveUnlimited !== false;
          if (typeof result.atm.pendingEarnings === 'number') atmInfo.pendingEarnings = result.atm.pendingEarnings;
        }
        var receiptNoteText = el('noteInput').value;

        if (action === 'deposit') {
          var depositAmount = typeof result.amount === 'number' ? result.amount : Math.floor(Number(el('amountInput').value) || 0);
          pushActivity({
            kind: 'DEPOSIT', tag: '↓', kindClass: 'kind-deposit', sign: 'positive',
            amountText: '+$' + formatMoney(depositAmount),
            reference: result.transactionId ? ('Ref ' + result.transactionId) : ''
          });
          context.today.moneyIn += depositAmount;
          context.thisMonth.moneyIn += depositAmount;
          renderToday();
          renderFinancialSummary();
          if (depositAmount > 0) lastDepositAmount = depositAmount;
        }
        if (action === 'withdraw') {
          var withdrawAmount = typeof result.amount === 'number' ? result.amount : Math.floor(Number(el('amountInput').value) || 0);
          pushActivity({
            kind: 'WITHDRAW', tag: '↑', kindClass: 'kind-withdraw', sign: 'negative',
            amountText: '-$' + formatMoney(withdrawAmount),
            counterparty: Number(result.fee) > 0 ? ('Withdrawal fee -$' + formatMoney(result.fee)) : '',
            reference: result.transactionId ? ('Ref ' + result.transactionId) : ''
          });
          context.today.moneyOut += withdrawAmount;
          context.today.feesPaid += Number(result.fee) || 0;
          context.thisMonth.moneyOut += withdrawAmount;
          context.thisMonth.feesPaid += Number(result.fee) || 0;
          renderToday();
          renderFinancialSummary();
          if (withdrawAmount > 0) lastWithdrawAmount = withdrawAmount;
        }
        if (action === 'transfer') {
          var sentAmount = typeof result.amount === 'number' ? result.amount : Math.floor(Number(el('amountInput').value) || 0);
          pushActivity({
            kind: 'TRANSFER OUT', tag: '→', kindClass: 'kind-transfer', sign: 'negative',
            amountText: '-$' + formatMoney(sentAmount),
            counterparty: result.targetName ? ('→ ' + result.targetName + (result.offlineDelivery ? ' (pending delivery)' : '')) : '',
            reference: result.transactionId ? ('Ref ' + result.transactionId) : ''
          });
          context.today.moneyOut += sentAmount;
          context.thisMonth.moneyOut += sentAmount;
          context.monthlyTransfers.sentCount += 1;
          context.monthlyTransfers.moneySent += sentAmount;
          renderToday();
          renderFinancialSummary();
        }

        if (action === 'deposit' || action === 'withdraw' || action === 'transfer') {
          openReceipt(action, result, receiptNoteText);
        }

        el('amountInput').value = '';
        if (action === 'transfer') {
          el('targetInput').value = '';
          el('noteInput').value = '';
          recipientLookup = { charId: null, ok: false, name: null, message: '' };
        }
      }
      render();
      var isReceiptAction = result.ok && (action === 'deposit' || action === 'withdraw' || action === 'transfer');
      if (!isReceiptAction) {
        showToast(result.message || 'The request could not be completed.', result.ok ? 'success' : 'error');
      }
    }
  });

  setRootVisible(false);
  updateClock();
  setInterval(updateClock, 1000);

  try {
    if (new URLSearchParams(window.location.search).get('preview') === '1') {
      openPanel({
        cash: 4820, bank: 128500,
        limits: { minAmount: 1 },
        transferLimits: { minimum: 1 },
        transferSecurity: { largeTransferWarning: 100000 },
        today: { moneyIn: 25000, moneyOut: 12500, feesPaid: 420 },
        thisMonth: { moneyIn: 284300, moneyOut: 161200, feesPaid: 1420 },
        monthlyTransfers: { sentCount: 18, receivedCount: 13, moneySent: 242500, moneyReceived: 186200 },
        transactions: [
          { kind: 'deposit', amount: 2000, time: '2026-08-25 13:04:00' },
          { kind: 'transfer_out', amount: 500, counterpartyName: 'Alex Reyes', time: '2026-08-25 09:47:00' }
        ],
        payees: [
          { id: 1, recipientCharacterId: 142, nickname: 'Alex', isFavourite: true },
          { id: 2, recipientCharacterId: 81, nickname: 'House Owner', isFavourite: true },
          { id: 3, recipientCharacterId: 23, nickname: 'Brother', isFavourite: false }
        ],
        payeeLimits: { maxPayees: 30, maxFavourites: 6, nicknameMaxLength: 40 },
        atm: {
          key: 'preview', id: 7, owned: true, isOwner: true, ownerName: 'You', contact: '555-0142', feePercent: 2,
          disabled: false, forSale: true, pendingEarnings: 340,
          cashReserve: 68450, cashCapacity: 100000, reserveStatus: 'operational', reserveUnlimited: false, ownerReserveContribution: 20000
        },
        ownership: {
          enabled: true, purchasePrice: 15000, unownedFeePercent: 2, feeChoices: [1, 2, 3, 4], governmentSellPercent: 80, ownedAtmId: 7,
          defaultCashCapacity: 100000, purchaseStartingReserve: 25000
        }
      });
    }
  } catch (_) {}
})();
