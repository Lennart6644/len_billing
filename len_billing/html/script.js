
const S = {
    locale: {}, config: {}, ctx: null, mode: 'issue', view: 'issue', sub: 'received', prices: false, billType: 'private',
    items: [], targetId: null, targetName: '', reason: '', noProfit: false,
    players: [], filter: 'all', current: { list: [], kind: 'received' },
};

const $ = (selector) => document.querySelector(selector);
const esc = (value) => String(value ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const t = (key) => S.locale[key] ?? key;
const money = (value) => S.config.currency + Number(value || 0).toLocaleString(S.locale.numberLocale);
const toInt = (value) => Math.floor(Number(value) || 0);
const blankItem = () => ({ description: '', quantity: 1, unitPrice: 0 });
const accent = (color) => color ? `--accent:${esc(color)}` : '';
const taxLabel = () => t('ui_tax').replace('%s', S.config.taxPercent + ' %');
const isPrivate = () => S.billType === 'private';
const reasonDefault = () => isPrivate() ? S.ctx.defaultReasonPrivate : S.ctx.defaultReasonJob;
const lateNote = () => t('ui_late_note').replace('%s', S.config.lateFeePercent + ' %');
const statusOf = (inv) => {
    if (inv.status === 'paid') return 'paid';
    if (inv.status === 'cancelled') return 'cancelled';
    return inv.overdue ? 'overdue' : 'open';
};

function post(name, data) {
    return fetch(`https://${GetParentResourceName()}/request`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, data })
    }).then((r) => r.json()).catch(() => ({ success: false, message: t('ui_connection') }));
}

function fitPaper() {
    const available = window.innerHeight * 0.96 - 90;
    const z = Math.min(1, Math.max(0.5, available / 1123));
    document.documentElement.style.setProperty('--zoom', z.toFixed(3));
}

let flashTimer = null;
function flash(text, state) {
    const overlay = $('#overlay');
    $('#overlay-text').textContent = text;
    $('#overlay-icon').className = state === 'busy'
        ? 'fa-solid fa-spinner fa-spin'
        : state === 'ok' ? 'fa-solid fa-circle-check ok' : 'fa-solid fa-triangle-exclamation bad';
    overlay.classList.remove('hidden');
    clearTimeout(flashTimer);
    if (state !== 'busy') {
        flashTimer = setTimeout(() => overlay.classList.add('hidden'), 1600);
    }
}

function close() {
    fetch(`https://${GetParentResourceName()}/close`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: '{}'
    });
    $('#app').classList.add('hidden');
}

function applyMessage(d) {
    S.locale = d.locale;
    S.config = d.config;
    const vars = { background: '--paper', text: '--ink', muted: '--muted', line: '--line' };
    Object.entries(vars).forEach(([key, cssVar]) => {
        if (d.config.paper && d.config.paper[key]) {
            document.documentElement.style.setProperty(cssVar, d.config.paper[key]);
        }
    });
    document.querySelectorAll('[data-i18n]').forEach((el) => {
        el.textContent = t(el.dataset.i18n);
    });
    fitPaper();
}

function applyMode(mode) {
    S.mode = mode;
    $('#sheet').className = mode;
    $('#tabs').classList.toggle('hidden', mode !== 'bills');
    $('#float-close').classList.toggle('hidden', mode === 'bills');
}

function setActiveTab(view) {
    document.querySelectorAll('.tab[data-view]').forEach((b) => b.classList.toggle('active', b.dataset.view === view));
}

async function go(view, sub) {
    S.view = view;
    S.prices = false;
    if (sub) S.sub = sub;
    else if (view === 'private' || view === 'job') S.sub = 'received';
    setActiveTab(view);
    if (view === 'issue') {
        $('#sheet').classList.remove('is-settings');
        return renderIssue();
    }
    return refresh();
}

function refresh() {
    if (S.prices) {
        $('#sheet').classList.add('is-settings');
        return renderPriceList();
    }
    $('#sheet').classList.remove('is-settings');
    return loadList();
}

function subBar() {
    const leader = !!(S.ctx && S.ctx.isLeader);
    const subs = [['received', 'ui_sub_received']];
    if (S.view === 'private' || leader) subs.push(['issued', 'ui_sub_issued']);
    return `<div class="segment sub">${subs.map(([key, label]) =>
        `<button class="${S.sub === key ? 'on' : ''}" data-sub="${key}">${esc(t(label))}</button>`).join('')}</div>`;
}

async function selectAdminJob(name) {
    const job = S.ctx.allJobs.find((j) => j.name === name);
    if (!job) return;
    const r = await post('getPriceList', { jobName: name, viaCommand: S.viaCommand });
    S.adminJob = name;
    S.ctx.jobLabel = job.label;
    S.ctx.jobStyle = { label: job.label, short: job.short, color: job.color, icon: job.icon };
    S.ctx.jobLimit = null;
    S.ctx.defaultReasonJob = job.defaultReason;
    S.ctx.priceList = Array.isArray(r) ? r : [];
}

