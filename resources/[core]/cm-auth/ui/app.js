// cm-auth/ui/app.js

const app = document.getElementById('app');
const loginForm = document.getElementById('login-form');
const registerForm = document.getElementById('register-form');
const formTitle = document.getElementById('form-title');
const formEyebrow = document.getElementById('form-eyebrow');
const toast = document.getElementById('toast');

const loginEmail = document.getElementById('login-email');
const loginPass = document.getElementById('login-pass');
const rememberEmail = document.getElementById('remember-email');
const regEmail = document.getElementById('reg-email');
const regPass = document.getElementById('reg-pass');
const regPass2 = document.getElementById('reg-pass2');
const loginBtn = document.getElementById('login-btn');
const registerBtn = document.getElementById('register-btn');

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
        button.dataset.originalText = button.textContent;
        button.textContent = text || 'Please wait...';
        button.disabled = true;
    } else {
        button.textContent = button.dataset.originalText || button.textContent;
        button.disabled = false;
    }
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

function showLogin() {
    loginForm.classList.add('active');
    registerForm.classList.remove('active');
    formTitle.textContent = 'Login';
    formEyebrow.textContent = 'Authorization';
    setLoading(registerBtn, false);
    setTimeout(() => loginEmail?.focus(), 50);
}

function showRegister() {
    registerForm.classList.add('active');
    loginForm.classList.remove('active');
    formTitle.textContent = 'Register';
    formEyebrow.textContent = 'Create account';
    setLoading(loginBtn, false);
    if (loginEmail?.value && regEmail) regEmail.value = loginEmail.value.trim();
    setTimeout(() => regEmail?.focus(), 50);
}

function openAuth() {
    app.classList.remove('hidden');
    loadRememberedEmail();
    showLogin();
}

function closeAuth() {
    app.classList.add('hidden');
    setLoading(loginBtn, false);
    setLoading(registerBtn, false);
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
    post('login', { email, password })
        .catch(() => {
            setLoading(loginBtn, false);
            showToast('Connection error. Try again.', 'error');
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
    post('register', { email, password, confirmPassword })
        .catch(() => {
            setLoading(registerBtn, false);
            showToast('Connection error. Try again.', 'error');
        });
}

window.addEventListener('message', (event) => {
    const data = event.data || {};

    if (data.action === 'open') {
        openAuth();
    }

    if (data.action === 'closeAuth') {
        closeAuth();
    }

    if (data.action === 'error') {
        setLoading(loginBtn, false);
        showToast(data.message || 'Wrong password. Try again.', 'error');
    }

    if (data.action === 'registerResult') {
        setLoading(registerBtn, false);
        showToast(data.message || (data.success ? 'Account created.' : 'Register failed.'), data.success ? 'success' : 'error');
        if (data.success) {
            if (regEmail?.value && loginEmail) loginEmail.value = regEmail.value.trim().toLowerCase();
            regPass.value = '';
            regPass2.value = '';
            setTimeout(showLogin, 900);
        }
    }
});

document.querySelectorAll('.eye-btn').forEach((button) => {
    button.addEventListener('click', () => {
        const targetId = button.getAttribute('data-toggle');
        const input = document.getElementById(targetId);
        if (!input) return;
        input.type = input.type === 'password' ? 'text' : 'password';
        button.textContent = input.type === 'password' ? '👁' : '🙈';
    });
});

loginForm.addEventListener('submit', login);
registerForm.addEventListener('submit', register);

window.showLogin = showLogin;
window.showRegister = showRegister;

loadRememberedEmail();
