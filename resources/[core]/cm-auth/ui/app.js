// cm-auth UI logic
const app = document.getElementById('app');
const loginForm = document.getElementById('login-form');
const registerForm = document.getElementById('register-form');
const resetForm = document.getElementById('reset-form');
const formsWrap = document.getElementById('forms-wrap');
const trustedPanel = document.getElementById('trusted-panel');
const trustedName = document.getElementById('trusted-name');
const trustedEmail = document.getElementById('trusted-email');
const trustedLoginBtn = document.getElementById('trusted-login-btn');
const switchAccountBtn = document.getElementById('switch-account-btn');
const formTitle = document.getElementById('form-title');
const formEyebrow = document.getElementById('form-eyebrow');
const formSubtext = document.getElementById('form-subtext');
const toast = document.getElementById('toast');

const loginEmail = document.getElementById('login-email');
const loginPass = document.getElementById('login-pass');
const rememberEmail = document.getElementById('remember-email');
const regEmail = document.getElementById('reg-email');
const regPass = document.getElementById('reg-pass');
const regPass2 = document.getElementById('reg-pass2');
const resetEmail = document.getElementById('reset-email');
const resetPass = document.getElementById('reset-pass');
const resetPass2 = document.getElementById('reset-pass2');
const loginBtn = document.getElementById('login-btn');
const registerBtn = document.getElementById('register-btn');
const resetBtn = document.getElementById('reset-btn');

// Mirrors shared/config.lua Config.Password. Fast client-side feedback only —
// the server remains the authority on these bounds.
const PASSWORD_MIN = 6;
const PASSWORD_MAX = 72;
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const REQUEST_TIMEOUT_MS = 12000;

let toastTimer = null;

function resourceUrl(path) {
    return `https://${GetParentResourceName()}/${path}`;
}

function showToast(message, type = 'error') {
    const finalMessage = message || 'Something went wrong.';

    if (window.CMUI && typeof window.CMUI.toast === 'function') {
        window.CMUI.toast(finalMessage, type, 4200);
        return;
    }

    if (!toast) return;
    clearTimeout(toastTimer);
    toast.textContent = finalMessage;
    toast.className = `toast show ${type}`;
    toastTimer = setTimeout(() => {
        toast.className = 'toast';
    }, 4200);
}

// Disables the button while a request is pending and guarantees it re-enables
// even if the server/NUI round-trip never responds (dead-button prevention).
// Buttons are skewed shapes with a nested .btn-label + .btn-icon — swap the
// label's text only, never the button's own textContent, or the icon/skew
// wrapper markup would be destroyed.
function setLoading(button, loading, text) {
    if (!button) return;
    const label = button.querySelector('.btn-label') || button;

    clearTimeout(button._cmTimeout);
    button._cmTimeout = null;

    if (loading) {
        button.dataset.originalText = button.dataset.originalText || label.textContent;
        label.textContent = text || 'Please wait...';
        button.disabled = true;
        button._cmTimeout = window.setTimeout(() => {
            setLoading(button, false);
            showToast('Connection error. Try again.', 'error');
        }, REQUEST_TIMEOUT_MS);
        return;
    }

    label.textContent = button.dataset.originalText || label.textContent;
    button.disabled = false;
}

function resetAllButtons() {
    setLoading(loginBtn, false);
    setLoading(registerBtn, false);
    setLoading(resetBtn, false);
    setLoading(trustedLoginBtn, false);
}

function isValidEmailFormat(email) {
    return EMAIL_PATTERN.test(email);
}

function brandName() {
    return (window.CMBranding && window.CMBranding.serverName) || 'CM Roleplay';
}

// Applies the single shared branding source (../shared/branding.js) to the
// static eyebrow so this page never hardcodes the server name; brandName()
// covers the "into CM Roleplay" mention inside the login subtitle.
function applyBranding() {
    const brand = window.CMBranding || {};
    if (formEyebrow) formEyebrow.textContent = brand.tagline || 'Enter the city';
}

// Shows only the first character of the local part so a saved account is
// recognizable without printing the full address.
function maskEmail(email) {
    const raw = String(email || '');
    const at = raw.indexOf('@');
    if (at <= 0) return raw;
    return `${raw.slice(0, 1)}***${raw.slice(at)}`;
}

function loadRememberedEmail() {
    let remembered = '';
    try {
        remembered = localStorage.getItem('cm_auth_email') || '';
    } catch (e) {
        remembered = '';
    }
    if (remembered && loginEmail) {
        loginEmail.value = remembered;
        if (rememberEmail) rememberEmail.checked = true;
    }
}