function adminDropdown() {
    const cur = S.ctx.allJobs.find((j) => j.name === S.adminJob) || S.ctx.allJobs[0] || {};
    const on = isPrivate() ? '' : ' on';
    return `<div class="dd">
        <button type="button" class="dd-btn${on}" data-dd-toggle>
            <span class="dd-chip" style="background:${esc(cur.color || '#334155')}"><i class="fa-solid ${esc(cur.icon || 'fa-building-columns')}"></i></span>
            <span class="dd-label">${esc(cur.label || '')}</span>
            <i class="fa-solid fa-chevron-down dd-caret"></i>
        </button>
        <div class="dd-menu hidden">${S.ctx.allJobs.map((j) => `
            <button type="button" class="dd-item${j.name === cur.name ? ' sel' : ''}" data-dd-pick="${esc(j.name)}">
                <span class="dd-chip" style="background:${esc(j.color)}"><i class="fa-solid ${esc(j.icon)}"></i></span>
                <span class="dd-text"><b>${esc(j.label)}</b><em>${esc(j.short)}</em></span>
                <i class="fa-solid fa-check dd-check"></i>
            </button>`).join('')}</div>
    </div>`;
}

async function changeAdminJob(name) {
    S.billType = 'job';
    S.noProfit = false;
    await selectAdminJob(name);
    renderIssue();
}

function calc(items, rate) {
    const subtotal = items.reduce((sum, it) => sum + it.quantity * it.unitPrice, 0);
    const tax = Math.floor(subtotal * rate / 100);
    return { subtotal, tax, total: subtotal + tax };
}

function stampHTML(style) {
    return `<div class="stamp" style="${accent(style.color)}">
        <span class="stamp-top">${esc(style.label || '')}</span>
        <span class="stamp-mid">${esc(style.short || '')}</span>
        <span class="stamp-bot">${esc(t('ui_stamp_official'))}</span>
    </div>`;
}

function signZone(place, dateText, isJob, signName, style) {
    const slot = isJob
        ? stampHTML(style)
        : `<div class="sig-wrap"><div class="sig-hand">${esc(signName || '')}</div><small>${esc(t('ui_signature'))}</small></div>`;
    return `<div class="sign-zone">
        <div class="place-block"><small>${esc(t('ui_place_date'))}</small><b>${esc(place)}, ${esc(dateText)}</b></div>
        <div class="sign-slot">${slot}</div>
    </div>`;
}

function bandHTML(dueText, number) {
    return `<footer class="paper-foot">
        <span>${esc(t('ui_due'))} <b>${esc(dueText)}</b> · ${esc(lateNote())}</span>
        <span>${esc(t('ui_number'))} <b>${esc(number)}</b></span>
    </footer>`;
}

