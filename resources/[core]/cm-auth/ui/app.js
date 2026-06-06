// cm-auth/ui/app.js

console.log('[CM-AUTH-UI] === SCRIPT STARTING ===');

const app = document.getElementById('app');
const loginForm = document.getElementById('login-form');
const registerForm = document.getElementById('register-form');
const errorMsg = document.getElementById('error-msg');

console.log('[CM-AUTH-UI] app found:', !!app);
console.log('[CM-AUTH-UI] loginForm found:', !!loginForm);
console.log('[CM-AUTH-UI] registerForm found:', !!registerForm);
console.log('[CM-AUTH-UI] errorMsg found:', !!errorMsg);

// Listen for messages from client Lua
window.addEventListener('message', function(event) {
    console.log('[CM-AUTH-UI] >>> MESSAGE RECEIVED <<<');
    console.log('[CM-AUTH-UI] event.data:', JSON.stringify(event.data));
    
    const data = event.data;
    
    if (data.action === 'open') {
        console.log('[CM-AUTH-UI] ACTION = OPEN');
        if (app) {
            app.style.display = 'flex';
            console.log('[CM-AUTH-UI] app display set to flex');
        } else {
            console.error('[CM-AUTH-UI] ERROR: app element not found!');
        }
        showLogin();
    }
    
    // FIX: Add handler to hide the auth container completely
    if (data.action === 'closeAuth') {
        console.log('[CM-AUTH-UI] ACTION = CLOSEAUTH');
        if (app) {
            app.style.display = 'none';
        }
    }
    
    if (data.action === 'error') {
        console.log('[CM-AUTH-UI] ACTION = ERROR, msg:', data.message);
        showError(data.message, 'error');
    }
    
    if (data.action === 'registerResult') {
        console.log('[CM-AUTH-UI] ACTION = REGISTERRESULT, success:', data.success);
        showError(data.message, data.success ? 'success' : 'error');
        if (data.success) {
            console.log('[CM-AUTH-UI] Register success, switching to login in 2s');
            setTimeout(showLogin, 2000);
        }
    }
});

function showLogin() {
    console.log('[CM-AUTH-UI] showLogin() called');
    if (loginForm) loginForm.style.display = 'block';
    if (registerForm) registerForm.style.display = 'none';
    if (errorMsg) errorMsg.style.display = 'none';
    console.log('[CM-AUTH-UI] Login visible, register hidden');
}

function showRegister() {
    console.log('[CM-AUTH-UI] showRegister() called');
    if (loginForm) loginForm.style.display = 'none';
    if (registerForm) registerForm.style.display = 'block';
    if (errorMsg) errorMsg.style.display = 'none';
    console.log('[CM-AUTH-UI] Register visible, login hidden');
}

function showError(msg, type) {
    console.log('[CM-AUTH-UI] showError:', msg, type);
    if (!errorMsg) {
        console.error('[CM-AUTH-UI] ERROR: errorMsg element missing!');
        return;
    }
    errorMsg.textContent = msg;
    errorMsg.className = 'show ' + (type || 'error');
}

// ============================================
// LOGIN
// ============================================

function login() {
    console.log('[CM-AUTH-UI] >>> LOGIN BUTTON CLICKED <<<');
    
    const usernameInput = document.getElementById('login-user');
    const passwordInput = document.getElementById('login-pass');
    
    console.log('[CM-AUTH-UI] usernameInput found:', !!usernameInput);
    console.log('[CM-AUTH-UI] passwordInput found:', !!passwordInput);
    
    const username = usernameInput ? usernameInput.value.trim() : '';
    const password = passwordInput ? passwordInput.value : '';
    
    console.log('[CM-AUTH-UI] username:', username);
    console.log('[CM-AUTH-UI] password entered:', !!password);
    console.log('[CM-AUTH-UI] password length:', password.length);
    
    if (!username || !password) {
        console.log('[CM-AUTH-UI] VALIDATION FAILED: empty fields');
        showError('Please fill in all fields');
        return;
    }
    
    const resourceName = GetParentResourceName();
    console.log('[CM-AUTH-UI] Resource name:', resourceName);
    
    const url = 'https://' + resourceName + '/login';
    console.log('[CM-AUTH-UI] Fetch URL:', url);
    
    const body = JSON.stringify({ username: username, password: password });
    console.log('[CM-AUTH-UI] Request body:', body);
    
    fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: body
    })
    .then(function(response) {
        console.log('[CM-AUTH-UI] Fetch response status:', response.status);
        return response.text();
    })
    .then(function(text) {
        console.log('[CM-AUTH-UI] Fetch response body:', text);
    })
    .catch(function(error) {
        console.error('[CM-AUTH-UI] FETCH ERROR:', error.message);
        showError('Connection error: ' + error.message);
    });
    
    console.log('[CM-AUTH-UI] Fetch request sent');
}

// ============================================
// REGISTER
// ============================================

function register() {
    console.log('[CM-AUTH-UI] >>> REGISTER BUTTON CLICKED <<<');
    
    const usernameInput = document.getElementById('reg-user');
    const emailInput = document.getElementById('reg-email');
    const passwordInput = document.getElementById('reg-pass');
    
    const username = usernameInput ? usernameInput.value.trim() : '';
    const email = emailInput ? emailInput.value.trim() : '';
    const password = passwordInput ? passwordInput.value : '';
    
    console.log('[CM-AUTH-UI] username:', username);
    console.log('[CM-AUTH-UI] email:', email);
    console.log('[CM-AUTH-UI] password entered:', !!password);
    console.log('[CM-AUTH-UI] password length:', password.length);
    
    if (!username || !email || !password) {
        console.log('[CM-AUTH-UI] VALIDATION FAILED: empty fields');
        showError('Please fill in all fields');
        return;
    }
    
    if (password.length < 6) {
        console.log('[CM-AUTH-UI] VALIDATION FAILED: password too short');
        showError('Password must be at least 6 characters');
        return;
    }
    
    const resourceName = GetParentResourceName();
    const url = 'https://' + resourceName + '/register';
    console.log('[CM-AUTH-UI] Fetch URL:', url);
    
    const body = JSON.stringify({ username: username, email: email, password: password });
    console.log('[CM-AUTH-UI] Request body:', body);
    
    fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: body
    })
    .then(function(response) {
        console.log('[CM-AUTH-UI] Fetch response status:', response.status);
        return response.text();
    })
    .then(function(text) {
        console.log('[CM-AUTH-UI] Fetch response body:', text);
    })
    .catch(function(error) {
        console.error('[CM-AUTH-UI] FETCH ERROR:', error.message);
        showError('Connection error: ' + error.message);
    });
    
    console.log('[CM-AUTH-UI] Fetch request sent');
}

// Expose to window for HTML onclick
window.showLogin = showLogin;
window.showRegister = showRegister;
window.login = login;
window.register = register;

console.log('[CM-AUTH-UI] === SCRIPT READY ===');
console.log('[CM-AUTH-UI] Waiting for "open" message from client...');