function saveRememberedEmail(email) {
    try {
        if (rememberEmail && rememberEmail.checked) {
            localStorage.setItem('cm_auth_email', email);
        } else {
            localStorage.removeItem('cm_auth_email');
        }
    } catch (e) {
        // Private-mode/blocked storage: remembering email is a convenience only.
    }
}

function showForms() {
    trustedPanel?.classList.add('hidden');
    formsWrap?.classList.remove('hidden');
}

function showLogin() {
    showForms();
    loginForm?.classList.add('active');
    registerForm?.classList.remove('active');
    resetForm?.classList.remove('active');
    if (formTitle) formTitle.textContent = 'Welcome back';
    if (formSubtext) formSubtext.textContent = `Sign in to continue into ${brandName()}. Saved login is supported.`;
    resetAllButtons();
    window.setTimeout(() => loginEmail?.focus(), 50);
}

function showRegister() {
    showForms();
    registerForm?.classList.add('active');
    loginForm?.classList.remove('active');
    resetForm?.classList.remove('active');
    if (formTitle) formTitle.textContent = 'Create account';
    if (formSubtext) formSubtext.textContent = 'Create your account to start playing.';
    resetAllButtons();
    if (loginEmail?.value && regEmail) regEmail.value = loginEmail.value.trim();
    window.setTimeout(() => regEmail?.focus(), 50);
}

function showReset() {
    showForms();
    resetForm?.classList.add('active');
    loginForm?.classList.remove('active');
    registerForm?.classList.remove('active');
    if (formTitle) formTitle.textContent = 'Reset password';
    if (formSubtext) formSubtext.textContent = 'Resetting works only from the Rockstar account that owns this profile.';
    resetAllButtons();
    if (loginEmail?.value && resetEmail) resetEmail.value = loginEmail.value.trim().toLowerCase();
    window.setTimeout(() => resetEmail?.focus(), 50);
}

function showTrusted(profile = {}) {
    app?.classList.remove('hidden');
    formsWrap?.classList.add('hidden');
    trustedPanel?.classList.remove('hidden');
    if (formTitle) formTitle.textContent = 'Welcome back';
    if (formSubtext) formSubtext.textContent = `Sign in to continue into ${brandName()}. Saved login is supported.`;
    if (trustedName) trustedName.textContent = `Welcome back, ${profile.username || 'Player'}`;
    if (trustedEmail) trustedEmail.textContent = profile.email ? maskEmail(profile.email) : '';
    resetAllButtons();
}

function openAuth(type = 'login', profile = {}) {
    app?.classList.remove('hidden');
    loadRememberedEmail();

    if (type === 'trusted') {
        showTrusted(profile);
    } else if (type === 'register') {
        showRegister();
    } else {
        showLogin();
    }
}

function closeAuth() {
    app?.classList.add('hidden');
    resetAllButtons();
    // Login succeeded (this is the only path that closes the whole page) —
    // don't leave the password sitting in the DOM.
    if (loginPass) loginPass.value = '';
}

async function post(path, payload) {
    const response = await fetch(resourceUrl(path), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload || {})
    });
    return response.text();
}

function login(event) {
    if (event) event.preventDefault();
    if (loginBtn?.disabled) return;

    const email = loginEmail.value.trim().toLowerCase();
    const password = loginPass.value;

    if (!email || !password) {
        showToast('Enter your email and password.', 'error');
        return;
    }
    if (!isValidEmailFormat(email)) {
        showToast('Enter a valid email address.', 'error');
        return;
    }

    saveRememberedEmail(email);
    setLoading(loginBtn, true, 'Logging in...');
    post('login', { email, password }).catch(() => {
        setLoading(loginBtn, false);
        showToast('Connection error. Try again.', 'error');
    });
}

function trustedLogin() {
    if (trustedLoginBtn?.disabled) return;
    setLoading(trustedLoginBtn, true, 'Logging in...');
    post('tokenLogin', {}).catch(() => {
        setLoading(trustedLoginBtn, false);
        showToast('Saved login failed. Try again.', 'error');
    });
}

function forgetToken() {
    setLoading(trustedLoginBtn, false);
    post('forgetToken', {}).finally(() => {
        showLogin();
        showToast('Saved login removed. Login with email and password.', 'success');
    });
}