function renderIssue() {
    const ctx = S.ctx;
    const style = isPrivate() ? ctx.privateStyle : ctx.jobStyle;
    const sender = isPrivate() ? ctx.name : ctx.jobLabel;
    const subSender = isPrivate() ? style.label : ctx.name;
    const todayText = new Date().toLocaleDateString(S.locale.dateLocale);
    const dueText = new Date(Date.now() + S.config.dueDays * 86400000).toLocaleDateString(S.locale.dateLocale);

    $('#view').innerHTML = `
        <div class="issue-wrap">
            ${ctx.canBillJob ? `<div class="segment">
                <button data-type="private" class="${isPrivate() ? 'on' : ''}">${esc(t('ui_type_private'))}</button>
                ${ctx.isAdmin
                    ? adminDropdown()
                    : `<button data-type="job" class="${isPrivate() ? '' : 'on'}">${esc(ctx.jobLabel)}</button>`}
            </div>` : ''}
            <article class="paper" style="${accent(style.color)}">
                <header class="paper-head">
                    <div class="doc-title">${esc(t('ui_title'))}</div>
                    <div class="issuer">
                        <div class="issuer-name">${esc(sender)}</div>
                        <div class="issuer-sub">${esc(subSender)}</div>
                    </div>
                </header>
                <section class="paper-meta">
                    <div class="meta-left">
                        <small>${esc(t('ui_to'))}</small>
                        <div class="ac">
                            <input id="f-target" value="${esc(S.targetName)}" placeholder="${esc(t('ui_to_placeholder'))}" autocomplete="off">
                            <div class="ac-list hidden" id="ac-list"></div>
                        </div>
                    </div>
                    <div class="meta-right">
                        <div><small>${esc(t('ui_date'))}</small><b>${esc(todayText)}</b></div>
                        <div><small>${esc(t('ui_due'))}</small><b>${esc(dueText)}</b></div>
                    </div>
                </section>
                <section class="paper-body">
                    <table class="items">
                        <thead><tr>
                            <th>${esc(t('ui_item_description'))}</th>
                            <th class="num w-qty">${esc(t('ui_item_quantity'))}</th>
                            <th class="num w-price">${esc(t('ui_item_price'))}</th>
                            <th class="num w-sum">${esc(t('ui_item_total'))}</th>
                            <th class="w-x"></th>
                        </tr></thead>
                        <tbody id="items-body"></tbody>
                    </table>
                    <div class="item-tools">
                        <button class="ghost-btn" data-add><i class="fa-solid fa-plus"></i> ${esc(t('ui_add_item'))}</button>
                    </div>
                    <div class="totals">
                        <div><span>${esc(t('ui_subtotal'))}</span><span id="t-sub"></span></div>
                        <div><span>${esc(taxLabel())}</span><span id="t-tax"></span></div>
                        <div class="grand"><span>${esc(t('ui_total'))}</span><span id="t-total"></span></div>
                    </div>
                    <div class="limit-note" id="limit-note"></div>
                    <div class="reason">
                        <small>${esc(t('ui_reason'))} ${esc(t('ui_optional'))}</small>
                        <input id="f-reason" maxlength="${S.config.maxReason}" value="${esc(S.reason)}" placeholder="${esc(reasonDefault())}">
                    </div>
                    ${isPrivate() ? '' : `<div class="check" data-toggle="noprofit"><span class="xbox">${S.noProfit ? '<span class="x-mark">X</span>' : ''}</span><span class="check-text">${esc(t('ui_no_profit'))}</span></div>`}
                </section>
                ${signZone(S.config.city, todayText, !isPrivate(), ctx.name, style)}
                ${bandHTML(dueText, t('ui_number_new'))}
            </article>
            <button class="submit-btn" id="submit"><i class="fa-solid fa-stamp"></i> ${esc(t('ui_submit'))}</button>
        </div>`;
    renderRows();
    updateTotals();
}

function renderRows() {
    const removable = S.items.length > 1;
    $('#items-body').innerHTML = S.items.map((it, i) => `
        <tr>
            <td class="desc-cell">
                <input class="i-desc" data-i="${i}" maxlength="${S.config.maxDescription}" value="${esc(it.description)}" placeholder="${esc(t('ui_item_placeholder'))}" autocomplete="off">
                <div class="isug hidden" data-isug="${i}"></div>
            </td>
            <td><input class="i-qty num" data-i="${i}" type="number" min="1" max="${S.config.maxQuantity}" value="${it.quantity}"></td>
            <td><input class="i-price num" data-i="${i}" type="number" min="0" max="${S.config.maxUnitPrice}" value="${it.unitPrice}"></td>
            <td class="num" data-sum="${i}">${money(it.quantity * it.unitPrice)}</td>
            <td>${removable ? `<button class="row-del" data-remove="${i}" title="${esc(t('ui_remove'))}"><i class="fa-solid fa-xmark"></i></button>` : ''}</td>
        </tr>`).join('');
}

function refreshRow(i) {
    const it = S.items[i];
    const cell = document.querySelector(`[data-sum="${i}"]`);
    if (cell) cell.textContent = money(it.quantity * it.unitPrice);
    updateTotals();
}

function updateTotals() {
    const c = calc(S.items, S.config.taxPercent);
    const sub = $('#t-sub');
    if (!sub) return;
    sub.textContent = money(c.subtotal);
    $('#t-tax').textContent = money(c.tax);
    $('#t-total').textContent = money(c.total);
    const limit = isPrivate() ? S.ctx.privateLimit : S.ctx.jobLimit;
    const note = $('#limit-note');
    if (!limit) {
        note.textContent = '';
        note.classList.remove('warn');
        return;
    }
    note.textContent = t('ui_limit').replace('%s', money(limit));
    note.classList.toggle('warn', c.total > limit);
}

function renderItemSuggest(i) {
    const box = document.querySelector(`[data-isug="${i}"]`);
    if (!box) return;
    const q = S.items[i].description.trim().toLowerCase();
    const matches = (isPrivate() || q.length < 2) ? [] : S.ctx.priceList
        .map((p, idx) => ({ p, idx }))
        .filter(({ p }) => p.label.toLowerCase().includes(q) || String(p.short).toLowerCase().includes(q))
        .slice(0, 8);
    if (!matches.length) {
        box.classList.add('hidden');
        box.innerHTML = '';
        return;
    }
    box.innerHTML = matches.map(({ p, idx }) => `
        <button class="ac-item" data-ipick="${i}:${idx}">
            <span>${esc(p.label)}<em>${esc(p.category)}</em></span>
            <span class="ac-id">${money(p.price)}</span>
        </button>`).join('');
    box.classList.remove('hidden');
}

