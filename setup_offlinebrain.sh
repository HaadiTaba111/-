#!/bin/bash

# ══════════════════════════════════════════════════════════════
#  🧠 OfflineBrain - اسکریپت نصب و راه‌اندازی کامل خودکار
#  نسخه: 2.0.0
#  تاریخ: 2024
# ══════════════════════════════════════════════════════════════

set -e  # خروج در صورت خطا

# رنگ‌ها
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# توابع کمکی
print_header() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║          🧠 OfflineBrain - مغز آفلاین فارسی‌زبان             ║"
    echo "║                                                              ║"
    echo "║     نصب و راه‌اندازی کامل خودکار - نسخه 2.0.0             ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_step() {
    echo -e "\n${BLUE}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# بررسی Python
check_python() {
    print_step "بررسی Python..."
    
    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 نصب نیست!"
        echo "لطفاً Python 3.8 یا بالاتر را نصب کنید:"
        echo "  Ubuntu/Debian: sudo apt install python3 python3-pip python3-venv"
        echo "  macOS: brew install python3"
        exit 1
    fi
    
    PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
    print_success "Python $PYTHON_VERSION یافت شد"
}

# ایجاد ساختار پوشه‌ها
create_structure() {
    print_step "ایجاد ساختار پروژه..."
    
    mkdir -p OfflineBrain/{weights,data/stories,logs,tokenizer_model,hotswap,tests,scripts,dashboard,android,docker}
    cd OfflineBrain
    
    print_success "ساختار پوشه‌ها ایجاد شد"
}