function register(event) {
    if (event) event.preventDefault();
    if (registerBtn?.disabled) return;

    const email = regEmail.value.trim().toLowerCase();
    const password = regPass.value;
    const confirmPassword = regPass2.value;

    if (!email || !password || !confirmPassword) {
        showToast('Fill in all register fields.', 'error');
        return;
    }
    if (!isValidEmailFormat(email)) {
        showToast('Enter a valid email address.', 'error');
        return;
    }
    if (password.length < PASSWORD_MIN) {
        showToast(`Password must be at least ${PASSWORD_MIN} characters.`, 'error');
        return;
    }
    if (password.length > PASSWORD_MAX) {
        showToast(`Password must be ${PASSWORD_MAX} characters or fewer.`, 'error');
        return;
    }
    if (password !== confirmPassword) {
        showToast('Passwords do not match.', 'error');
        return;
    }

    setLoading(registerBtn, true, 'Creating...');
    post('register', { email, password, confirmPassword }).catch(() => {
        setLoading(registerBtn, false);
        showToast('Connection error. Try again.', 'error');
    });
}

function resetPassword(event) {
    if (event) event.preventDefault();
    if (resetBtn?.disabled) return;

    const email = resetEmail.value.trim().toLowerCase();
    const password = resetPass.value;
    const confirmPassword = resetPass2.value;

    if (!email || !password || !confirmPassword) {
        showToast('Fill in all reset fields.', 'error');
        return;
    }
    if (!isValidEmailFormat(email)) {
        showToast('Enter a valid email address.', 'error');
        return;
    }
    if (password.length < PASSWORD_MIN) {
        showToast(`Password must be at least ${PASSWORD_MIN} characters.`, 'error');
        return;
    }
    if (password.length > PASSWORD_MAX) {
        showToast(`Password must be ${PASSWORD_MAX} characters or fewer.`, 'error');
        return;
    }
    if (password !== confirmPassword) {
        showToast('Passwords do not match.', 'error');
        return;
    }

    setLoading(resetBtn, true, 'Resetting...');
    post('resetPassword', { email, password, confirmPassword }).catch(() => {
        setLoading(resetBtn, false);
        showToast('Connection error. Try again.', 'error');
    });
}

window.addEventListener('message', (event) => {
    const data = event.data || {};

    if (data.action === 'open') {
        openAuth(data.type || 'login', data.profile || {});
    }

    if (data.action === 'closeAuth') {
        closeAuth();
    }

    if (data.action === 'error') {
        setLoading(loginBtn, false);
        setLoading(trustedLoginBtn, false);
        showToast(data.message || 'Wrong password. Try again.', 'error');
        if (trustedPanel && !trustedPanel.classList.contains('hidden')) {
            showLogin();
        }
    }

    if (data.action === 'registerResult') {
        setLoading(registerBtn, false);
        showToast(data.message || (data.success ? 'Account created.' : 'Register failed.'), data.success ? 'success' : 'error');
        if (data.success) {
            if (regEmail?.value && loginEmail) loginEmail.value = regEmail.value.trim().toLowerCase();
            regPass.value = '';
            regPass2.value = '';
            window.setTimeout(showLogin, 900);
        }
    }

    if (data.action === 'resetResult') {
        setLoading(resetBtn, false);
        showToast(data.message || (data.success ? 'Password updated.' : 'Reset failed.'), data.success ? 'success' : 'error');
        if (data.success) {
            if (resetEmail?.value && loginEmail) loginEmail.value = resetEmail.value.trim().toLowerCase();
            resetPass.value = '';
            resetPass2.value = '';
            window.setTimeout(showLogin, 900);
        }
    }
});

document.querySelectorAll('.eye-btn').forEach((button) => {
    button.addEventListener('click', () => {
        const targetId = button.getAttribute('data-toggle');
        const input = document.getElementById(targetId);
        if (!input) return;
        const nextType = input.type === 'password' ? 'text' : 'password';
        input.type = nextType;
        button.textContent = nextType === 'password' ? 'SHOW' : 'HIDE';
        button.setAttribute('aria-label', nextType === 'password' ? 'Show password' : 'Hide password');
    });
});

// Form-switch controls (links and secondary buttons) use data-nav instead of
// inline onclick handlers.
document.querySelectorAll('[data-nav]').forEach((button) => {
    button.addEventListener('click', () => {
        const target = button.getAttribute('data-nav');
        if (target === 'register') showRegister();
        else if (target === 'reset') showReset();
        else showLogin();
    });
});

loginForm?.addEventListener('submit', login);
registerForm?.addEventListener('submit', register);
resetForm?.addEventListener('submit', resetPassword);
trustedLoginBtn?.addEventListener('click', trustedLogin);
switchAccountBtn?.addEventListener('click', forgetToken);

loadRememberedEmail();
applyBranding();

window.addEventListener('DOMContentLoaded', () => {
    post('uiReady', {}).catch(() => {});
});