function hideItemSuggest() {
    document.querySelectorAll('.isug').forEach((b) => b.classList.add('hidden'));
}

function pickItem(i, idx) {
    const p = S.ctx.priceList[idx];
    if (!p) return;
    S.items[i].description = p.label;
    S.items[i].unitPrice = toInt(p.price);
    renderRows();
    updateTotals();
}

function updateSuggestions() {
    const list = $('#ac-list');
    if (!list) return;
    const q = S.targetName.trim().toLowerCase();
    const matches = q.length < 4 ? [] : S.players.filter((p) => p.name.toLowerCase().includes(q)).slice(0, 6);
    if (!matches.length) {
        list.classList.add('hidden');
        list.innerHTML = '';
        return;
    }
    list.innerHTML = matches.map((p) => `
        <button class="ac-item" data-pick="${p.id}" data-name="${esc(p.name)}">
            <span>${esc(p.name)}</span><span class="ac-id">#${p.id}</span>
        </button>`).join('');
    list.classList.remove('hidden');
}

function hideSuggestions() {
    const list = $('#ac-list');
    if (list) list.classList.add('hidden');
}

function pickPlayer(btn) {
    S.targetId = Number(btn.dataset.pick);
    S.targetName = btn.dataset.name;
    $('#f-target').value = S.targetName;
    hideSuggestions();
}

async function refreshPlayers() {
    const r = await post('getPlayers');
    if (Array.isArray(r)) S.players = r;
    updateSuggestions();
}

function paperView(inv, copy) {
    const rows = (inv.items || []).map((it) => `
        <tr>
            <td>${esc(it.description)}</td>
            <td class="num">${toInt(it.quantity)}</td>
            <td class="num">${money(it.unitPrice)}</td>
            <td class="num">${money(it.lineTotal)}</td>
        </tr>`).join('');
    const isJob = inv.billType === 'job';
    const headName = isJob ? inv.jobLabel : inv.issuer;
    const headSub = isJob ? (inv.issuer || '') : inv.label;
    const lateRow = inv.lateFee > 0
        ? `<div><span>${esc(t('ui_late_fee').replace('%s', S.config.lateFeePercent + ' %'))}</span><span>${money(inv.lateFee)}</span></div>`
        : '';
    const statusOverlay = inv.status === 'paid'
        ? `<div class="status-stamp paid">${esc(t('ui_stamp_paid'))}<small>${esc(inv.paidText || '')}</small></div>`
        : inv.status === 'cancelled'
            ? `<div class="status-stamp cancelled">${esc(t('ui_stamp_cancelled'))}</div>`
            : '';
    const style = { label: isJob ? inv.jobLabel : inv.label, short: inv.short, color: inv.color };
    return `
    <article class="paper" style="${accent(inv.color)}">
        ${copy ? `<div class="watermark">${esc(t('ui_copy'))}</div>` : ''}
        ${statusOverlay}
        <header class="paper-head">
            <div class="doc-title">${esc(t('ui_title'))}</div>
            <div class="issuer">
                <div class="issuer-name">${esc(headName)}</div>
                <div class="issuer-sub">${esc(headSub)}</div>
            </div>
        </header>
        <section class="paper-meta">
            <div class="meta-left">
                <small>${esc(t('ui_to'))}</small>
                <b>${esc(inv.target)}</b>
            </div>
            <div class="meta-right">
                <div><small>${esc(t('ui_number'))}</small><b>${esc(inv.number)}</b></div>
                <div><small>${esc(t('ui_date'))}</small><b>${esc(inv.dateText)}</b></div>
                <div><small>${esc(t('ui_due'))}</small><b>${esc(inv.dueText)}</b></div>
            </div>
        </section>
        <section class="paper-body">
            <table class="items">
                <thead><tr>
                    <th>${esc(t('ui_item_description'))}</th>
                    <th class="num">${esc(t('ui_item_quantity'))}</th>
                    <th class="num">${esc(t('ui_item_price'))}</th>
                    <th class="num">${esc(t('ui_item_total'))}</th>
                </tr></thead>
                <tbody>${rows}</tbody>
            </table>
            <div class="totals">
                <div><span>${esc(t('ui_subtotal'))}</span><span>${money(inv.subtotal)}</span></div>
                <div><span>${esc(taxLabel())}</span><span>${money(inv.tax)}</span></div>
                ${lateRow}
                <div class="grand"><span>${esc(inv.lateFee > 0 ? t('ui_payable') : t('ui_total'))}</span><span>${money(inv.payable)}</span></div>
            </div>
            <div class="reason"><small>${esc(t('ui_reason'))}</small><p>${esc(inv.reason)}</p></div>
            ${inv.noProfit ? `<div class="noprofit">${esc(t('ui_no_profit'))}</div>` : ''}
        </section>
        ${signZone(S.config.city, inv.dateText, isJob, inv.issuer, style)}
        ${bandHTML(inv.dueText, inv.number)}
    </article>`;
}

