#!/bin/bash

# ============================================
# ایجاد پروژه داشبورد چت حرفه‌ای
# ============================================

PROJECT_DIR="llama-dashboard"

echo "🚀 در حال ایجاد پروژه در پوشه: $PROJECT_DIR"

# ایجاد ساختار پوشه‌ها
mkdir -p "$PROJECT_DIR/modules"
mkdir -p "$PROJECT_DIR/assets/icons"

# ========== index.html ==========
cat > "$PROJECT_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html dir="rtl" lang="fa">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>داشبورد چت حرفه‌ای</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <!-- نوار کناری -->
    <div class="sidebar" id="sidebar">
        <div class="logo">🤖 <span>Chat Pro</span></div>
        <button class="nav-btn active" data-page="chat">💬 چت</button>
        <button class="nav-btn" data-page="history">📜 تاریخچه</button>
        <button class="nav-btn" data-page="models">📦 مدل‌ها</button>
        <button class="nav-btn" data-page="settings">⚙️ تنظیمات</button>
        <button class="nav-btn" data-page="roles">🎭 نقش‌ها</button>
        <button class="theme-toggle" id="themeToggle">🌙</button>
    </div>

    <!-- محتوای اصلی -->
    <div class="main-content">
        <div id="app"></div>
    </div>

    <!-- ===== هسته برنامه ===== -->
    <script>
        // state مدیریت وضعیت
        window.app = {
            state: {
                currentPage: 'chat',
                theme: localStorage.getItem('theme') || 'dark',
                chatHistory: JSON.parse(localStorage.getItem('chatHistory') || '[]'),
                modelPath: '',
                apiKey: '',
                mode: 'offline', // 'offline' | 'online'
                params: {
                    temperature: 0.7,
                    top_p: 0.9,
                    max_tokens: 512,
                    context_size: 2048,
                    systemPrompt: 'شما یک دستیار مفید و دقیق هستید.'
                },
                roles: JSON.parse(localStorage.getItem('roles') || '[]'),
                currentRole: null,
                isStreaming: false,
                abortController: null
            },
            navigate: function(page) {
                this.state.currentPage = page;
                if (window.loadModule) window.loadModule(page);
                document.querySelectorAll('.nav-btn').forEach(btn => {
                    btn.classList.toggle('active', btn.dataset.page === page);
                });
            },
            updateState: function(newState) {
                Object.assign(this.state, newState);
                if (newState.chatHistory !== undefined) {
                    localStorage.setItem('chatHistory', JSON.stringify(this.state.chatHistory));
                }
                if (newState.roles !== undefined) {
                    localStorage.setItem('roles', JSON.stringify(this.state.roles));
                }
                if (newState.theme !== undefined) {
                    localStorage.setItem('theme', this.state.theme);
                    document.documentElement.setAttribute('data-theme', this.state.theme);
                }
                document.dispatchEvent(new CustomEvent('appStateChanged', { detail: this.state }));
            }
        };

        document.documentElement.setAttribute('data-theme', window.app.state.theme);
        document.getElementById('themeToggle').textContent = window.app.state.theme === 'dark' ? '🌙' : '☀️';
        document.getElementById('themeToggle').addEventListener('click', () => {
            const newTheme = window.app.state.theme === 'dark' ? 'light' : 'dark';
            window.app.updateState({ theme: newTheme });
            document.getElementById('themeToggle').textContent = newTheme === 'dark' ? '🌙' : '☀️';
        });
    </script>

    <script type="module" src="app.js"></script>
</body>
</html>
EOF

