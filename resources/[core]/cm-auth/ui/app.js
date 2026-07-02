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

let toastTimer = null;

function resourceUrl(path) {
    return `https://${GetParentResourceName()}/${path}`;
}

function showToast(message, type = 'error') {
    if (!toast) return;
    clearTimeout(toastTimer);
    toast.textContent = message || 'Something went wrong.';
    toast.className = `toast show ${type}`;
    toastTimer = setTimeout(() => {
        toast.className = 'toast';
    }, 4200);
}

function setLoading(button, loading, text) {
    if (!button) return;

    if (loading) {
        button.dataset.originalText = button.dataset.originalText || button.textContent;
        button.textContent = text || 'Please wait...';
        button.disabled = true;
        return;
    }

    button.textContent = button.dataset.originalText || button.textContent;
    button.disabled = false;
}

function loadRememberedEmail() {
    const remembered = localStorage.getItem('cm_auth_email') || '';
    if (remembered && loginEmail) {
        loginEmail.value = remembered;
        if (rememberEmail) rememberEmail.checked = true;
    }
}

function saveRememberedEmail(email) {
    if (rememberEmail && rememberEmail.checked) {
        localStorage.setItem('cm_auth_email', email);
    } else {
        localStorage.removeItem('cm_auth_email');
    }
}

function showForms() {
    trustedPanel.classList.add('hidden');
    formsWrap.classList.remove('hidden');
}

function showLogin() {
    showForms();
    loginForm.classList.add('active');
    registerForm.classList.remove('active');
    resetForm?.classList.remove('active');
    formTitle.textContent = 'Login';
    formEyebrow.textContent = 'Authorization';
    setLoading(loginBtn, false);
    setLoading(registerBtn, false);
    setLoading(resetBtn, false);
    setLoading(trustedLoginBtn, false);
    window.setTimeout(() => loginEmail?.focus(), 50);
}

function showRegister() {
    showForms();
    registerForm.classList.add('active');
    loginForm.classList.remove('active');
    resetForm?.classList.remove('active');
    formTitle.textContent = 'Register';
    formEyebrow.textContent = 'Create account';
    setLoading(loginBtn, false);
    setLoading(registerBtn, false);
    setLoading(resetBtn, false);
    setLoading(trustedLoginBtn, false);
    if (loginEmail?.value && regEmail) regEmail.value = loginEmail.value.trim();
    window.setTimeout(() => regEmail?.focus(), 50);
}

function showReset() {
    showForms();
    resetForm?.classList.add('active');
    loginForm.classList.remove('active');
    registerForm.classList.remove('active');
    formTitle.textContent = 'Reset password';
    formEyebrow.textContent = 'Account recovery';
    setLoading(loginBtn, false);
    setLoading(registerBtn, false);
    setLoading(resetBtn, false);
    setLoading(trustedLoginBtn, false);
    if (loginEmail?.value && resetEmail) resetEmail.value = loginEmail.value.trim().toLowerCase();
    window.setTimeout(() => resetEmail?.focus(), 50);
}

function showTrusted(profile = {}) {
    app.classList.remove('hidden');
    formsWrap.classList.add('hidden');
    trustedPanel.classList.remove('hidden');
    formTitle.textContent = 'Login as';
    formEyebrow.textContent = 'Trusted device';
    trustedName.textContent = `Login as ${profile.username || 'Player'}`;
    trustedEmail.textContent = profile.email || '';
    setLoading(loginBtn, false);
    setLoading(registerBtn, false);
    setLoading(trustedLoginBtn, false);
}

function openAuth(type = 'login', profile = {}) {
    app.classList.remove('hidden');
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
    app.classList.add('hidden');
    setLoading(loginBtn, false);
    setLoading(registerBtn, false);
    setLoading(trustedLoginBtn, false);
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

    const email = loginEmail.value.trim().toLowerCase();
    const password = loginPass.value;

    if (!email || !password) {
        showToast('Enter your email and password.', 'error');
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

    const email = regEmail.value.trim().toLowerCase();
    const password = regPass.value;
    const confirmPassword = regPass2.value;

    if (!email || !password || !confirmPassword) {
        showToast('Fill in all register fields.', 'error');
        return;
    }

    if (password.length < 6) {
        showToast('Password must be at least 6 characters.', 'error');
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

    const email = resetEmail.value.trim().toLowerCase();
    const password = resetPass.value;
    const confirmPassword = resetPass2.value;

    if (!email || !password || !confirmPassword) {
        showToast('Fill in all reset fields.', 'error');
        return;
    }

    if (password.length < 6) {
        showToast('Password must be at least 6 characters.', 'error');
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
    });
});

loginForm.addEventListener('submit', login);
registerForm.addEventListener('submit', register);
resetForm?.addEventListener('submit', resetPassword);
trustedLoginBtn.addEventListener('click', trustedLogin);
switchAccountBtn.addEventListener('click', forgetToken);

window.showLogin = showLogin;
window.showRegister = showRegister;
window.showReset = showReset;

loadRememberedEmail();

window.addEventListener('DOMContentLoaded', () => {
    post('uiReady', {}).catch(() => {});
});