function cardHTML(inv, kind, index) {
    const st = statusOf(inv);
    const badges = {
        paid: `<span class="badge ok-b">${esc(t('ui_status_paid'))} · ${esc(inv.paidText || '')}</span>`,
        open: `<span class="badge info-b">${esc(t('ui_status_open'))} · ${esc(t('ui_due'))} ${esc(inv.dueText)}</span>`,
        overdue: `<span class="badge">${esc(t('ui_status_overdue'))}</span>`,
        cancelled: `<span class="badge mute-b">${esc(t('ui_status_cancelled'))}</span>`,
    };
    const sub = kind === 'issued' ? inv.target : (inv.issuer || inv.jobLabel || '');
    return `
        <button class="inv-card" data-open="${index}" data-kind="${kind}">
            <span class="inv-strip st-${st}"></span>
            <span class="inv-ic" style="background:${esc(inv.color)}"><i class="fa-solid ${esc(inv.icon)}"></i></span>
            <span class="inv-main">
                <span class="inv-title">${esc(inv.reason)}</span>
                <span class="inv-sub">${esc(sub)} · ${esc(inv.number)}</span>
                <span class="inv-status">${badges[st]}</span>
            </span>
            <span class="inv-amount">${money(inv.payable)}</span>
        </button>`;
}

function renderList(list, kind) {
    S.current = { list, kind };
    const filters = [['all', 'ui_filter_all'], ['open', 'ui_filter_open'], ['overdue', 'ui_filter_overdue'], ['paid', 'ui_filter_paid']];
    const bar = `<div class="filters">${filters.map(([key, label]) =>
        `<button class="f-btn ${S.filter === key ? 'on' : ''}" data-filter="${key}">${esc(t(label))}</button>`).join('')}</div>`;
    const visible = list.filter((inv) => S.filter === 'all' || statusOf(inv) === S.filter);
    const body = visible.length
        ? `<div class="list">${visible.map((inv) => cardHTML(inv, kind, list.indexOf(inv))).join('')}</div>`
        : `<div class="empty"><i class="fa-regular fa-folder-open"></i><p>${esc(list.length ? t('ui_empty_filter') : t('ui_empty'))}</p></div>`;
    const manage = (S.view === 'job' && S.ctx && S.ctx.isLeader)
        ? `<div class="manage-row"><button class="btn ghost" data-open-prices><i class="fa-solid fa-tags"></i> ${esc(t('ui_settings_title'))}</button></div>`
        : '';
    $('#view').innerHTML = `<div class="list-wrap">${subBar()}${manage}${bar}${body}</div>`;
}

function renderPreview(inv, kind) {
    const st = statusOf(inv);
    const open = st === 'open' || st === 'overdue';
    let action = '';
    if (open && kind === 'received') {
        action = `<button class="btn primary" data-pay="${inv.id}"><i class="fa-solid fa-credit-card"></i> ${esc(t('ui_pay'))} · ${money(inv.payable)}</button>`;
    }
    if (open && kind === 'issued') {
        action = `<button class="btn danger" data-cancel="${inv.id}"><i class="fa-solid fa-trash"></i> ${esc(t('ui_cancel_invoice'))}</button>`;
    }
    $('#view').innerHTML = `
        <div class="preview">
            ${paperView(inv, false)}
            <div class="actions">
                <button class="btn ghost" data-back><i class="fa-solid fa-arrow-left"></i> ${esc(t('ui_back'))}</button>
                ${action}
            </div>
        </div>`;
}

function renderPrinted(inv) {
    $('#view').innerHTML = `<div class="preview">${paperView(inv, true)}</div>`;
}

async function payInvoice(id) {
    flash(t('ui_paying'), 'busy');
    const r = await post('pay', id);
    flash(r.message, r.success ? 'ok' : 'bad');
    if (r.success) loadList();
}

async function cancelInvoice(btn) {
    if (btn.dataset.armed !== '1') {
        btn.dataset.armed = '1';
        btn.innerHTML = `<i class="fa-solid fa-triangle-exclamation"></i> ${esc(t('ui_sure'))}`;
        return;
    }
    flash(t('ui_cancelling'), 'busy');
    const r = await post('cancel', Number(btn.dataset.cancel));
    flash(r.message, r.success ? 'ok' : 'bad');
    if (r.success) loadList();
}