# ایجاد فایل‌های پایه
create_base_files() {
    print_step "ایجاد فایل‌های پایه..."

    # .gitignore
    cat > .gitignore << 'EOF'
__pycache__/
*.py[cod]
*$py.class
*.so
*.egg-info/
dist/
build/
venv/
.env
weights/*.pt
weights/*.onnx
weights/*.tflite
weights/*.gguf
data/*.db
data/*.json
logs/*.log
.DS_Store
*.swp
hotswap/*
!hotswap/.gitkeep
tokenizer_model/*.json
!tokenizer_model/.gitkeep
EOF

    # requirements.txt
    cat > requirements.txt << 'EOF'
torch>=2.0.0
numpy>=1.24.0
tokenizers>=0.13.0
fastapi>=0.100.0
uvicorn>=0.23.0
pydantic>=2.0.0
aiofiles>=23.0.0
requests>=2.31.0
sounddevice>=0.4.0
soundfile>=0.12.0
pyttsx3>=2.90
jinja2>=3.1.0
psutil>=5.9.0
websockets>=11.0.0
pytest>=7.4.0
huggingface-hub>=0.16.0
onnx>=1.14.0
onnxruntime>=1.15.0
EOF

    # __init__.py
    cat > __init__.py << 'EOF'
"""
OfflineBrain - مدل مغز آفلاین فارسی‌زبان
نسخه 2.0.0
"""

__version__ = "2.0.0"
__author__ = "OfflineBrain Team"

from .model import OfflineBrain
from .tokenizer import PersianTokenizer
from .chat import ChatBrain

__all__ = ["OfflineBrain", "PersianTokenizer", "ChatBrain"]
EOF

    touch hotswap/.gitkeep
    touch tokenizer_model/.gitkeep
    
    print_success "فایل‌های پایه ایجاد شد"
}

# ایجاد فایل config.py
create_config() {
    print_step "ایجاد فایل تنظیمات..."
    
    cat > config.py << 'EOFCONFIG'
"""config.py - تنظیمات کلی پروژه"""
import os
from pathlib import Path

BASE_DIR = Path(__file__).parent
WEIGHTS_DIR = BASE_DIR / "weights"
DATA_DIR = BASE_DIR / "data"
LOGS_DIR = BASE_DIR / "logs"
TOKENIZER_DIR = BASE_DIR / "tokenizer_model"
HOTSWAP_DIR = BASE_DIR / "hotswap"

for d in [WEIGHTS_DIR, DATA_DIR, LOGS_DIR, TOKENIZER_DIR, HOTSWAP_DIR]:
    d.mkdir(exist_ok=True)

class ModelConfig:
    vocab_size: int = 32000
    embed_dim: int = 256
    ff_dim: int = 1024
    num_heads: int = 4
    num_encoder_layers: int = 4
    num_decoder_layers: int = 4
    max_seq_len: int = 512
    dropout: float = 0.1
    activation: str = "gelu"
    pad_token_id: int = 0
    bos_token_id: int = 1
    eos_token_id: int = 2

class TrainingConfig:
    epochs: int = 50
    batch_size: int = 32
    learning_rate: float = 3e-4
    weight_decay: float = 0.01
    warmup_steps: int = 1000
    max_grad_norm: float = 1.0
    save_every: int = 5
    eval_every: int = 1
    patience: int = 10

class ChatConfig:
    temperature: float = 0.7
    top_k: int = 50
    top_p: float = 0.9
    repetition_penalty: float = 1.1
    max_new_tokens: int = 128

class HuggingFaceConfig:
    model_id: str = "username/OfflineBrain-fa"
    auto_update: bool = False
    check_interval: int = 3600
EOFCONFIG

    print_success "فایل config.py ایجاد شد"
}

# ایجاد فایل model.py (نسخه خلاصه)
create_model() {
    print_step "ایجاد معماری مدل..."
    
    cat > model.py << 'EOFMODEL'
"""model.py - معماری مدل OfflineBrain"""
import math
import torch
import torch.nn as nn
import torch.nn.functional as F
from config import ModelConfig

class PositionalEncoding(nn.Module):
    def __init__(self, d_model: int, max_len: int = 512, dropout: float = 0.1):
        super().__init__()
        self.dropout = nn.Dropout(p=dropout)
        pe = torch.zeros(max_len, d_model)
        position = torch.arange(0, max_len, dtype=torch.float).unsqueeze(1)
        div_term = torch.exp(torch.arange(0, d_model, 2).float() * (-math.log(10000.0) / d_model))
        pe[:, 0::2] = torch.sin(position * div_term)
        pe[:, 1::2] = torch.cos(position * div_term)
        self.register_buffer("pe", pe.unsqueeze(0))

    def forward(self, x):
        x = x + self.pe[:, : x.size(1), :]
        return self.dropout(x)

class FeedForward(nn.Module):
    def __init__(self, d_model: int = 256, d_ff: int = 1024, dropout: float = 0.1):
        super().__init__()
        self.linear1 = nn.Linear(d_model, d_ff)
        self.linear2 = nn.Linear(d_ff, d_model)
        self.dropout = nn.Dropout(dropout)
        self.activation = nn.GELU()

    def forward(self, x):
        return self.linear2(self.dropout(self.activation(self.linear1(x))))

class EncoderBlock(nn.Module):
    def __init__(self, d_model: int = 256, d_ff: int = 1024, num_heads: int = 4, dropout: float = 0.1):
        super().__init__()
        self.self_attn = nn.MultiheadAttention(d_model, num_heads, dropout=dropout, batch_first=True)
        self.ffn = FeedForward(d_model, d_ff, dropout)
        self.norm1 = nn.LayerNorm(d_model)
        self.norm2 = nn.LayerNorm(d_model)
        self.dropout1 = nn.Dropout(dropout)
        self.dropout2 = nn.Dropout(dropout)

    def forward(self, x, src_mask=None):
        attn_out, _ = self.self_attn(x, x, x, attn_mask=src_mask)
        x = self.norm1(x + self.dropout1(attn_out))
        ffn_out = self.ffn(x)
        x = self.norm2(x + self.dropout2(ffn_out))
        return x

class DecoderBlock(nn.Module):
    def __init__(self, d_model: int = 256, d_ff: int = 1024, num_heads: int = 4, dropout: float = 0.1):
        super().__init__()
        self.self_attn = nn.MultiheadAttention(d_model, num_heads, dropout=dropout, batch_first=True)
        self.cross_attn = nn.MultiheadAttention(d_model, num_heads, dropout=dropout, batch_first=True)
        self.ffn = FeedForward(d_model, d_ff, dropout)
        self.norm1 = nn.LayerNorm(d_model)
        self.norm2 = nn.LayerNorm(d_model)
        self.norm3 = nn.LayerNorm(d_model)
        self.dropout1 = nn.Dropout(dropout)
        self.dropout2 = nn.Dropout(dropout)
        self.dropout3 = nn.Dropout(dropout)

    def forward(self, x, enc_output, tgt_mask=None, memory_mask=None):
        attn_out, _ = self.self_attn(x, x, x, attn_mask=tgt_mask)
        x = self.norm1(x + self.dropout1(attn_out))
        cross_out, _ = self.cross_attn(x, enc_output, enc_output, attn_mask=memory_mask)
        x = self.norm2(x + self.dropout2(cross_out))
        ffn_out = self.ffn(x)
        x = self.norm3(x + self.dropout3(ffn_out))
        return x

class MHABottleneck(nn.Module):
    def __init__(self, d_model: int = 256, num_heads: int = 4, dropout: float = 0.1, num_layers: int = 2):
        super().__init__()
        self.layers = nn.ModuleList([
            nn.MultiheadAttention(d_model, num_heads, dropout=dropout, batch_first=True)
            for _ in range(num_layers)
        ])
        self.norms = nn.ModuleList([nn.LayerNorm(d_model) for _ in range(num_layers)])
        self.dropouts = nn.ModuleList([nn.Dropout(dropout) for _ in range(num_layers)])
        self.latent_proj = nn.Linear(d_model, d_model)

    def forward(self, x):
        attn_weights_list = []
        for attn, norm, drop in zip(self.layers, self.norms, self.dropouts):
            attn_out, attn_weights = attn(x, x, x)
            x = norm(x + drop(attn_out))
            attn_weights_list.append(attn_weights)
        latent = self.latent_proj(x)
        return latent, attn_weights_list

class OfflineBrain(nn.Module):
    def __init__(self, config: ModelConfig = None):
        super().__init__()
        if config is None:
            config = ModelConfig()
        self.config = config
        self.d_model = config.embed_dim

        self.token_embedding = nn.Embedding(config.vocab_size, config.embed_dim, padding_idx=config.pad_token_id)
        self.positional_encoding = PositionalEncoding(config.embed_dim, config.max_seq_len, config.dropout)
        
        self.encoder_layers = nn.ModuleList([
            EncoderBlock(config.embed_dim, config.ff_dim, config.num_heads, config.dropout)
            for _ in range(config.num_encoder_layers)
        ])
        
        self.bottleneck = MHABottleneck(config.embed_dim, config.num_heads, config.dropout)
        
        self.decoder_layers = nn.ModuleList([
            DecoderBlock(config.embed_dim, config.ff_dim, config.num_heads, config.dropout)
            for _ in range(config.num_decoder_layers)
        ])
        
        self.enc_norm = nn.LayerNorm(config.embed_dim)
        self.dec_norm = nn.LayerNorm(config.embed_dim)
        self.output_projection = nn.Linear(config.embed_dim, config.vocab_size)
        self.output_projection.weight = self.token_embedding.weight
        
        self._init_weights()

    def _init_weights(self):
        for p in self.parameters():
            if p.dim() > 1:
                nn.init.xavier_uniform_(p)

    def generate_causal_mask(self, size: int, device):
        mask = torch.triu(torch.ones(size, size, device=device), diagonal=1).bool()
        return mask

    def encode(self, src, src_mask=None):
        x = self.token_embedding(src) * math.sqrt(self.d_model)
        x = self.positional_encoding(x)
        for layer in self.encoder_layers:
            x = layer(x, src_mask)
        latent, bottleneck_attn = self.bottleneck(x)
        latent = self.enc_norm(latent)
        return latent, bottleneck_attn

    def decode(self, tgt, enc_output, tgt_mask=None, memory_mask=None):
        x = self.token_embedding(tgt) * math.sqrt(self.d_model)
        x = self.positional_encoding(x)
        if tgt_mask is None:
            tgt_mask = self.generate_causal_mask(tgt.size(1), tgt.device)
        for layer in self.decoder_layers:
            x = layer(x, enc_output, tgt_mask)
        x = self.dec_norm(x)
        logits = self.output_projection(x)
        return logits

    def forward(self, src, tgt, src_mask=None, tgt_mask=None):
        enc_output, bottleneck_attn = self.encode(src, src_mask)
        logits = self.decode(tgt, enc_output, tgt_mask)
        return logits, enc_output, bottleneck_attn

    def count_parameters(self):
        return sum(p.numel() for p in self.parameters() if p.requires_grad)

    @classmethod
    def from_pretrained(cls, path: str, config: ModelConfig = None):
        if config is None:
            config = ModelConfig()
        model = cls(config)
        state_dict = torch.load(path, map_location="cpu")
        if isinstance(state_dict, dict) and "model_state_dict" in state_dict:
            model.load_state_dict(state_dict["model_state_dict"])
        else:
            model.load_state_dict(state_dict)
        return model
EOFMODEL

    print_success "فایل model.py ایجاد شد"
}

# ایجاد tokenizer.py (ساده شده)
create_tokenizer() {
    print_step "ایجاد توکنایزر..."
    
    cat > tokenizer.py << 'EOFTOK'
"""tokenizer.py - توکنایزر ساده فارسی"""
import json
from typing import List

class PersianTokenizer:
    PAD_TOKEN = "[PAD]"
    BOS_TOKEN = "[BOS]"
    EOS_TOKEN = "[EOS]"
    UNK_TOKEN = "[UNK]"
    SEP_TOKEN = "[SEP]"
    SPECIAL_TOKENS = [PAD_TOKEN, BOS_TOKEN, EOS_TOKEN, UNK_TOKEN, SEP_TOKEN]

    def __init__(self, vocab_size: int = 32000):
        self.vocab_size = vocab_size
        self.pad_token_id = 0
        self.bos_token_id = 1
        self.eos_token_id = 2
        self.unk_token_id = 3
        self.sep_token_id = 4
        self._char_map = {}
        self._reverse_char_map = {}
        self._build_char_map()

    def _build_char_map(self):
        persian = "ابپتثجچحخدذرزژسشصضطظعغفقکگلمنوهی"
        digits = "۰۱۲۳۴۵۶۷۸۹0123456789"
        punct = "،.؟!؛:«»()[]{}/-–— \t\n"
        latin = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
        all_chars = self.SPECIAL_TOKENS + list(persian + digits + punct + latin)
        self._char_map = {char: idx for idx, char in enumerate(all_chars)}
        self._reverse_char_map = {idx: char for char, idx in self._char_map.items()}
        self.vocab_size = len(self._char_map)

    def encode(self, text: str, add_special: bool = True) -> List[int]:
        ids = []
        for char in text:
            ids.append(self._char_map.get(char, self.unk_token_id))
        if add_special:
            ids = [self.bos_token_id] + ids + [self.eos_token_id]
        return ids

    def decode(self, ids: List[int], skip_special: bool = True) -> str:
        text = []
        for token_id in ids:
            if skip_special and token_id < len(self.SPECIAL_TOKENS):
                continue
            if token_id in self._reverse_char_map:
                text.append(self._reverse_char_map[token_id])
        return "".join(text)

    def save(self, path: str):
        data = {"char_map": self._char_map, "vocab_size": self.vocab_size}
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

    def load(self, path: str):
        with open(path, 'r', encoding='utf-8') as f:
            data = json.load(f)
        self._char_map = data["char_map"]
        self._reverse_char_map = {int(v): k for k, v in self._char_map.items()}
        self.vocab_size = data["vocab_size"]

    @property
    def vocab(self):
        return self._char_map
EOFTOK

    print_success "فایل tokenizer.py ایجاد شد"
}

# ایجاد chat.py (ساده شده)
create_chat() {
    print_step "ایجاد رابط چت..."
    
    cat > chat.py << 'EOFCHAT'
"""chat.py - رابط چت"""
import torch
import torch.nn.functional as F
from pathlib import Path
from config import ModelConfig, ChatConfig
from model import OfflineBrain
from tokenizer import PersianTokenizer

class ChatBrain:
    def __init__(self, model_path: str = None, tokenizer_path: str = None, device: str = None):
        self.device = device or ("cuda" if torch.cuda.is_available() else "cpu")
        self.chat_config = ChatConfig()
        self.model_config = ModelConfig()
        self.model = OfflineBrain(self.model_config)
        
        if model_path and Path(model_path).exists():
            checkpoint = torch.load(model_path, map_location="cpu")
            if isinstance(checkpoint, dict) and "model_state_dict" in checkpoint:
                self.model.load_state_dict(checkpoint["model_state_dict"])
            else:
                self.model.load_state_dict(checkpoint)
        
        self.model.to(self.device)
        self.model.eval()
        
        self.tokenizer = PersianTokenizer(self.model_config.vocab_size)
        if tokenizer_path and Path(tokenizer_path).exists():
            self.tokenizer.load(tokenizer_path)
        
        self.conversation_history = []

    def generate(self, prompt: str, max_new_tokens: int = None, temperature: float = None,
                 top_k: int = None, top_p: float = None, repetition_penalty: float = None):
        if max_new_tokens is None:
            max_new_tokens = self.chat_config.max_new_tokens
        if temperature is None:
            temperature = self.chat_config.temperature
        if top_k is None:
            top_k = self.chat_config.top_k
        if top_p is None:
            top_p = self.chat_config.top_p
        if repetition_penalty is None:
            repetition_penalty = self.chat_config.repetition_penalty

        input_ids = self.tokenizer.encode(prompt, add_special=False)
        src = torch.tensor([input_ids], dtype=torch.long, device=self.device)
        decoder_input = [self.tokenizer.bos_token_id]
        generated_tokens = []

        with torch.no_grad():
            for _ in range(max_new_tokens):
                tgt = torch.tensor([decoder_input], dtype=torch.long, device=self.device)
                logits, _, _ = self.model(src, tgt)
                next_logits = logits[0, -1, :]

                if generated_tokens:
                    for token_id in set(generated_tokens[-50:]):
                        if next_logits[token_id] > 0:
                            next_logits[token_id] /= repetition_penalty
                        else:
                            next_logits[token_id] *= repetition_penalty

                next_logits = next_logits / temperature

                if top_k > 0:
                    indices_to_remove = next_logits < torch.topk(next_logits, top_k)[0][-1]
                    next_logits[indices_to_remove] = float("-inf")

                probs = F.softmax(next_logits, dim=-1)
                next_token = torch.multinomial(probs, num_samples=1).item()

                if next_token == self.tokenizer.eos_token_id:
                    break

                generated_tokens.append(next_token)
                decoder_input.append(next_token)

        response = self.tokenizer.decode(generated_tokens)
        return response

    def chat(self, user_message: str):
        prompt = f"کاربر: {user_message}\nدستیار:"
        response = self.generate(prompt)
        self.conversation_history.append({"role": "user", "content": user_message})
        self.conversation_history.append({"role": "assistant", "content": response})
        return response

if __name__ == "__main__":
    print("🧠 OfflineBrain - چت ساده")
    print("=" * 50)
    brain = ChatBrain()
    while True:
        try:
            user_input = input("\n👤 شما: ").strip()
            if user_input in ["/quit", "/exit"]:
                print("👋 خداحافظ!")
                break
            response = brain.chat(user_input)
            print(f"\n🤖 هوش مصنوعی: {response}")
        except (EOFError, KeyboardInterrupt):
            print("\n👋 خداحافظ!")
            break
EOFCHAT

    print_success "فایل chat.py ایجاد شد"
}

# ایجاد داشبورد ساده
create_simple_dashboard() {
    print_step "ایجاد داشبورد ساده..."
    
    mkdir -p dashboard
    
    cat > dashboard/simple_app.py << 'EOFDASH'
"""داشبورد ساده"""
from fastapi import FastAPI
from fastapi.responses import HTMLResponse, JSONResponse
from pydantic import BaseModel
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from chat import ChatBrain
from config import WEIGHTS_DIR

app = FastAPI(title="OfflineBrain Dashboard")
brain = None

class ChatRequest(BaseModel):
    message: str
    temperature: float = 0.7

@app.on_event("startup")
async def startup():
    global brain
    try:
        model_path = str(WEIGHTS_DIR / "best_model.pt")
        brain = ChatBrain(model_path if os.path.exists(model_path) else None)
        print("✅ مدل بارگذاری شد")
    except Exception as e:
        print(f"⚠️ خطا: {e}")
        brain = ChatBrain()

@app.get("/", response_class=HTMLResponse)
async def home():
    return """
<!DOCTYPE html>
<html dir="rtl">
<head>
    <meta charset="UTF-8">
    <title>OfflineBrain</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: Arial; background: #1a1a2e; color: #fff; padding: 20px; }
        .container { max-width: 800px; margin: 0 auto; }
        h1 { color: #00d4ff; text-align: center; margin-bottom: 30px; }
        #messages { height: 400px; overflow-y: auto; padding: 20px; background: #0a0a1a; border-radius: 10px; margin-bottom: 20px; }
        .message { margin: 10px 0; padding: 10px; border-radius: 8px; }
        .user { background: #1a3a5c; text-align: left; }
        .bot { background: #2a1a3c; text-align: right; }
        #input-box { display: flex; gap: 10px; }
        input { flex: 1; padding: 12px; border-radius: 8px; border: 1px solid #333; background: #111; color: #fff; font-size: 16px; }
        button { padding: 12px 24px; border-radius: 8px; border: none; background: #00d4ff; color: #000; font-weight: bold; cursor: pointer; }
        button:hover { background: #00b8d4; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🧠 OfflineBrain</h1>
        <div id="messages"></div>
        <div id="input-box">
            <input id="input" type="text" placeholder="پیام خود را بنویسید..." onkeypress="if(event.key==='Enter') send()">
            <button onclick="send()">ارسال</button>
        </div>
    </div>
    <script>
        async function send() {
            const input = document.getElementById('input');
            const msg = input.value.trim();
            if (!msg) return;
            
            addMessage('user', msg);
            input.value = '';
            
            const res = await fetch('/api/chat', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({message: msg})
            });
            const data = await res.json();
            addMessage('bot', data.response);
        }
        
        function addMessage(role, text) {
            const div = document.createElement('div');
            div.className = 'message ' + role;
            div.textContent = (role === 'user' ? '👤 ' : '🤖 ') + text;
            document.getElementById('messages').appendChild(div);
            div.scrollIntoView();
        }
    </script>
</body>
</html>
"""

@app.post("/api/chat")
async def chat(req: ChatRequest):
    if brain is None:
        return JSONResponse({"error": "مدل بارگذاری نشده"}, status_code=503)
    try:
        response = brain.generate(req.message, temperature=req.temperature)
        return {"response": response}
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOFDASH

    print_success "داشبورد ساده ایجاد شد"
}

# ایجاد داده نمونه
create_sample_data() {
    print_step "ایجاد داده نمونه..."
    
    cat > data/sample_data.txt << 'EOFDATA'
سلام، حالت چطوره؟
خیلی ممنونم از لطفت
امروز هوا خیلی قشنگه
من عاشق شعر فارسی هستم
حافظ بزرگترین شاعر ایران است
برف امشب خیلی زیبا بود
کتاب جدیدی خواندم که جالب بود
می‌خواهم یادگیری ماشین یاد بگیرم
پایتون زبان برنامه‌نویسی محبوب است
هوش مصنوعی آینده را تغییر می‌دهد
داستان‌های فارسی خیلی زیبا هستند
نوروز جشن آغاز سال نو ایرانی است
EOFDATA

    print_success "داده نمونه ایجاد شد"
}

# نصب وابستگی‌ها
install_dependencies() {
    print_step "نصب وابستگی‌ها..."
    
    python3 -m venv venv
    source venv/bin/activate
    
    pip install --upgrade pip --quiet
    pip install -r requirements.txt --quiet
    
    print_success "وابستگی‌ها نصب شد"
}

# ایجاد اسکریپت‌های کمکی
create_helper_scripts() {
    print_step "ایجاد اسکریپت‌های کمکی..."
    
    # اسکریپت اجرای چت
    cat > run_chat.sh << 'EOFRUN'
#!/bin/bash
source venv/bin/activate
python chat.py
EOFRUN
    chmod +x run_chat.sh

    # اسکریپت اجرای داشبورد
    cat > run_dashboard.sh << 'EOFDASH'
#!/bin/bash
source venv/bin/activate
echo "🚀 راه‌اندازی داشبورد..."
echo "   URL: http://localhost:8000"
python dashboard/simple_app.py
EOFDASH
    chmod +x run_dashboard.sh

    # اسکریپت تست
    cat > test.sh << 'EOFTEST'
#!/bin/bash
source venv/bin/activate
python -c "
from model import OfflineBrain
from config import ModelConfig
config = ModelConfig()
model = OfflineBrain(config)
print(f'✅ مدل ساخته شد: {model.count_parameters():,} پارامتر')
print(f'✅ حجم تقریبی: {model.count_parameters() * 4 / (1024**2):.1f} MB')
"
EOFTEST
    chmod +x test.sh

    print_success "اسکریپت‌های کمکی ایجاد شد"
}

# ایجاد README
create_readme() {
    print_step "ایجاد فایل README..."
    
    cat > README.md << 'EOFREADME'
# 🧠 OfflineBrain - مغز آفلاین فارسی‌زبان

## نصب شده! ✅

### ساختار پروژه