# ========== style.css ==========
cat > "$PROJECT_DIR/style.css" << 'EOF'
:root {
    --bg: #0d1117;
    --bg-secondary: #161b22;
    --bg-hover: #1c2333;
    --text: #e6edf3;
    --text-secondary: #8b949e;
    --border: #30363d;
    --accent: #58a6ff;
    --accent-hover: #79c0ff;
    --danger: #f85149;
    --success: #3fb950;
    --shadow: rgba(0, 0, 0, 0.5);
    --radius: 12px;
    --transition: 0.3s ease;
}
[data-theme="light"] {
    --bg: #ffffff;
    --bg-secondary: #f6f8fa;
    --bg-hover: #eaeef2;
    --text: #1f2328;
    --text-secondary: #656d76;
    --border: #d0d7de;
    --accent: #0969da;
    --accent-hover: #0550ae;
    --shadow: rgba(0, 0, 0, 0.1);
}
* { margin: 0; padding: 0; box-sizing: border-box; transition: background var(--transition), color var(--transition), border var(--transition); }
body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    background: var(--bg);
    color: var(--text);
    height: 100vh;
    overflow: hidden;
    display: flex;
}
.sidebar {
    width: 220px;
    background: var(--bg-secondary);
    border-right: 1px solid var(--border);
    padding: 20px 12px;
    display: flex;
    flex-direction: column;
    gap: 8px;
    flex-shrink: 0;
    overflow-y: auto;
}
.logo {
    font-size: 22px;
    font-weight: 700;
    padding: 12px 16px;
    margin-bottom: 16px;
    display: flex;
    align-items: center;
    gap: 10px;
    color: var(--accent);
}
.logo span { color: var(--text); }
.nav-btn {
    background: transparent;
    border: none;
    color: var(--text-secondary);
    padding: 12px 16px;
    border-radius: var(--radius);
    font-size: 15px;
    font-weight: 500;
    cursor: pointer;
    text-align: right;
    transition: all var(--transition);
    display: flex;
    align-items: center;
    gap: 12px;
}
.nav-btn:hover { background: var(--bg-hover); color: var(--text); }
.nav-btn.active { background: var(--accent); color: #fff; }
.nav-btn .icon { font-size: 18px; }
.theme-toggle {
    margin-top: auto;
    background: var(--bg-hover);
    border: 1px solid var(--border);
    color: var(--text);
    padding: 10px;
    border-radius: var(--radius);
    cursor: pointer;
    font-size: 20px;
    transition: all var(--transition);
}
.theme-toggle:hover { background: var(--border); }
.main-content { flex: 1; padding: 20px 24px; overflow-y: auto; background: var(--bg); }
#app { max-width: 1000px; margin: 0 auto; height: 100%; }
.chat-container { display: flex; flex-direction: column; height: 100%; }
.chat-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 12px 0;
    border-bottom: 1px solid var(--border);
    margin-bottom: 16px;
    flex-wrap: wrap;
    gap: 8px;
}
.chat-header .mode-badge {
    font-size: 13px;
    padding: 4px 12px;
    border-radius: 20px;
    background: var(--bg-secondary);
    border: 1px solid var(--border);
    color: var(--text-secondary);
}
.chat-header .role-badge {
    font-size: 13px;
    padding: 4px 12px;
    border-radius: 20px;
    background: var(--accent);
    color: #fff;
}
.chat-box {
    flex: 1;
    overflow-y: auto;
    padding: 12px 0;
    display: flex;
    flex-direction: column;
    gap: 12px;
    min-height: 300px;
}
.msg {
    max-width: 85%;
    padding: 12px 16px;
    border-radius: var(--radius);
    line-height: 1.6;
    word-wrap: break-word;
    animation: fadeIn 0.3s ease;
}
.msg.user { align-self: flex-end; background: var(--accent); color: #fff; }
.msg.assistant { align-self: flex-start; background: var(--bg-secondary); border: 1px solid var(--border); }
.msg .role-label { font-size: 11px; opacity: 0.7; margin-bottom: 4px; }
.msg .msg-actions { margin-top: 8px; display: flex; gap: 8px; }
.msg .msg-actions button {
    background: transparent;
    border: none;
    color: var(--text-secondary);
    cursor: pointer;
    font-size: 14px;
    padding: 2px 6px;
    border-radius: 4px;
}
.msg .msg-actions button:hover { background: var(--bg-hover); color: var(--text); }
.msg .streaming-cursor {
    display: inline-block;
    width: 4px;
    height: 1em;
    background: var(--accent);
    animation: blink 1s infinite;
    vertical-align: text-bottom;
}
.chat-input-area {
    display: flex;
    gap: 10px;
    padding: 12px 0;
    border-top: 1px solid var(--border);
    flex-wrap: wrap;
}
.chat-input-area input {
    flex: 1;
    padding: 12px 16px;
    border: 1px solid var(--border);
    border-radius: var(--radius);
    background: var(--bg-secondary);
    color: var(--text);
    font-size: 15px;
    outline: none;
    min-width: 150px;
}
.chat-input-area input:focus { border-color: var(--accent); }
.chat-input-area button {
    padding: 12px 24px;
    border: none;
    border-radius: var(--radius);
    background: var(--accent);
    color: #fff;
    font-size: 15px;
    font-weight: 600;
    cursor: pointer;
    transition: all var(--transition);
    white-space: nowrap;
}
.chat-input-area button:hover { background: var(--accent-hover); }
.chat-input-area button:disabled { opacity: 0.5; cursor: not-allowed; }
.chat-input-area .voice-btn { background: var(--bg-hover); color: var(--text); padding: 12px 16px; }
.chat-input-area .voice-btn:hover { background: var(--border); }
.chat-input-area .voice-btn.recording { background: var(--danger); color: #fff; }
.settings-container { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; }
@media (max-width: 600px) { .settings-container { grid-template-columns: 1fr; } }
.settings-group {
    background: var(--bg-secondary);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 20px;
}
.settings-group h3 { margin-bottom: 16px; font-size: 16px; }
.settings-group label {
    display: block;
    margin: 12px 0 4px;
    font-size: 14px;
    color: var(--text-secondary);
}
.settings-group input, .settings-group select, .settings-group textarea {
    width: 100%;
    padding: 10px 12px;
    border: 1px solid var(--border);
    border-radius: var(--radius);
    background: var(--bg);
    color: var(--text);
    font-size: 14px;
    outline: none;
}
.settings-group input:focus, .settings-group textarea:focus { border-color: var(--accent); }
.settings-group textarea { resize: vertical; min-height: 80px; font-family: inherit; }
.settings-group .range-value { float: left; color: var(--accent); font-weight: 600; }
.settings-group input[type="range"] { padding: 0; background: transparent; accent-color: var(--accent); }
.history-item {
    background: var(--bg-secondary);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 16px;
    margin-bottom: 10px;
    cursor: pointer;
    transition: all var(--transition);
}
.history-item:hover { background: var(--bg-hover); border-color: var(--accent); }
.history-item .title { font-weight: 600; }
.history-item .date { font-size: 12px; color: var(--text-secondary); }
.history-item .preview {
    font-size: 14px;
    color: var(--text-secondary);
    margin-top: 4px;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
}
.history-item .delete-btn {
    float: left;
    background: transparent;
    border: none;
    color: var(--danger);
    cursor: pointer;
    font-size: 14px;
    padding: 4px 8px;
    border-radius: 4px;
}
.history-item .delete-btn:hover { background: var(--danger); color: #fff; }
.model-card {
    background: var(--bg-secondary);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 16px;
    margin-bottom: 10px;
    display: flex;
    justify-content: space-between;
    align-items: center;
    flex-wrap: wrap;
    gap: 8px;
}
.model-card .info .name { font-weight: 600; }
.model-card .info .size { font-size: 13px; color: var(--text-secondary); }
.model-card .actions button {
    padding: 6px 14px;
    border: none;
    border-radius: 6px;
    cursor: pointer;
    font-size: 13px;
    transition: all var(--transition);
}
.model-card .actions .load-btn { background: var(--accent); color: #fff; }
.model-card .actions .load-btn:hover { background: var(--accent-hover); }
.model-card .actions .delete-btn { background: var(--danger); color: #fff; }
.model-card .actions .delete-btn:hover { opacity: 0.8; }
.model-card .progress { width: 100%; height: 4px; background: var(--border); border-radius: 4px; margin-top: 8px; overflow: hidden; }
.model-card .progress .bar { height: 100%; background: var(--accent); transition: width 0.5s ease; }
.role-card {
    background: var(--bg-secondary);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 16px;
    margin-bottom: 10px;
    display: flex;
    justify-content: space-between;
    align-items: center;
    flex-wrap: wrap;
    gap: 8px;
}
.role-card .info .name { font-weight: 600; }
.role-card .info .desc { font-size: 13px; color: var(--text-secondary); }
.role-card .actions button {
    padding: 6px 14px;
    border: none;
    border-radius: 6px;
    cursor: pointer;
    font-size: 13px;
    transition: all var(--transition);
}
.role-card .actions .apply-btn { background: var(--accent); color: #fff; }
.role-card .actions .apply-btn:hover { background: var(--accent-hover); }
.role-card .actions .delete-btn { background: var(--danger); color: #fff; }
.role-card .actions .delete-btn:hover { opacity: 0.8; }
@keyframes fadeIn { from { opacity: 0; transform: translateY(8px); } to { opacity: 1; transform: translateY(0); } }
@keyframes blink { 0%, 100% { opacity: 1; } 50% { opacity: 0; } }
::-webkit-scrollbar { width: 6px; height: 6px; }
::-webkit-scrollbar-track { background: var(--bg-secondary); }
::-webkit-scrollbar-thumb { background: var(--border); border-radius: 10px; }
::-webkit-scrollbar-thumb:hover { background: var(--text-secondary); }
EOF

# ========== app.js ==========
cat > "$PROJECT_DIR/app.js" << 'EOF'
// ===== لودر اصلی ماژول‌ها =====
window.loadModule = function(moduleName) {
    import(`./modules/${moduleName}.js`)
        .then(module => {
            document.getElementById('app').innerHTML = module.default();
            if (module.init) module.init();
        })
        .catch(err => {
            console.error(`خطا در لود ماژول ${moduleName}:`, err);
            document.getElementById('app').innerHTML = `<div class="error">خطا در بارگذاری صفحه</div>`;
        });
};

// لود صفحه پیش‌فرض
window.loadModule(window.app.state.currentPage);
EOF

# ========== ماژول‌ها ==========

# ماژول چت
cat > "$PROJECT_DIR/modules/chat.js" << 'EOF'
export default function() {
    const history = window.app.state.chatHistory.map((msg, i) => `
        <div class="msg ${msg.role}">
            <div class="role-label">${msg.role === 'user' ? 'شما' : 'دستیار'}</div>
            ${msg.content}
            <div class="msg-actions">
                <button onclick="copyText('${i}')">📋</button>
            </div>
        </div>
    `).join('');

    return `
        <div class="chat-container">
            <div class="chat-header">
                <div>
                    <span class="mode-badge">${window.app.state.mode === 'offline' ? '📴 آفلاین' : '🌐 آنلاین'}</span>
                    ${window.app.state.currentRole ? `<span class="role-badge">🎭 ${window.app.state.currentRole}</span>` : ''}
                </div>
                <button onclick="clearChat()" style="background:transparent;border:1px solid var(--danger);color:var(--danger);padding:4px 12px;border-radius:6px;cursor:pointer;">🗑️ پاک کردن</button>
            </div>
            <div class="chat-box" id="chatBox">
                ${history || '<div style="color:var(--text-secondary);text-align:center;padding:40px;">هنوز پیامی ارسال نشده</div>'}
            </div>
            <div class="chat-input-area">
                <input type="text" id="userInput" placeholder="پیام خود را بنویسید..." onkeydown="if(event.key==='Enter') sendMessage()">
                <button onclick="sendMessage()" id="sendBtn">🚀 ارسال</button>
                <button onclick="toggleVoice()" class="voice-btn" id="voiceBtn">🎤</button>
                <button onclick="stopGeneration()" id="stopBtn" style="display:none;background:var(--danger);">⏹ توقف</button>
            </div>
        </div>
    `;
};

// متغیرهای سراسری برای ماژول چت
let isRecording = false;
let recognition = null;

window.sendMessage = function() {
    const input = document.getElementById('userInput');
    const msg = input.value.trim();
    if (!msg || window.app.state.isStreaming) return;

    // اضافه کردن پیام کاربر
    window.app.state.chatHistory.push({ role: 'user', content: msg });
    window.app.updateState({ chatHistory: window.app.state.chatHistory });
    input.value = '';
    renderChat();

    // آماده‌سازی برای استریم
    window.app.state.isStreaming = true;
    document.getElementById('sendBtn').disabled = true;
    document.getElementById('stopBtn').style.display = 'inline-block';

    // ایجاد AbortController
    window.app.state.abortController = new AbortController();

    // انتخاب endpoint بر اساس حالت
    const isOffline = window.app.state.mode === 'offline';
    const url = isOffline 
        ? 'http://localhost:8080/v1/chat/completions'
        : 'https://api.openai.com/v1/chat/completions';

    const headers = {
        'Content-Type': 'application/json'
    };
    if (!isOffline) {
        headers['Authorization'] = `Bearer ${window.app.state.apiKey}`;
    }

    const messages = [
        { role: 'system', content: window.app.state.params.systemPrompt },
        ...window.app.state.chatHistory.map(m => ({ role: m.role, content: m.content }))
    ];

    fetch(url, {
        method: 'POST',
        headers: headers,
        body: JSON.stringify({
            model: isOffline ? 'local' : 'gpt-3.5-turbo',
            messages: messages,
            temperature: window.app.state.params.temperature,
            top_p: window.app.state.params.top_p,
            max_tokens: window.app.state.params.max_tokens,
            stream: true
        }),
        signal: window.app.state.abortController.signal
    })
    .then(response => {
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        let buffer = '';
        let assistantMsg = '';

        // اضافه کردن جایگاه برای پاسخ
        window.app.state.chatHistory.push({ role: 'assistant', content: '' });
        const lastIndex = window.app.state.chatHistory.length - 1;
        window.app.updateState({ chatHistory: window.app.state.chatHistory });

        function readStream() {
            reader.read().then(({ done, value }) => {
                if (done) {
                    finishStream(lastIndex);
                    return;
                }
                buffer += decoder.decode(value, { stream: true });
                const lines = buffer.split('\n');
                buffer = lines.pop() || '';

                for (const line of lines) {
                    if (line.startsWith('data: ')) {
                        const data = line.slice(6).trim();
                        if (data === '[DONE]') {
                            finishStream(lastIndex);
                            return;
                        }
                        try {
                            const json = JSON.parse(data);
                            const content = json.choices?.[0]?.delta?.content || '';
                            if (content) {
                                assistantMsg += content;
                                window.app.state.chatHistory[lastIndex].content = assistantMsg;
                                // رندر زنده
                                renderChat();
                            }
                        } catch (e) {
                            // خطای JSON رو نادیده بگیر
                        }
                    }
                }
                readStream();
            }).catch(err => {
                if (err.name === 'AbortError') {
                    console.log('تولید متوقف شد');
                } else {
                    console.error('خطا:', err);
                }
                finishStream(lastIndex);
            });
        }
        readStream();
    })
    .catch(err => {
        if (err.name === 'AbortError') {
            console.log('تولید متوقف شد');
        } else {
            alert('خطا در ارتباط با سرور: ' + err.message);
            window.app.state.chatHistory.pop(); // حذف پاسخ خالی
            window.app.updateState({ chatHistory: window.app.state.chatHistory });
        }
        finishStream();
    });
};

function finishStream(index) {
    window.app.state.isStreaming = false;
    document.getElementById('sendBtn').disabled = false;
    document.getElementById('stopBtn').style.display = 'none';
    if (index !== undefined && window.app.state.chatHistory[index]?.content === '') {
        window.app.state.chatHistory.pop(); // حذف پاسخ خالی
        window.app.updateState({ chatHistory: window.app.state.chatHistory });
    }
    renderChat();
}

window.stopGeneration = function() {
    if (window.app.state.abortController) {
        window.app.state.abortController.abort();
        window.app.state.abortController = null;
    }
};

window.copyText = function(index) {
    const msg = window.app.state.chatHistory[parseInt(index)];
    if (msg) {
        navigator.clipboard?.writeText(msg.content) || alert('متن کپی شد');
    }
};

window.clearChat = function() {
    if (confirm('همه پیام‌ها پاک شوند؟')) {
        window.app.state.chatHistory = [];
        window.app.updateState({ chatHistory: [] });
        renderChat();
    }
};

window.toggleVoice = function() {
    if (!('webkitSpeechRecognition' in window) && !('SpeechRecognition' in window)) {
        alert('مرورگر از ورودی صوتی پشتیبانی نمی‌کند');
        return;
    }
    if (isRecording) {
        recognition?.stop();
        isRecording = false;
        document.getElementById('voiceBtn').classList.remove('recording');
        return;
    }
    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
    recognition = new SpeechRecognition();
    recognition.lang = 'fa-IR';
    recognition.continuous = false;
    recognition.interimResults = true;

    recognition.onstart = function() {
        isRecording = true;
        document.getElementById('voiceBtn').classList.add('recording');
    };
    recognition.onresult = function(event) {
        const input = document.getElementById('userInput');
        let final = '';
        for (let i = event.resultIndex; i < event.results.length; i++) {
            if (event.results[i].isFinal) {
                final += event.results[i][0].transcript;
            }
        }
        if (final) {
            input.value = final;
            // ارسال خودکار
            setTimeout(() => window.sendMessage(), 300);
        }
    };
    recognition.onend = function() {
        isRecording = false;
        document.getElementById('voiceBtn').classList.remove('recording');
    };
    recognition.start();
};

function renderChat() {
    const box = document.getElementById('chatBox');
    if (!box) return;
    const history = window.app.state.chatHistory.map((msg, i) => `
        <div class="msg ${msg.role}">
            <div class="role-label">${msg.role === 'user' ? 'شما' : 'دستیار'}</div>
            ${msg.content || '<span class="streaming-cursor"></span>'}
            ${msg.content ? `<div class="msg-actions"><button onclick="copyText('${i}')">📋</button></div>` : ''}
        </div>
    `).join('');
    box.innerHTML = history || '<div style="color:var(--text-secondary);text-align:center;padding:40px;">هنوز پیامی ارسال نشده</div>';
    box.scrollTop = box.scrollHeight;
}

export function init() {
    renderChat();
    document.getElementById('userInput')?.focus();
}
EOF

# ماژول تنظیمات
cat > "$PROJECT_DIR/modules/settings.js" << 'EOF'
export default function() {
    const p = window.app.state.params;
    return `
        <div class="settings-container">
            <div class="settings-group">
                <h3>🔌 حالت اتصال</h3>
                <label>حالت</label>
                <select id="modeSelect">
                    <option value="offline" ${window.app.state.mode === 'offline' ? 'selected' : ''}>📴 آفلاین (llama.cpp)</option>
                    <option value="online" ${window.app.state.mode === 'online' ? 'selected' : ''}>🌐 آنلاین (OpenAI)</option>
                </select>
                <label>آدرس سرور (آفلاین)</label>
                <input type="text" id="serverUrl" value="http://localhost:8080">
                <label>API Key (آنلاین)</label>
                <input type="password" id="apiKey" value="${window.app.state.apiKey || ''}" placeholder="sk-...">
            </div>

            <div class="settings-group">
                <h3>⚙️ پارامترهای مدل</h3>
                <label>دمای خلاقیت (Temperature): <span class="range-value" id="tempVal">${p.temperature}</span></label>
                <input type="range" id="temperature" min="0" max="2" step="0.1" value="${p.temperature}" oninput="document.getElementById('tempVal').textContent=this.value">

                <label>Top-P: <span class="range-value" id="topPVal">${p.top_p}</span></label>
                <input type="range" id="topP" min="0" max="1" step="0.05" value="${p.top_p}" oninput="document.getElementById('topPVal').textContent=this.value">

                <label>حداکثر توکن‌ها: <span class="range-value" id="maxTokensVal">${p.max_tokens}</span></label>
                <input type="range" id="maxTokens" min="50" max="4096" step="50" value="${p.max_tokens}" oninput="document.getElementById('maxTokensVal').textContent=this.value">

                <label>System Prompt</label>
                <textarea id="systemPrompt">${p.systemPrompt}</textarea>
            </div>

            <div class="settings-group" style="grid-column: 1 / -1;">
                <button onclick="saveAllSettings()" style="background:var(--accent);color:#fff;border:none;padding:12px 24px;border-radius:var(--radius);cursor:pointer;font-size:16px;font-weight:600;">💾 ذخیره همه تنظیمات</button>
            </div>
        </div>
    `;
};

window.saveAllSettings = function() {
    const mode = document.getElementById('modeSelect').value;
    const apiKey = document.getElementById('apiKey').value;
    const temp = parseFloat(document.getElementById('temperature').value);
    const topP = parseFloat(document.getElementById('topP').value);
    const maxTokens = parseInt(document.getElementById('maxTokens').value);
    const systemPrompt = document.getElementById('systemPrompt').value;

    window.app.updateState({
        mode: mode,
        apiKey: apiKey,
        params: {
            temperature: temp,
            top_p: topP,
            max_tokens: maxTokens,
            context_size: 2048,
            systemPrompt: systemPrompt
        }
    });
    alert('✅ تنظیمات ذخیره شد!');
};

export function init() {
    // تنظیم مقدار اولیه برای نمایش
}
EOF

# ماژول تاریخچه
cat > "$PROJECT_DIR/modules/history.js" << 'EOF'
export default function() {
    const history = window.app.state.chatHistory.length === 0 
        ? '<div style="color:var(--text-secondary);text-align:center;padding:40px;">هیچ چتی ذخیره نشده</div>'
        : `<div class="history-item" onclick="loadChat()">
            <div class="title">💬 مکالمه ${new Date().toLocaleDateString('fa-IR')}</div>
            <div class="date">${new Date().toLocaleTimeString('fa-IR')}</div>
            <div class="preview">${window.app.state.chatHistory.slice(0, 3).map(m => m.content).join(' | ')}</div>
            <button class="delete-btn" onclick="event.stopPropagation();clearChat()">🗑️ حذف</button>
           </div>`;

    return `
        <div>
            <h2>📜 تاریخچه چت‌ها</h2>
            <p style="color:var(--text-secondary);margin-bottom:16px;">${window.app.state.chatHistory.length} پیام ذخیره شده</p>
            ${history}
            <button onclick="exportChat()" style="margin-top:12px;background:var(--bg-secondary);border:1px solid var(--border);color:var(--text);padding:8px 16px;border-radius:var(--radius);cursor:pointer;">📤 خروجی JSON</button>
        </div>
    `;
};

window.loadChat = function() {
    window.app.navigate('chat');
};

window.exportChat = function() {
    const data = JSON.stringify(window.app.state.chatHistory, null, 2);
    const blob = new Blob([data], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `chat_${Date.now()}.json`;
    a.click();
    URL.revokeObjectURL(url);
};

window.clearChat = function() {
    if (confirm('همه چت‌ها پاک شوند؟')) {
        window.app.state.chatHistory = [];
        window.app.updateState({ chatHistory: [] });
        window.app.navigate('history');
    }
};
EOF

# ماژول مدل‌ها
cat > "$PROJECT_DIR/modules/models.js" << 'EOF'
export default function() {
    const models = JSON.parse(localStorage.getItem('models') || '[]');
    const list = models.length === 0 
        ? '<div style="color:var(--text-secondary);text-align:center;padding:40px;">هیچ مدلی نصب نیست</div>'
        : models.map(m => `
            <div class="model-card">
                <div class="info">
                    <div class="name">${m.name}</div>
                    <div class="size">${m.size || 'نامشخص'} • ${m.path || 'مسیر نامشخص'}</div>
                </div>
                <div class="actions">
                    <button class="load-btn" onclick="loadModel('${m.path}')">🔌 بارگذاری</button>
                    <button class="delete-btn" onclick="deleteModel('${m.path}')">🗑️</button>
                </div>
                ${m.downloading ? `<div class="progress"><div class="bar" style="width:${m.progress || 0}%"></div></div>` : ''}
            </div>
        `).join('');

    return `
        <div>
            <h2>📦 مدیریت مدل‌ها</h2>
            <div style="display:flex;gap:10px;margin:16px 0;flex-wrap:wrap;">
                <input type="text" id="modelName" placeholder="نام مدل (مثلاً: llama3)" style="flex:1;padding:10px;border:1px solid var(--border);border-radius:var(--radius);background:var(--bg-secondary);color:var(--text);">
                <input type="text" id="modelUrl" placeholder="لینک دانلود (HuggingFace)" style="flex:2;padding:10px;border:1px solid var(--border);border-radius:var(--radius);background:var(--bg-secondary);color:var(--text);">
                <button onclick="downloadModel()" style="background:var(--accent);color:#fff;border:none;padding:10px 20px;border-radius:var(--radius);cursor:pointer;">⬇️ دانلود</button>
            </div>
            ${list}
        </div>
    `;
};

window.loadModel = function(path) {
    window.app.updateState({ modelPath: path });
    alert(`✅ مدل از مسیر ${path} بارگذاری شد`);
    window.app.navigate('chat');
};

window.deleteModel = function(path) {
    if (confirm('مدل حذف شود؟')) {
        let models = JSON.parse(localStorage.getItem('models') || '[]');
        models = models.filter(m => m.path !== path);
        localStorage.setItem('models', JSON.stringify(models));
        window.app.navigate('models');
    }
};

window.downloadModel = function() {
    const name = document.getElementById('modelName').value.trim();
    const url = document.getElementById('modelUrl').value.trim();
    if (!name || !url) {
        alert('لطفاً نام و لینک مدل را وارد کنید');
        return;
    }
    alert('🚧 قابلیت دانلود در نسخه‌ی بعدی اضافه می‌شود.\nبرای حالا مدل را به صورت دستی در مسیر /storage/emulated/0/Models/ قرار دهید.');
};
EOF

# ماژول نقش‌ها
cat > "$PROJECT_DIR/modules/roles.js" << 'EOF'
export default function() {
    const roles = window.app.state.roles;
    const list = roles.length === 0 
        ? '<div style="color:var(--text-secondary);text-align:center;padding:40px;">هیچ نقشی تعریف نشده</div>'
        : roles.map(r => `
            <div class="role-card">
                <div class="info">
                    <div class="name">🎭 ${r.name}</div>
                    <div class="desc">${r.description || r.prompt?.slice(0, 80) + '...'}</div>
                </div>
                <div class="actions">
                    <button class="apply-btn" onclick="applyRole('${r.name}')">✅ اعمال</button>
                    <button class="delete-btn" onclick="deleteRole('${r.name}')">🗑️</button>
                </div>
            </div>
        `).join('');

    return `
        <div>
            <h2>🎭 مدیریت نقش‌ها</h2>
            <div style="display:flex;gap:10px;margin:16px 0;flex-wrap:wrap;">
                <input type="text" id="roleName" placeholder="نام نقش" style="flex:1;padding:10px;border:1px solid var(--border);border-radius:var(--radius);background:var(--bg-secondary);color:var(--text);">
                <textarea id="rolePrompt" placeholder="System Prompt برای این نقش..." style="flex:2;padding:10px;border:1px solid var(--border);border-radius:var(--radius);background:var(--bg-secondary);color:var(--text);min-height:60px;"></textarea>
                <button onclick="addRole()" style="background:var(--accent);color:#fff;border:none;padding:10px 20px;border-radius:var(--radius);cursor:pointer;">➕ افزودن</button>
            </div>
            ${list}
            <button onclick="window.app.navigate('chat')" style="margin-top:12px;background:var(--bg-secondary);border:1px solid var(--border);color:var(--text);padding:8px 16px;border-radius:var(--radius);cursor:pointer;">💬 رفتن به چت</button>
        </div>
    `;
};

window.addRole = function() {
    const name = document.getElementById('roleName').value.trim();
    const prompt = document.getElementById('rolePrompt').value.trim();
    if (!name || !prompt) {
        alert('لطفاً نام و پرامپت نقش را وارد کنید');
        return;
    }
    const roles = window.app.state.roles;
    roles.push({ name, prompt });
    window.app.updateState({ roles });
    document.getElementById('roleName').value = '';
    document.getElementById('rolePrompt').value = '';
    window.app.navigate('roles');
};

window.applyRole = function(name) {
    const role = window.app.state.roles.find(r => r.name === name);
    if (role) {
        window.app.updateState({
            currentRole: name,
            params: { ...window.app.state.params, systemPrompt: role.prompt }
        });
        alert(`✅ نقش "${name}" اعمال شد`);
        window.app.navigate('chat');
    }
};

window.deleteRole = function(name) {
    if (confirm(`نقش "${name}" حذف شود؟`)) {
        let roles = window.app.state.roles.filter(r => r.name !== name);
        window.app.updateState({ roles });
        if (window.app.state.currentRole === name) {
            window.app.updateState({ currentRole: null });
        }
        window.app.navigate('roles');
    }
};
EOF

echo "✅ پروژه با موفقیت در پوشه $PROJECT_DIR ایجاد شد!"
echo "📂 برای اجرا:"
echo "   cd $PROJECT_DIR"
echo "   python3 -m http.server 8080"
echo "   سپس مرورگر را به http://localhost:8080 ببرید."