async function submitInvoice() {
    let targetId = S.targetId;
    if (!targetId) {
        const q = S.targetName.trim().toLowerCase();
        const exact = S.players.find((p) => p.name.toLowerCase() === q || String(p.id) === q);
        targetId = exact ? exact.id : null;
    }
    if (!targetId) {
        flash(t('ui_err_target'), 'bad');
        return;
    }
    flash(t('ui_issuing'), 'busy');
    const r = await post('issue', {
        billType: S.billType,
        targetSource: targetId,
        reason: S.reason,
        noProfit: S.noProfit,
        items: S.items,
        asAdmin: !!(S.ctx.isAdmin && !isPrivate()),
        viaCommand: S.viaCommand,
        jobName: S.adminJob,
    });
    flash(r.message, r.success ? 'ok' : 'bad');
    if (r.success) {
        setTimeout(close, 900);
    }
}

$('#view').addEventListener('focusin', (e) => {
    if (e.target.id === 'f-target') refreshPlayers();
});

$('#view').addEventListener('input', (e) => {
    const el = e.target;
    if (el.id === 'f-target') {
        S.targetName = el.value;
        S.targetId = null;
        updateSuggestions();
    }
    if (el.id === 'f-reason') S.reason = el.value;
    if (el.classList.contains('i-desc')) {
        const i = Number(el.dataset.i);
        S.items[i].description = el.value;
        renderItemSuggest(i);
    }
    if (el.classList.contains('i-qty')) {
        S.items[el.dataset.i].quantity = Math.max(1, toInt(el.value));
        refreshRow(el.dataset.i);
    }
    if (el.classList.contains('i-price')) {
        S.items[el.dataset.i].unitPrice = Math.max(0, toInt(el.value));
        refreshRow(el.dataset.i);
    }
});

$('#view').addEventListener('change', async (e) => {
    if (e.target.id === 'f-noprofit') S.noProfit = e.target.checked;
});

$('#view').addEventListener('click', (e) => {
    if (!e.target.closest('.ac')) hideSuggestions();
    if (!e.target.closest('.desc-cell')) hideItemSuggest();
    if (!e.target.closest('.dd')) {
        document.querySelectorAll('.dd-menu').forEach((m) => m.classList.add('hidden'));
        document.querySelectorAll('.dd').forEach((d) => d.classList.remove('open'));
    }
    const toggle = e.target.closest('[data-toggle="noprofit"]');
    if (toggle) {
        S.noProfit = !S.noProfit;
        return renderIssue();
    }
    const btn = e.target.closest('button');
    if (!btn) return;
    if (settingsAction(btn)) return;
    if (btn.hasAttribute('data-dd-toggle')) {
        const wrap = btn.closest('.dd');
        const menu = wrap.querySelector('.dd-menu');
        menu.classList.toggle('hidden');
        wrap.classList.toggle('open', !menu.classList.contains('hidden'));
        return;
    }
    if (btn.dataset.ddPick !== undefined) return changeAdminJob(btn.dataset.ddPick);
    if (btn.dataset.step !== undefined) return stepPrice(btn, Number(btn.dataset.step));
    if (btn.dataset.pick !== undefined) return pickPlayer(btn);
    if (btn.dataset.ipick !== undefined) {
        const [i, idx] = btn.dataset.ipick.split(':').map(Number);
        return pickItem(i, idx);
    }
    if (btn.hasAttribute('data-open-prices')) {
        S.prices = true;
        return renderPriceList();
    }
    if (btn.hasAttribute('data-prices-back')) {
        S.prices = false;
        return refresh();
    }
    if (btn.dataset.sub) {
        S.sub = btn.dataset.sub;
        S.filter = 'all';
        return refresh();
    }
    if (btn.dataset.filter) {
        S.filter = btn.dataset.filter;
        return renderList(S.current.list, S.current.kind);
    }
    if (btn.dataset.type) {
        S.billType = btn.dataset.type;
        S.noProfit = false;
        return renderIssue();
    }
    if (btn.hasAttribute('data-add')) {
        if (S.items.length < S.config.maxItems) S.items.push(blankItem());
        return renderIssue();
    }
    if (btn.dataset.remove !== undefined) {
        if (S.items.length > 1) S.items.splice(Number(btn.dataset.remove), 1);
        return renderRows() || updateTotals();
    }
    if (btn.id === 'submit') return submitInvoice();
    if (btn.hasAttribute('data-open')) {
        return renderPreview(S.current.list[Number(btn.dataset.open)], btn.dataset.kind);
    }
    if (btn.hasAttribute('data-back')) return renderList(S.current.list, S.current.kind);
    if (btn.hasAttribute('data-pay')) return payInvoice(Number(btn.dataset.pay));
    if (btn.hasAttribute('data-cancel')) return cancelInvoice(btn);
    if (btn.hasAttribute('data-close')) return close();
});

document.querySelectorAll('.tab[data-view]').forEach((btn) => {
    btn.addEventListener('click', () => {
        if (btn.dataset.view !== S.view) S.filter = 'all';
        go(btn.dataset.view);
    });
});

$('#btn-close').addEventListener('click', close);
$('#float-close').addEventListener('click', close);

document.addEventListener('keyup', (e) => {
    if (e.key === 'Escape' && !$('#app').classList.contains('hidden')) close();
});

window.addEventListener('resize', fitPaper);

window.addEventListener('message', async (e) => {
    const d = e.data;
    if (!d || !d.action) return;

    if (d.action === 'open') {
        applyMessage(d);
        S.ctx = d.context;
        S.billType = d.admin ? 'job' : 'private';
        S.adminJob = null;
        S.viaCommand = d.admin === true;
        if (S.ctx.isAdmin && S.ctx.allJobs.length) await selectAdminJob(S.ctx.allJobs[0].name);
        S.items = [blankItem()];
        S.targetId = null;
        S.targetName = '';
        S.reason = '';
        S.noProfit = false;
        S.filter = 'all';
        S.sub = 'received';
        $('#app').classList.remove('hidden');
        applyMode(d.mode);
        const players = await post('getPlayers');
        S.players = Array.isArray(players) ? players : [];
        go(d.mode === 'bills' ? 'job' : 'issue');
    }

    if (d.action === 'printed') {
        applyMessage(d);
        $('#app').classList.remove('hidden');
        applyMode('printed');
        renderPrinted(d.invoice);
    }

    if (d.action === 'hide') {
        $('#app').classList.add('hidden');
    }
});

function armed(btn) {
    if (btn.dataset.armed === '1') {
        return true;
    }
    btn.dataset.armed = '1';
    btn.classList.add('armed');
    btn.innerHTML = `<i class="fa-solid fa-question"></i>`;
    btn.title = t('ui_settings_confirm');
    return false;
}



function settingsAction(btn) {
    const d = btn.dataset;
    if (d.catSave !== undefined) {
        const name = document.querySelector(`[data-cat-name="${d.catSave}"]`).value;
        saveInPlace(btn, 'saveCategory', { id: Number(d.catSave), name });
        return true;
    }
    if (d.catDel !== undefined) {
        if (!armed(btn)) return true;
        mutate(btn, 'deleteCategory', { id: Number(d.catDel) });
        return true;
    }
    if (d.catAdd !== undefined) {
        mutate(btn, 'saveCategory', { name: document.querySelector('#new-cat').value });
        return true;
    }
    if (d.itemSave !== undefined) {
        const id = Number(d.itemSave);
        saveInPlace(btn, 'saveItem', {
            id,
            categoryId: Number(d.cat),
            label: document.querySelector(`[data-item-label="${id}"]`).value,
            short: document.querySelector(`[data-item-short="${id}"]`).value,
            price: document.querySelector(`[data-item-price="${id}"]`).value,
        });
        return true;
    }
    if (d.itemDel !== undefined) {
        if (!armed(btn)) return true;
        mutate(btn, 'deleteItem', { id: Number(d.itemDel) });
        return true;
    }
    if (d.itemAdd !== undefined) {
        const c = d.itemAdd;
        mutate(btn, 'saveItem', {
            categoryId: Number(c),
            label: document.querySelector(`[data-new-label="${c}"]`).value,
            short: document.querySelector(`[data-new-short="${c}"]`).value,
            price: document.querySelector(`[data-new-price="${c}"]`).value,
        });
        return true;
    }
    return false;
}

const priceField = (attrs, value, placeholder) => `
    <div class="price-field">
        <span class="cur">${esc(S.config.currency)}</span>
        <input class="price" type="number" min="0" max="${S.config.maxUnitPrice}" ${attrs} value="${esc(value)}" placeholder="${esc(placeholder)}">
        <span class="stepper">
            <button type="button" class="step" data-step="1"><i class="fa-solid fa-chevron-up"></i></button>
            <button type="button" class="step" data-step="-1"><i class="fa-solid fa-chevron-down"></i></button>
        </span>
    </div>`;

function priceHead() {
    return `<div class="settings-top">
        <button class="btn ghost" data-prices-back><i class="fa-solid fa-arrow-left"></i> ${esc(t('ui_back'))}</button>
        <span class="settings-head">${esc(t('ui_settings_title'))}</span>
        <span class="admin-badge">${esc(t('ui_settings_badge'))}</span>
    </div>`;
}

async function renderPriceList(keep = false) {
    const view = $('#view');
    const y = view.scrollTop;
    if (!keep) view.innerHTML = `<div class="settings-wrap">${priceHead()}<div class="status-line"><i class="fa-solid fa-spinner fa-spin"></i> ${esc(t('ui_loading'))}</div></div>`;
    const r = await post('getPrices');
    if (!S.prices) return;
    const cats = Array.isArray(r) ? r : [];
    view.innerHTML = `
        <div class="settings-wrap">
            ${priceHead()}
            ${cats.length ? '' : `<div class="empty">${esc(t('ui_settings_empty'))}</div>`}
            ${cats.map((c) => `
                <section class="cat-block">
                    <div class="cat-head">
                        <input class="cat-name" data-cat-name="${c.id}" value="${esc(c.name)}" maxlength="80">
                        <button class="mini-btn" data-cat-save="${c.id}" title="${esc(t('ui_settings_save'))}"><i class="fa-solid fa-floppy-disk"></i></button>
                        <button class="mini-btn danger" data-cat-del="${c.id}"><i class="fa-solid fa-trash"></i></button>
                    </div>
                    ${c.items.map((it) => `
                        <div class="item-row">
                            <input data-item-label="${it.id}" value="${esc(it.label)}" maxlength="120" placeholder="${esc(t('ui_settings_label'))}">
                            <input class="short" data-item-short="${it.id}" value="${esc(it.short)}" maxlength="40" placeholder="${esc(t('ui_settings_short'))}">
                            ${priceField(`data-item-price="${it.id}"`, it.price, '')}
                            <button class="mini-btn" data-item-save="${it.id}" data-cat="${c.id}" title="${esc(t('ui_settings_save'))}"><i class="fa-solid fa-check"></i></button>
                            <button class="mini-btn danger" data-item-del="${it.id}"><i class="fa-solid fa-xmark"></i></button>
                        </div>`).join('')}
                    <div class="item-row new">
                        <input data-new-label="${c.id}" maxlength="120" placeholder="${esc(t('ui_settings_new_item'))}: ${esc(t('ui_settings_label'))}">
                        <input class="short" data-new-short="${c.id}" maxlength="40" placeholder="${esc(t('ui_settings_short'))}">
                        ${priceField(`data-new-price="${c.id}"`, '', t('ui_settings_price'))}
                        <button class="mini-btn primary" data-item-add="${c.id}"><i class="fa-solid fa-plus"></i></button>
                    </div>
                </section>`).join('')}
            <section class="cat-block">
                <div class="cat-head">
                    <input id="new-cat" maxlength="80" placeholder="${esc(t('ui_settings_new_category'))}">
                    <button class="mini-btn wide primary" data-cat-add><i class="fa-solid fa-plus"></i> ${esc(t('ui_settings_add_category'))}</button>
                </div>
            </section>
        </div>`;
    view.scrollTop = keep ? y : 0;
}

async function loadList() {
    const view = S.view;
    const sub = S.sub;
    $('#view').innerHTML = `<div class="status-line"><i class="fa-solid fa-spinner fa-spin"></i> ${esc(t('ui_loading'))}</div>`;
    let r;
    if (sub === 'issued' && view === 'private') r = await post('getPrivateIssued');
    else if (sub === 'issued' && view === 'job') r = await post('getJobInvoices');
    else r = await post('getInbox', { billType: view === 'job' ? 'job' : 'private' });
    if (S.view !== view || S.sub !== sub) return;
    renderList(Array.isArray(r) ? r : [], sub === 'issued' ? 'issued' : 'received');
}

function feedback(btn, r) {
    if (!btn.dataset.icon) btn.dataset.icon = btn.innerHTML;
    clearTimeout(btn._reset);
    btn.classList.remove('pulse-ok', 'pulse-bad');
    void btn.offsetWidth;
    btn.classList.add(r.success ? 'pulse-ok' : 'pulse-bad');
    btn.innerHTML = `<i class="fa-solid ${r.success ? 'fa-check' : 'fa-xmark'}"></i>`;
    btn._reset = setTimeout(() => {
        btn.innerHTML = btn.dataset.icon;
        btn.classList.remove('pulse-ok', 'pulse-bad');
    }, 1100);
    if (!r.success && r.message) {
        const tip = document.createElement('span');
        tip.className = 'btn-tip';
        tip.textContent = r.message;
        btn.parentElement.appendChild(tip);
        setTimeout(() => tip.remove(), 2200);
    }
}

async function saveInPlace(btn, name, data) {
    feedback(btn, await post(name, data));
}

async function mutate(btn, name, data) {
    const r = await post(name, data);
    if (r.success) return renderPriceList(true);
    feedback(btn, r);
}

function stepPrice(btn, dir) {
    const input = btn.closest('.price-field').querySelector('input');
    input.value = Math.min(S.config.maxUnitPrice, Math.max(0, toInt(input.value) + dir * 10));
}
