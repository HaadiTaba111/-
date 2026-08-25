#!/bin/bash
# ============================================================
# Jarvis Two-Brain System - Progressive Setup
# Each run adds next layer | Total: 6 phases
# ============================================================

set -e

# ─── Colors ─────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# ─── State ──────────────────────────────────────────────────
STATE_FILE="$HOME/.jarvis_state"
CURRENT_PHASE=0
[ -f "$STATE_FILE" ] && source "$STATE_FILE"
NEXT_PHASE=$((CURRENT_PHASE + 1))

# ─── Banner ─────────────────────────────────────────────────
clear
echo -e "${CYAN}"
cat << 'EOF'
     ██╗ █████╗ ██████╗ ██╗   ██╗██╗███████╗
     ██║██╔══██╗██╔══██╗██║   ██║██║██╔════╝
     ██║███████║██████╔╝██║   ██║██║███████╗
██   ██║██╔══██║██╔══██╗╚██╗ ██╔╝██║╚════██║
╚█████╔╝██║  ██║██║  ██║ ╚████╔╝ ██║███████║
 ╚════╝ ╚═╝  ╚═╝╚═╝  ╚═╝  ╚═══╝  ╚═╝╚══════╝
        Two-Brain System — Progressive Setup
EOF
echo -e "${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Phase done: ${GREEN}${CURRENT_PHASE}/5${NC} | Next: ${MAGENTA}Phase ${NEXT_PHASE}${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# ════════════════════════════════════════════════════════════
# PHASE 0 — Base: Config + Structure + Dependencies
# ════════════════════════════════════════════════════════════
phase_0() {
    echo -e "${MAGENTA}▶ PHASE 0: Base Setup${NC}\n"

    # Defaults
    DEF_DIR="$HOME/jarvis"
    DEF_HOST="http://localhost"
    DEF_PORT="1234"
    DEF_MODEL="qwen3-4b-instruct-2507-q4_k_m"
    DEF_DASH="7860"
    DEF_TOKENS="6000"
    DEF_STEPS="10"

    read -p "$(echo -e ${BLUE}"Project dir [$DEF_DIR]: "${NC})"         P_DIR;    P_DIR="${P_DIR:-$DEF_DIR}"
    read -p "$(echo -e ${BLUE}"LM Studio host [$DEF_HOST]: "${NC})"     P_HOST;   P_HOST="${P_HOST:-$DEF_HOST}"
    read -p "$(echo -e ${BLUE}"LM Studio port [$DEF_PORT]: "${NC})"     P_PORT;   P_PORT="${P_PORT:-$DEF_PORT}"
    read -p "$(echo -e ${BLUE}"Model name [$DEF_MODEL]: "${NC})"        P_MODEL;  P_MODEL="${P_MODEL:-$DEF_MODEL}"
    read -p "$(echo -e ${BLUE}"Dashboard port [$DEF_DASH]: "${NC})"     P_DASH;   P_DASH="${P_DASH:-$DEF_DASH}"
    read -p "$(echo -e ${BLUE}"Max tokens [$DEF_TOKENS]: "${NC})"       P_TOKENS; P_TOKENS="${P_TOKENS:-$DEF_TOKENS}"
    read -p "$(echo -e ${BLUE}"Max steps/plan [$DEF_STEPS]: "${NC})"    P_STEPS;  P_STEPS="${P_STEPS:-$DEF_STEPS}"

    echo -e "\n${CYAN}[1/4] System packages...${NC}"
    sudo apt-get update -qq
    sudo apt-get install -y -qq python3 python3-pip python3-venv \
        curl git build-essential libffi-dev libssl-dev
    echo -e "${GREEN}✓ Packages OK${NC}"

    echo -e "${CYAN}[2/4] Folder structure...${NC}"
    mkdir -p "$P_DIR"/{src,logs/{brain,agent,dashboard},memory/{l1_exact,l2_vector,l3_supervisor},dashboard/{static,templates},tests,configs,workspace}
    echo -e "${GREEN}✓ Structure OK${NC}"

    echo -e "${CYAN}[3/4] Python venv...${NC}"
    python3 -m venv "$P_DIR/.venv"
    source "$P_DIR/.venv/bin/activate"
    pip install --upgrade pip -q

    cat > "$P_DIR/requirements.txt" << 'REQ'
fastapi==0.111.0
uvicorn[standard]==0.30.1
websockets==12.0
httpx==0.27.0
pydantic==2.7.1
python-dotenv==1.0.1
jinja2==3.1.4
python-multipart==0.0.9
aiofiles==23.2.1
rich==13.7.1
chromadb==0.5.0
sentence-transformers==3.0.1
tenacity==8.3.0
orjson==3.10.3
loguru==0.7.2
REQ

    pip install -r "$P_DIR/requirements.txt" -q
    echo -e "${GREEN}✓ Python deps OK${NC}"

    echo -e "${CYAN}[4/4] .env file...${NC}"
    cat > "$P_DIR/.env" << ENV
# Jarvis Two-Brain System — Config
LM_STUDIO_HOST=${P_HOST}
LM_STUDIO_PORT=${P_PORT}
LM_STUDIO_URL=${P_HOST}:${P_PORT}/v1
MODEL_NAME=${P_MODEL}
MAX_OUTPUT_TOKENS=${P_TOKENS}
MAX_STEPS_PER_PLAN=${P_STEPS}
TEMPERATURE=0.2
TOP_P=0.95
DASHBOARD_HOST=0.0.0.0
DASHBOARD_PORT=${P_DASH}
DASHBOARD_RELOAD=false
MEMORY_L1_PATH=${P_DIR}/memory/l1_exact
MEMORY_L2_PATH=${P_DIR}/memory/l2_vector
MEMORY_L3_PATH=${P_DIR}/memory/l3_supervisor
L2_COLLECTION_NAME=jarvis_semantic
L2_TOP_K=3
LOG_LEVEL=INFO
LOG_PATH=${P_DIR}/logs
PROJECT_DIR=${P_DIR}
ENV
    echo -e "${GREEN}✓ .env OK${NC}"

    # Save state
    cat > "$STATE_FILE" << STATE
CURRENT_PHASE=0
PROJECT_DIR=${P_DIR}
LM_HOST=${P_HOST}
LM_PORT=${P_PORT}
MODEL_NAME=${P_MODEL}
DASHBOARD_PORT=${P_DASH}
MAX_TOKENS=${P_TOKENS}
MAX_STEPS=${P_STEPS}
STATE

    _done 0 "Phase 1 → Brain Core (schemas + memory + brain)"
}

# ════════════════════════════════════════════════════════════
# PHASE 1 — Brain Core: schemas + memory + brain
# ════════════════════════════════════════════════════════════
phase_1() {
    echo -e "${MAGENTA}▶ PHASE 1: Brain Core${NC}\n"
    source "$STATE_FILE"
    source "$PROJECT_DIR/.venv/bin/activate"

    # ── schemas.py ──────────────────────────────────────────
    cat > "$PROJECT_DIR/src/schemas.py" << 'EOF'
from pydantic import BaseModel, Field
from typing import Optional, List, Any
from enum import Enum

class OutputType(str, Enum):
    PLAN = "PLAN"
    FIX  = "FIX"
    KNOWLEDGE = "KNOWLEDGE"

class MemoryLevel(str, Enum):
    L1   = "L1"
    L2   = "L2"
    L3   = "L3"
    NONE = "NONE"

class PlanStep(BaseModel):
    step_id: int
    action:  str
    command: str
    expected_output: str
    safe: bool = True
    requires_confirmation: bool = False

class PlanOutput(BaseModel):
    type:        str = "PLAN"
    task_id:     str
    part:        int = 1
    total_parts: int = 1
    goal:        str
    steps:       List[PlanStep]
    memory_used: MemoryLevel = MemoryLevel.NONE

class FixOutput(BaseModel):
    type:          str = "FIX"
    task_id:       str
    error_summary: str
    root_cause:    str
    fix_steps:     List[PlanStep]
    memory_used:   MemoryLevel = MemoryLevel.NONE

class KnowledgeOutput(BaseModel):
    type:        str = "KNOWLEDGE"
    task_id:     str
    question:    str
    answer:      str
    confidence:  float = Field(ge=0.0, le=1.0)
    memory_used: MemoryLevel = MemoryLevel.NONE

class SuccessReport(BaseModel):
    report_type: str = "SUCCESS"
    task_id:     str
    step_id:     int
    output:      str
    duration_ms: Optional[int] = None

class ErrorReport(BaseModel):
    report_type: str = "ERROR"
    task_id:     str
    step_id:     int
    command:     str
    error_code:  Optional[int] = None
    stderr:      str
    stdout:      Optional[str] = None
    duration_ms: Optional[int] = None

class MemoryResult(BaseModel):
    report_type: str = "MEMORY_RESULT"
    task_id:     str
    level:       MemoryLevel
    found:       bool
    data:        Optional[Any]   = None
    similarity:  Optional[float] = None

class UserRequest(BaseModel):
    message: str
    task_id: Optional[str] = None

class JarvisConfig(BaseModel):
    lm_host:        str
    lm_port:        int
    model_name:     str
    max_tokens:     int
    max_steps:      int
    temperature:    float
    top_p:          float
    dashboard_port: int
EOF
    echo -e "${GREEN}✓ schemas.py${NC}"

    # ── memory.py ───────────────────────────────────────────
    cat > "$PROJECT_DIR/src/memory.py" << 'EOF'
import json, hashlib
from pathlib import Path
from typing import Optional
from loguru import logger

class MemorySystem:
    """
    L1 → Exact Fix  (JSON files, hash key)
    L2 → Semantic   (ChromaDB vector store)
    L3 → Supervisor (append-only JSONL log)
    Priority search: L1 → L2 → L3
    """
    def __init__(self, l1_path, l2_path, l3_path,
                 collection_name="jarvis_semantic", top_k=3):
        self.l1 = Path(l1_path);  self.l1.mkdir(parents=True, exist_ok=True)
        self.l2 = Path(l2_path);  self.l2.mkdir(parents=True, exist_ok=True)
        self.l3 = Path(l3_path);  self.l3.mkdir(parents=True, exist_ok=True)
        self.col_name = collection_name
        self.top_k    = top_k
        self._col     = None
        self._init_l2()

    def _init_l2(self):
        try:
            import chromadb
            client    = chromadb.PersistentClient(path=str(self.l2))
            self._col = client.get_or_create_collection(self.col_name)
            logger.info("L2 ChromaDB ready")
        except Exception as e:
            logger.warning(f"L2 unavailable: {e}")

    def _h(self, text: str) -> str:
        return hashlib.sha256(text.strip().lower().encode()).hexdigest()[:16]

    # ── L1 ──────────────────────────────────────────────────
    def l1_get(self, sig: str) -> Optional[dict]:
        p = self.l1 / f"{self._h(sig)}.json"
        if p.exists():
            logger.info(f"L1 HIT {self._h(sig)}")
            return json.loads(p.read_text())
        return None

    def l1_store(self, sig: str, data: dict):
        p = self.l1 / f"{self._h(sig)}.json"
        p.write_text(json.dumps(data, ensure_ascii=False, indent=2))
        logger.info(f"L1 STORE {self._h(sig)}")

    # ── L2 ──────────────────────────────────────────────────
    def l2_search(self, query: str) -> Optional[list]:
        if not self._col: return None
        try:
            r = self._col.query(query_texts=[query], n_results=self.top_k)
            if r and r['documents'] and r['documents'][0]:
                return [{"doc": d, "meta": m, "dist": x}
                        for d, m, x in zip(r['documents'][0],
                                           r['metadatas'][0],
                                           r['distances'][0])]
        except Exception as e:
            logger.error(f"L2 search: {e}")
        return None

    def l2_store(self, text: str, meta: dict):
        if not self._col: return
        try:
            self._col.upsert(documents=[text], metadatas=[meta],
                             ids=[self._h(text)])
        except Exception as e:
            logger.error(f"L2 store: {e}")

    # ── L3 ──────────────────────────────────────────────────
    def l3_log(self, event: dict):
        f = self.l3 / "supervisor.jsonl"
        with open(f, "a") as fp:
            fp.write(json.dumps(event, ensure_ascii=False) + "\n")

    def l3_patterns(self, limit=20) -> list:
        f = self.l3 / "supervisor.jsonl"
        if not f.exists(): return []
        lines = f.read_text().strip().split("\n")
        return [json.loads(l) for l in lines[-limit:] if l]

    # ── Priority Search: L1 → L2 → L3 ──────────────────────
    def search(self, query: str) -> dict:
        r = self.l1_get(query)
        if r: return {"level": "L1", "found": True, "data": r}
        r = self.l2_search(query)
        if r: return {"level": "L2", "found": True, "data": r}
        r = self.l3_patterns()
        if r: return {"level": "L3", "found": True, "data": r}
        return {"level": "NONE", "found": False, "data": None}

    # ── Stats ────────────────────────────────────────────────
    def stats(self) -> dict:
        l1c = len(list(self.l1.glob("*.json")))
        l3c = len(self.l3_patterns(9999))
        return {"l1_entries": l1c, "l2_collection": self.col_name, "l3_events": l3c}
EOF
    echo -e "${GREEN}✓ memory.py${NC}"

    # ── brain.py ────────────────────────────────────────────
    cat > "$PROJECT_DIR/src/brain.py" << 'EOF'
import json, uuid, re
from typing import Optional
from loguru import logger
from tenacity import retry, stop_after_attempt, wait_exponential
import httpx

from memory import MemorySystem
from schemas import ErrorReport, SuccessReport

SYSTEM_PROMPT = """\
You are Jarvis Brain — the planning core of a two-brain AI system.

ROLES
  Brain (you): plans tasks, fixes errors, answers questions.
  Agent: executes shell commands, reports SUCCESS or ERROR.

OUTPUT RULES
  - JSON keys/values: English only
  - Text outside JSON blocks: user language (Persian if user writes Persian)
  - Max output: {max_tokens} tokens
  - Max {max_steps} steps per PLAN part; split into parts if needed
  - NEVER emit dangerous commands (rm -rf /, mkfs, dd if=/dev/zero)
    without step safe=false AND requires_confirmation=true

OUTPUT FORMATS

1) PLAN
```json
{{
  "type": "PLAN",
  "task_id": "<uuid8>",
  "part": 1, "total_parts": 1,
  "goal": "<one-line goal>",
  "steps": [
{{
"step_id": 1,
"action": "<human label>",
"command": "<exact shell command, no placeholders>",
"expected_output": "<what success looks like>",
"safe": true,
"requires_confirmation": false
}}
  ],
  "memory_used": "NONE"
}}

2) FIX
json
{{
  "type": "FIX",
  "task_id": "<same id from error report>",
  "error_summary": "<short>",
  "root_cause": "<why>",
  "fix_steps": [ {{...same schema as steps...}} ],
  "memory_used": "L1|L2|L3|NONE"
}}

3) KNOWLEDGE
json
{{
  "type": "KNOWLEDGE",
  "task_id": "<uuid8>",
  "question": "<user question>",
  "answer": "<full answer>",
  "confidence": 0.95,
  "memory_used": "NONE"
}}

PLANNING RULES
  1 Atomic   — one command per step
  2 Complete — assume nothing pre-exists
  3 Explicit — no <placeholder> tokens
  4 Safe     — destructive ops: safe=false, requires_confirmation=true
  5 Deterministic — same input → same output
  6 Max {max_steps} steps per part

ERROR HANDLING  (memory priority L1→L2→L3)
  L1 hit  → apply fix directly (no new LLM call)
  L2 hit  → review & adapt similar fix
  L3 hit  → use as context hint, generate fresh fix
  No hit  → generate completely new fix; store result in L1

MEMORY RESULT BEHAVIOUR
  found=true  level=L1 → return stored fix as-is
  found=true  level=L2 → adapt to current context
  found=true  level=L3 → use as background context only
  found=false           → full new generation
"""

class JarvisBrain:
def __init__(self, config: dict, memory: MemorySystem):
self.cfg    = config
self.mem    = memory
self.url    = f"{config['lm_url']}/chat/completions"
self.prompt = SYSTEM_PROMPT.format(
max_tokens=config['max_tokens'],
max_steps=config['max_steps']
)

@retry(stop=stop_after_attempt(3),
wait=wait_exponential(min=1, max=8))
async def _llm(self, messages: list) -> str:
async with httpx.AsyncClient(timeout=120.0) as c:
r = await c.post(self.url, json={
"model":       self.cfg['model_name'],
"messages":    messages,
"max_tokens":  int(self.cfg['max_tokens']),
"temperature": float(self.cfg['temperature']),
"top_p":       float(self.cfg['top_p']),
"stream":      False
})
r.raise_for_status()
return r.json()['choices'][0]['message']['content']

def _parse(self, text: str) -> Optional[dict]:
m = re.search(r'
```(?:json)?\s*(\{.*?\})\s*
```', text, re.DOTALL)
if m:
try: return json.loads(m.group(1))
except: pass
try:
s = text.index('{'); e = text.rindex('}') + 1
return json.loads(text[s:e])
except: return None

async def think(self, user_msg: str,
task_id: Optional[str] = None) -> dict:
tid = task_id or uuid.uuid4().hex[:8]
mem = self.mem.search(user_msg)
logger.info(f"[{tid}] mem={mem['level']} found={mem['found']}")

# L1 exact hit → return immediately
if mem['found'] and mem['level'] == 'L1':
return {**mem['data'], "task_id": tid, "memory_used": "L1"}

msgs = [{"role": "system", "content": self.prompt}]

if mem['found']:
ctx = f"Memory context ({mem['level']}):\n{json.dumps(mem['data'], ensure_ascii=False)}"
msgs.append({"role": "user", "content": ctx})

msgs.append({"role": "user",
"content": f"Task-ID: {tid}\n\n{user_msg}"})

try:
raw    = await self._llm(msgs)
result = self._parse(raw) or {
"type": "KNOWLEDGE", "task_id": tid,
"question": user_msg, "answer": raw,
"confidence": 0.7
}
result["task_id"]     = tid
result["memory_used"] = mem['level']
self.mem.l3_log({"task_id": tid, "type": result.get("type"),
"mem": mem['level']})
return result
except Exception as e:
logger.error(f"Brain error: {e}")
return {"type": "ERROR", "task_id": tid, "error": str(e)}

async def fix(self, report: ErrorReport) -> dict:
sig = f"{report.command}:{report.stderr[:120]}"
mem = self.mem.search(sig)

# L1 hit
if mem['found'] and mem['level'] == 'L1':
logger.info(f"L1 fix for {report.task_id}")
return {**mem['data'], "task_id": report.task_id}

ctx = f"""ERROR REPORT
task_id : {report.task_id}
step_id : {report.step_id}
command : {report.command}
code    : {report.error_code}
stderr  : {report.stderr}
stdout  : {report.stdout or '—'}
memory  : level={mem['level']} found={mem['found']}
{f"context: {json.dumps(mem['data'])}" if mem['found'] else ''}

Generate a FIX response JSON."""

msgs = [{"role": "system", "content": self.prompt},
{"role": "user",   "content": ctx}]
raw    = await self._llm(msgs)
result = self._parse(raw) or {}
result.update({"type": "FIX", "task_id": report.task_id})

if not mem['found']:
self.mem.l1_store(sig, result)

return result

async def on_success(self, report: SuccessReport):
self.mem.l2_store(
text=f"task={report.task_id} step={report.step_id} out={report.output[:200]}",
meta={"task_id": report.task_id, "step_id": report.step_id}
)
self.mem.l3_log({"event": "SUCCESS",
"task_id": report.task_id,
"step_id": report.step_id})
EOF
echo -e "${GREEN}✓ brain.py${NC}"

_save_phase 1
_done 1 "Phase 2 → Agent (executor)"
}

# ════════════════════════════════════════════════════════════
# PHASE 2 — Agent: executor
# ════════════════════════════════════════════════════════════
phase_2() {
echo -e "${MAGENTA}▶ PHASE 2: Agent Executor${NC}\n"
source "$STATE_FILE"
source "$PROJECT_DIR/.venv/bin/activate"

cat > "$PROJECT_DIR/src/agent.py" << 'EOF'
import asyncio, time
from typing import Callable, Optional
from loguru import logger
from schemas import PlanStep, SuccessReport, ErrorReport

class JarvisAgent:
"""
Runs plan steps from Brain.
Calls on_success / on_error callbacks.
"""
def __init__(self,
on_success:  Callable,
on_error:    Callable,
on_confirm:  Optional[Callable] = None,
workdir: str = "/tmp/jarvis_ws"):
self.on_success = on_success
self.on_error   = on_error
self.on_confirm = on_confirm
self.workdir    = workdir
self._live      = False
self._task_id   = None

# ── Public ───────────────────────────────────────────────
async def run_plan(self, task_id: str, steps: list,
broadcast: Optional[Callable] = None):
self._live    = True
self._task_id = task_id

for raw in steps:
if not self._live: break
step = PlanStep(**raw) if isinstance(raw, dict) else raw

if broadcast:
await broadcast({"event": "STEP_START",
"task_id": task_id,
"step_id": step.step_id,
"action":  step.action,
"command": step.command})

# Dangerous step → ask user
if step.requires_confirmation and self.on_confirm:
ok = await self.on_confirm(step)
if not ok:
if broadcast:
await broadcast({"event": "STEP_SKIPPED",
"step_id": step.step_id})
continue

res = await self._exec(step.command)

if res['ok']:
rpt = SuccessReport(task_id=task_id,
step_id=step.step_id,
output=res['stdout'],
duration_ms=res['ms'])
await self.on_success(rpt)
if broadcast:
await broadcast({"event": "STEP_SUCCESS",
"step_id": step.step_id,
"output":  res['stdout']})
else:
rpt = ErrorReport(task_id=task_id,
step_id=step.step_id,
command=step.command,
error_code=res['code'],
stderr=res['stderr'],
stdout=res['stdout'],
duration_ms=res['ms'])
fix = await self.on_error(rpt)
if broadcast:
await broadcast({"event": "STEP_ERROR",
"step_id": step.step_id,
"stderr":  res['stderr'],
"fix":     fix})
break   # Brain will send new plan

self._live    = False
self._task_id = None

def stop(self):
self._live = False
logger.warning("Agent stopped by user")

@property
def running(self): return self._live
@property
def task_id(self):  return self._task_id

# ── Internal ─────────────────────────────────────────────
async def _exec(self, cmd: str) -> dict:
t0 = time.time()
try:
proc = await asyncio.create_subprocess_shell(
cmd,
stdout=asyncio.subprocess.PIPE,
stderr=asyncio.subprocess.PIPE,
cwd=self.workdir
)
out, err = await asyncio.wait_for(
proc.communicate(), timeout=300
)
ms = int((time.time() - t0) * 1000)
return {"ok":     proc.returncode == 0,
"code":   proc.returncode,
"stdout": out.decode('utf-8', errors='replace').strip(),
"stderr": err.decode('utf-8', errors='replace').strip(),
"ms":     ms}
except asyncio.TimeoutError:
return {"ok": False, "code": -1,
"stdout": "", "stderr": "Timeout >300s", "ms": 300000}
except Exception as e:
return {"ok": False, "code": -1,
"stdout": "", "stderr": str(e),
"ms": int((time.time() - t0)*1000)}
EOF
echo -e "${GREEN}✓ agent.py${NC}"

_save_phase 2
_done 2 "Phase 3 → FastAPI server + WebSocket"
}

# ════════════════════════════════════════════════════════════
# PHASE 3 — Server: FastAPI + WebSocket
# ════════════════════════════════════════════════════════════
phase_3() {
echo -e "${MAGENTA}▶ PHASE 3: FastAPI Server${NC}\n"
source "$STATE_FILE"
source "$PROJECT_DIR/.venv/bin/activate"

cat > "$PROJECT_DIR/src/server.py" << 'EOF'
import os, json, asyncio
from pathlib import Path
from contextlib import asynccontextmanager
from typing import Optional

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.requests import Request
from fastapi.responses import JSONResponse
from loguru import logger
from dotenv import load_dotenv
import httpx

load_dotenv()

from brain   import JarvisBrain
from agent   import JarvisAgent
from memory  import MemorySystem
from schemas import UserRequest, JarvisConfig, ErrorReport, SuccessReport

# ── Singleton state ──────────────────────────────────────────
class _S:
brain:   Optional[JarvisBrain] = None
agent:   Optional[JarvisAgent] = None
memory:  Optional[MemorySystem] = None
sockets: list = []
log:     list = []
cfg:     dict = {}

S = _S()

# ── Helpers ──────────────────────────────────────────────────
async def broadcast(ev: dict):
S.log.append(ev)
if len(S.log) > 500: S.log = S.log[-500:]
dead = []
for ws in S.sockets:
try:    await ws.send_json(ev)
except: dead.append(ws)
for ws in dead: S.sockets.remove(ws)

def _load_cfg() -> dict:
return {
"lm_url":      os.getenv("LM_STUDIO_URL", "http://localhost:1234/v1"),
"model_name":  os.getenv("MODEL_NAME", "qwen3-4b-instruct"),
"max_tokens":  int(os.getenv("MAX_OUTPUT_TOKENS", "6000")),
"max_steps":   int(os.getenv("MAX_STEPS_PER_PLAN", "10")),
"temperature": float(os.getenv("TEMPERATURE", "0.2")),
"top_p":       float(os.getenv("TOP_P", "0.95")),
"project_dir": os.getenv("PROJECT_DIR", str(Path.home()/"jarvis")),
}

def _boot(cfg: dict):
S.cfg    = cfg
S.memory = MemorySystem(
os.getenv("MEMORY_L1_PATH"),
os.getenv("MEMORY_L2_PATH"),
os.getenv("MEMORY_L3_PATH"),
os.getenv("L2_COLLECTION_NAME", "jarvis_semantic"),
int(os.getenv("L2_TOP_K", "3"))
)
S.brain = JarvisBrain(cfg, S.memory)

async def _ok(r: SuccessReport):
await S.brain.on_success(r)
await broadcast({"event": "SUCCESS", "data": r.model_dump()})

async def _err(r: ErrorReport):
fix = await S.brain.fix(r)
await broadcast({"event": "ERROR_FIX", "data": fix})
return fix

async def _confirm(step) -> bool:
await broadcast({"event": "CONFIRM_NEEDED", "step": step.model_dump()})
return False

S.agent = JarvisAgent(
on_success=_ok, on_error=_err, on_confirm=_confirm,
workdir=os.path.join(cfg['project_dir'], 'workspace')
)

@asynccontextmanager
async def lifespan(app: FastAPI):
_boot(_load_cfg())
logger.info("Jarvis ready")
yield

app = FastAPI(title="Jarvis Dashboard", lifespan=lifespan)

BASE = Path(__file__).parent.parent
app.mount("/static",
StaticFiles(directory=str(BASE/"dashboard/static")), name="static")
tpl = Jinja2Templates(directory=str(BASE/"dashboard/templates"))

# ── Routes ───────────────────────────────────────────────────
@app.get("/")
async def index(request: Request):
return tpl.TemplateResponse("index.html",
{"request": request, "cfg": S.cfg})

@app.get("/api/config")
async def get_cfg(): return S.cfg

@app.post("/api/config")
async def set_cfg(nc: JarvisConfig):
cfg = {
"lm_url":      f"{nc.lm_host}:{nc.lm_port}/v1",
"model_name":  nc.model_name,
"max_tokens":  nc.max_tokens,
"max_steps":   nc.max_steps,
"temperature": nc.temperature,
"top_p":       nc.top_p,
"project_dir": S.cfg.get("project_dir", str(Path.home()/"jarvis")),
}
_boot(cfg)
await broadcast({"event": "CONFIG_UPDATED", "cfg": cfg})
return {"ok": True}

@app.get("/api/models")
async def models():
base = S.cfg.get("lm_url","").replace("/v1","")
try:
async with httpx.AsyncClient(timeout=4.0) as c:
r = await c.get(f"{base}/v1/models")
return r.json()
except Exception as e:
return {"error": str(e), "data": []}

@app.post("/api/chat")
async def chat(req: UserRequest):
if not S.brain:
raise HTTPException(503, "Brain not ready")
await broadcast({"event": "USER_MSG", "msg": req.message})
result = await S.brain.think(req.message, req.task_id)
await broadcast({"event": "BRAIN_OUT", "data": result})
if result.get("type") == "PLAN" and result.get("steps"):
asyncio.create_task(
S.agent.run_plan(result["task_id"], result["steps"], broadcast)
)
return result

@app.get("/api/logs")
async def logs(): return {"logs": S.log[-100:]}

@app.get("/api/memory/stats")
async def mem_stats():
return S.memory.stats() if S.memory else {}

@app.delete("/api/agent/stop")
async def stop():
if S.agent: S.agent.stop()
return {"ok": True}

@app.websocket("/ws")
async def ws_ep(ws: WebSocket):
await ws.accept()
S.sockets.append(ws)
await ws.send_json({"event": "INIT", "logs": S.log[-50:]})
try:
while True:
d = await ws.receive_json()
if d.get("type") == "STOP" and S.agent:
S.agent.stop()
except WebSocketDisconnect:
if ws in S.sockets: S.sockets.remove(ws)
EOF
echo -e "${GREEN}✓ server.py${NC}"

_save_phase 3
_done 3 "Phase 4 → Dashboard HTML"
}

# ════════════════════════════════════════════════════════════
# PHASE 4 — Dashboard HTML (parametric)
# ════════════════════════════════════════════════════════════
phase_4() {
echo -e "${MAGENTA}▶ PHASE 4: Dashboard HTML${NC}\n"
source "$STATE_FILE"

cat > "$PROJECT_DIR/dashboard/templates/index.html" << 'HTML'
<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Jarvis Dashboard</title>
<style>
:root{
  --bg:#0d1117;--surf:#161b22;--brd:#30363d;
  --grn:#3fb950;--blu:#58a6ff;--org:#d29922;
  --red:#f85149;--pur:#bc8cff;--txt:#c9d1d9;
  --mut:#8b949e;--cyn:#39d353;
}
*{box-sizing:border-box;margin:0;padding:0}
body{background:var(--bg);color:var(--txt);font-family:'Segoe UI',monospace;overflow:hidden}

/* Grid */
.g{display:grid;grid-template-columns:270px 1fr 290px;grid-template-rows:56px 1fr;height:100vh}
header{grid-column:1/-1;background:var(--surf);border-bottom:1px solid var(--brd);
display:flex;align-items:center;padding:0 16px;gap:12px}
.sidebar{background:var(--surf);border-left:1px solid var(--brd);overflow-y:auto;padding:14px}
.main{display:flex;flex-direction:column;overflow:hidden}
.panel{background:var(--surf);border-right:1px solid var(--brd);overflow-y:auto;padding:14px}

/* Header */
.logo{font-size:1.3em;font-weight:700;color:var(--cyn);letter-spacing:2px}
.dot{width:9px;height:9px;border-radius:50%;background:var(--red);transition:.3s}
.dot.on{background:var(--grn)}
.hsp{flex:1}

/* Sidebar */
.stitle{font-size:.72em;text-transform:uppercase;color:var(--mut);
letter-spacing:1px;margin:14px 0 8px}
.cf label{display:block;font-size:.78em;color:var(--mut);margin-bottom:3px;margin-top:8px}
.cf input,.cf select{width:100%;padding:5px 9px;background:var(--bg);border:1px solid var(--brd);
  border-radius:5px;color:var(--txt);font-size:.82em}
.cf input:focus,.cf select:focus{outline:none;border-color:var(--blu)}
.btn{width:100%;padding:7px;border-radius:5px;border:none;cursor:pointer;
font-size:.82em;margin-top:4px;transition:opacity .2s}
.btn:hover{opacity:.82}
.bb{background:var(--blu);color:#000}
.bg{background:var(--grn);color:#000}
.br{background:var(--red);color:#fff}
.bo{background:transparent;color:var(--txt);border:1px solid var(--brd)}

/* Stats */
.sr{display:flex;justify-content:space-between;padding:5px 0;
border-bottom:1px solid var(--brd);font-size:.83em}
.sv{color:var(--cyn);font-weight:700}

/* Steps */
.si{padding:7px;background:var(--bg);border-radius:5px;margin-bottom:5px;
font-size:.8em;border-left:3px solid var(--brd)}
.si.run{border-color:var(--org);animation:pulse 1s infinite}
.si.ok {border-color:var(--grn)}
.si.err{border-color:var(--red)}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:.5}}

/* Chat */
.chat{flex:1;overflow-y:auto;padding:16px;display:flex;flex-direction:column;gap:10px}
.msg{max-width:88%;border-radius:9px;padding:11px 15px;font-size:.88em;line-height:1.55}
.mu{background:#1a2f50;color:var(--blu);margin-left:auto;direction:rtl}
.mb{background:#172817;color:var(--grn)}
.me{background:#2e1717;color:var(--red)}
.ms{color:var(--mut);font-size:.78em;text-align:center}
.msg pre{background:var(--bg);padding:7px;border-radius:5px;margin-top:7px;
overflow-x:auto;font-size:.83em;white-space:pre-wrap}

/* Input */
.inp{padding:12px;border-top:1px solid var(--brd);display:flex;gap:9px}
.inp textarea{flex:1;background:var(--bg);border:1px solid var(--brd);border-radius:7px;
  color:var(--txt);padding:9px;resize:none;font-size:.88em;font-family:inherit}
.inp textarea:focus{outline:none;border-color:var(--blu)}
.sbtn{padding:9px 18px;background:var(--blu);color:#000;border:none;
border-radius:7px;cursor:pointer;font-weight:700;align-self:flex-end}

/* Logs */
.le{font-size:.76em;padding:5px 7px;border-radius:4px;margin-bottom:3px;
background:var(--bg);border-left:3px solid var(--brd);
font-family:monospace;word-break:break-all}
.le.ok {border-color:var(--grn)}
.le.err{border-color:var(--red)}
.le.pln{border-color:var(--blu)}
.le.fix{border-color:var(--org)}
.le.sys{border-color:var(--mut)}

/* Badges */
.bx{display:inline-block;padding:2px 7px;border-radius:4px;
font-size:.73em;font-weight:700;margin-right:4px}
.bx.PLAN{background:#1a2f50;color:var(--blu)}
.bx.FIX {background:#2e1e0a;color:var(--org)}
.bx.KNOWLEDGE{background:#172817;color:var(--grn)}
.bx.ERROR{background:#2e1717;color:var(--red)}
.bx.L1{background:#0e2e0e;color:var(--cyn)}
.bx.L2{background:#0e0e2e;color:var(--pur)}
.bx.L3{background:#2e2e0e;color:var(--org)}
</style>
</head>
<body>
<div class="g">

<!-- Header -->
<header>
  <span class="logo">⚡ JARVIS</span>
  <div class="dot" id="dot"></div>
  <span id="stxt" style="font-size:.8em;color:var(--mut)">Connecting…</span>
  <div class="hsp"></div>
  <button class="btn br" style="width:auto;padding:5px 13px" onclick="stopAgent()">■ Stop</button>
</header>

<!-- Sidebar: Config -->
<aside class="sidebar">
  <div class="stitle">🔧 Config</div>
  <div class="cf">
<label>LM Studio Host</label>
<input id="cHost" value="http://localhost">
<label>Port</label>
<input id="cPort" value="1234" type="number">
<label>Model</label>
<select id="cModel"><option value="qwen3-4b-instruct-2507-q4_k_m">Qwen3-4B (default)</option></select>
<button class="btn bo" onclick="fetchModels()">↻ Fetch Models</button>
<label>Max Tokens</label>
<input id="cTok" value="6000" type="number">
<label>Max Steps</label>
<input id="cStp" value="10" type="number">
<label>Temperature</label>
<input id="cTmp" value="0.2" type="number" step="0.05" min="0" max="2">
<label>Top P</label>
<input id="cTop" value="0.95" type="number" step="0.05" min="0" max="1">
  </div>
  <button class="btn bb" style="margin-top:10px" onclick="saveConfig()">💾 Save</button>

  <div class="stitle">🧠 Memory</div>
  <div class="sr"><span>L1 Exact</span><span class="sv" id="ml1">—</span></div>
  <div class="sr"><span>L2 Semantic</span><span class="sv" id="ml2">—</span></div>
  <div class="sr"><span>L3 Events</span><span class="sv" id="ml3">—</span></div>
  <button class="btn bo" style="margin-top:7px" onclick="memStats()">↻ Refresh</button>

  <div class="stitle">📋 Steps</div>
  <div id="steps"></div>
</aside>

<!-- Main: Chat -->
<main class="main">
  <div class="chat" id="chat"></div>
  <div class="inp">
<textarea id="uinp" rows="3"
placeholder="Task or question… (Ctrl+Enter)"></textarea>
<button class="sbtn" onclick="send()">▶</button>
  </div>
</main>

<!-- Panel: Logs -->
<aside class="panel">
  <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px">
<div class="stitle" style="margin:0">📡 Events</div>
<button class="btn bo" style="width:auto;padding:2px 9px;font-size:.73em"
onclick="clearLog()">Clear</button>
  </div>
  <div id="logs"></div>
</aside>

</div><!-- /grid -->

<script>
// ── WS ───────────────────────────────────────────────────────
let ws;
function connect(){
  const p = location.protocol==='https:'?'wss:':'ws:';
  ws = new WebSocket(`${p}//${location.host}/ws`);
  ws.onopen  = ()=>{ setConn(true);  addLog('Connected','sys'); memStats(); };
  ws.onclose = ()=>{ setConn(false); setTimeout(connect,3000); };
  ws.onerror = ()=>  ws.close();
  ws.onmessage = e => handle(JSON.parse(e.data));
}
function setConn(on){
  document.getElementById('dot').className  = 'dot'+(on?' on':'');
  document.getElementById('stxt').textContent = on?'Connected':'Disconnected…';
}

// ── Event handler ────────────────────────────────────────────
function handle(ev){
  const t = ev.event;
  if(t==='INIT'){ ev.logs.forEach(handle); return; }

  if(t==='USER_MSG'){
addChat(ev.msg,'mu');
addLog('User: '+ev.msg.slice(0,55)+'…','sys');
return;
  }
  if(t==='BRAIN_OUT'){
const d=ev.data, tp=d.type||'';
let h=`<span class="bx ${tp}">${tp}</span>`;
if(d.memory_used && d.memory_used!=='NONE')
h+=`<span class="bx ${d.memory_used}">${d.memory_used}</span>`;
if(tp==='PLAN'){
h+=` <b>${d.goal}</b><br><small>${(d.steps||[]).length} steps · ${d.task_id}</small>`;
renderSteps(d.steps||[]);
} else if(tp==='FIX'){
h+=` <b>${d.error_summary}</b><br><small>${d.root_cause}</small>`;
} else {
h+=`<pre>${d.answer||JSON.stringify(d,null,2)}</pre>`;
}
addChat(h,'mb');
addLog(`Brain→${tp} mem=${d.memory_used}`, tp==='FIX'?'fix':'pln');
return;
  }
  if(t==='STEP_START'){
stepStatus(ev.step_id,'run',ev.action);
addLog(`▶ #${ev.step_id} ${(ev.command||'').slice(0,50)}`,'pln');
return;
  }
  if(t==='STEP_SUCCESS'){
stepStatus(ev.step_id,'ok');
addLog(`✓ #${ev.step_id} OK`,'ok');
memStats();
return;
  }
  if(t==='STEP_ERROR'){
stepStatus(ev.step_id,'err');
addLog(`✗ #${ev.step_id} ${(ev.stderr||'').slice(0,55)}`,'err');
addChat(`<b>Error step ${ev.step_id}</b><pre>${ev.stderr}</pre>`,'me');
return;
  }
  if(t==='ERROR_FIX'){
addLog(`🔧 Fix·mem=${ev.data?.memory_used}`,'fix'); return;
  }
  if(t==='CONFIG_UPDATED'){
addLog('Config saved ✓','ok'); return;
  }
  if(t==='CONFIRM_NEEDED'){
const s=ev.step;
if(confirm(`⚠️ Dangerous:\n${s.command}\n\nProceed?`))
ws.send(JSON.stringify({type:'CONFIRM',step_id:s.step_id}));
return;
  }
}

// ── Chat ─────────────────────────────────────────────────────
function addChat(html,cls){
  const d=document.createElement('div');
  d.className=`msg ${cls}`; d.innerHTML=html;
  const c=document.getElementById('chat');
  c.appendChild(d); c.scrollTop=c.scrollHeight;
}

// ── Logs ─────────────────────────────────────────────────────
function addLog(txt,cls='sys'){
  const d=document.createElement('div');
  d.className=`le ${cls}`;
  d.textContent=new Date().toLocaleTimeString()+' — '+txt;
  const l=document.getElementById('logs');
  l.prepend(d);
  if(l.children.length>300) l.lastChild.remove();
}
function clearLog(){ document.getElementById('logs').innerHTML=''; }

// ── Steps ─────────────────────────────────────────────────────
function renderSteps(arr){
  const el=document.getElementById('steps'); el.innerHTML='';
  arr.forEach(s=>{
const d=document.createElement('div');
d.className='si'; d.id=`s${s.step_id}`;
d.innerHTML=`<b>#${s.step_id}</b> ${s.action}<br>
<span style="color:var(--mut);font-size:.85em">${(s.command||'').slice(0,42)}…</span>`;
el.appendChild(d);
  });
}
function stepStatus(id,st,label){
  const el=document.getElementById(`s${id}`);
  if(el){ el.className=`si ${st}`;
if(label) el.querySelector('b').textContent=`#${id} ${label}`; }
}

// ── API ──────────────────────────────────────────────────────
async function send(){
  const t=document.getElementById('uinp'); const msg=t.value.trim();
  if(!msg) return; t.value='';
  try{
const r=await fetch('/api/chat',{method:'POST',
headers:{'Content-Type':'application/json'},
body:JSON.stringify({message:msg})});
if(!r.ok) addChat('Error: '+await r.text(),'me');
  }catch(e){ addChat('Network error: '+e.message,'me'); }
}

async function fetchModels(){
  try{
const r=await fetch('/api/models'), d=await r.json();
const sel=document.getElementById('cModel'); sel.innerHTML='';
(d.data||[]).forEach(m=>{
const o=document.createElement('option');
o.value=m.id; o.textContent=m.id; sel.appendChild(o);
});
if(!sel.options.length)
sel.innerHTML='<option>No models found</option>';
addLog('Models fetched','ok');
  }catch(e){ addLog('Models error: '+e.message,'err'); }
}

async function saveConfig(){
  try{
await fetch('/api/config',{method:'POST',
headers:{'Content-Type':'application/json'},
body:JSON.stringify({
lm_host:    document.getElementById('cHost').value,
lm_port:    +document.getElementById('cPort').value,
model_name: document.getElementById('cModel').value,
max_tokens: +document.getElementById('cTok').value,
max_steps:  +document.getElementById('cStp').value,
temperature:+document.getElementById('cTmp').value,
top_p:      +document.getElementById('cTop').value,
dashboard_port: +location.port||7860
})});
addLog('Config saved ✓','ok');
  }catch(e){ addLog('Save error: '+e.message,'err'); }
}

async function memStats(){
  try{
const r=await fetch('/api/memory/stats'),d=await r.json();
document.getElementById('ml1').textContent=d.l1_entries??'—';
document.getElementById('ml2').textContent=d.l2_collection??'—';
document.getElementById('ml3').textContent=d.l3_events??'—';
  }catch(_){}
}

async function stopAgent(){
  await fetch('/api/agent/stop',{method:'DELETE'});
  addLog('Agent stopped','sys');
}

document.getElementById('uinp').addEventListener('keydown',e=>{
  if(e.ctrlKey&&e.key==='Enter') send();
});

connect();
</script>
</body>
</html>
HTML
echo -e "${GREEN}✓ index.html${NC}"

_save_phase 4
_done 4 "Phase 5 → main.py + TUI + run scripts + health check"
}

# ════════════════════════════════════════════════════════════
# PHASE 5 — Entry points + scripts + tests
# ════════════════════════════════════════════════════════════
phase_5() {
echo -e "${MAGENTA}▶ PHASE 5: Entry Points + Scripts${NC}\n"
source "$STATE_FILE"
source "$PROJECT_DIR/.venv/bin/activate"

# ── main.py ─────────────────────────────────────────────
cat > "$PROJECT_DIR/src/main.py" << 'EOF'
import os, sys
from pathlib import Path
import uvicorn
from loguru import logger
from dotenv import load_dotenv
load_dotenv()

def setup_log():
lp = os.getenv("LOG_PATH", str(Path.home()/"jarvis/logs"))
logger.remove()
logger.add(sys.stderr, level=os.getenv("LOG_LEVEL","INFO"),
format="<green>{time:HH:mm:ss}</green> | <level>{level:<7}</level> | {message}")
logger.add(f"{lp}/brain/brain.log", rotation="10 MB", retention="7 days",
level="DEBUG", encoding="utf-8")

if __name__ == "__main__":
setup_log()
host = os.getenv("DASHBOARD_HOST","0.0.0.0")
port = int(os.getenv("DASHBOARD_PORT","7860"))
logger.info(f"Dashboard → http://localhost:{port}")
logger.info(f"LM Studio → {os.getenv('LM_STUDIO_URL')}")
logger.info(f"Model     → {os.getenv('MODEL_NAME')}")
uvicorn.run("server:app", host=host, port=port,
reload=False, log_level="warning",
app_dir=str(Path(__file__).parent))
EOF
echo -e "${GREEN}✓ main.py${NC}"

# ── tui.py ──────────────────────────────────────────────
cat > "$PROJECT_DIR/src/tui.py" << 'EOF'
import asyncio, httpx, os
from rich.console import Console
from rich.panel   import Panel
from rich.prompt  import Prompt
from rich.table   import Table
from rich         import box
from dotenv import load_dotenv
load_dotenv()

C   = Console()
URL = f"http://localhost:{os.getenv('DASHBOARD_PORT','7860')}"

async def stats():
async with httpx.AsyncClient(timeout=3) as c:
return (await c.get(f"{URL}/api/memory/stats")).json()

async def chat(msg):
async with httpx.AsyncClient(timeout=120) as c:
return (await c.post(f"{URL}/api/chat",
json={"message": msg})).json()

def show(d):
tp = d.get("type","?")
if tp == "PLAN":
t = Table(box=box.ROUNDED, title=f"[blue]PLAN[/] {d.get('goal','')}",
show_lines=True)
t.add_column("#",   style="cyan", width=4)
t.add_column("Action")
t.add_column("Command", style="green")
t.add_column("Safe", width=5)
for s in d.get("steps",[]):
t.add_row(str(s["step_id"]), s["action"],
s["command"][:55], "✓" if s.get("safe",True) else "[red]⚠[/]")
C.print(t)
elif tp == "KNOWLEDGE":
C.print(Panel(d.get("answer",""), title="[green]KNOWLEDGE[/]",
border_style="green"))
elif tp == "FIX":
C.print(Panel(f"[red]{d.get('error_summary','')}[/]\n{d.get('root_cause','')}",
title="[orange1]FIX[/]", border_style="orange1"))
else:
C.print(Panel(str(d), title=f"[red]{tp}[/]"))
C.print(f"[dim]mem={d.get('memory_used','—')} task={d.get('task_id','—')}[/]")

async def loop():
C.print(Panel("[cyan]JARVIS[/] TUI\n[dim]Ctrl+C or 'q' to quit[/]",
title="⚡", border_style="cyan"))
try:
s = await stats()
C.print(f"[green]Dashboard OK[/] L1={s.get('l1_entries',0)} L3={s.get('l3_events',0)}")
except:
C.print("[red]Dashboard not running — start ./run.sh first[/]"); return

while True:
try:
m = Prompt.ask("[blue]>[/]")
if m.strip().lower() in ("q","quit","exit"): break
if not m.strip(): continue
with C.status("[yellow]Thinking…[/]", spinner="dots"):
show(await chat(m))
except KeyboardInterrupt: break
except Exception as e: C.print(f"[red]{e}[/]")

if __name__ == "__main__":
asyncio.run(loop())
EOF
echo -e "${GREEN}✓ tui.py${NC}"

# ── run.sh ───────────────────────────────────────────────
cat > "$PROJECT_DIR/run.sh" << RSCRIPT
#!/bin/bash
cd "\$(dirname "\$0")"
source .venv/bin/activate
export PYTHONPATH=src
source .env
echo "Jarvis starting…  Dashboard → http://localhost:\${DASHBOARD_PORT:-7860}"
python3 src/main.py
RSCRIPT

# ── run_tui.sh ───────────────────────────────────────────
cat > "$PROJECT_DIR/run_tui.sh" << TSCRIPT
#!/bin/bash
cd "\$(dirname "\$0")"
source .venv/bin/activate
export PYTHONPATH=src
source .env
python3 src/tui.py
TSCRIPT

# ── health_check.sh ──────────────────────────────────────
cat > "$PROJECT_DIR/health_check.sh" << 'HSCRIPT'
#!/bin/bash
source "$(dirname "$0")/.env"
W='\033[1;33m'; G='\033[0;32m'; R='\033[0;31m'; N='\033[0m'
echo -e "${W}═══════ Jarvis Health Check ═══════${N}"
python3 --version 2>/dev/null && echo -e "${G}✓ Python${N}" || echo -e "${R}✗ Python${N}"
[ -d .venv ] && echo -e "${G}✓ Venv${N}"    || echo -e "${R}✗ Venv${N}"
curl -s --max-time 3 "${LM_STUDIO_HOST}:${LM_STUDIO_PORT}/v1/models" >/dev/null \
  && echo -e "${G}✓ LM Studio${N}" || echo -e "${R}✗ LM Studio (start it on Windows)${N}"
curl -s --max-time 3 "http://localhost:${DASHBOARD_PORT:-7860}" >/dev/null \
  && echo -e "${G}✓ Dashboard${N}" || echo -e "${R}✗ Dashboard (run ./run.sh)${N}"
for d in memory/l1_exact memory/l2_vector memory/l3_supervisor; do
  [ -d "$d" ] && echo -e "${G}✓ $d${N}" || echo -e "${R}✗ $d${N}"
done
echo -e "${W}═══════════════════════════════════${N}"
HSCRIPT

chmod +x "$PROJECT_DIR"/{run.sh,run_tui.sh,health_check.sh}

# ── test_memory.py ───────────────────────────────────────
cat > "$PROJECT_DIR/tests/test_memory.py" << 'EOF'
import sys, os, tempfile
sys.path.insert(0, os.path.join(os.path.dirname(__file__),'../src'))
from memory import MemorySystem

def mk():
t = tempfile.mkdtemp()
d = [os.path.join(t,x) for x in ('l1','l2','l3')]
for x in d: os.makedirs(x)
return MemorySystem(*d)

def test_l1():
m = mk()
m.l1_store("cmd:err", {"fix":"retry"})
assert m.l1_get("cmd:err") == {"fix":"retry"}
r = m.search("cmd:err")
assert r['found'] and r['level']=='L1'
print("✓ L1 OK")

def test_l3():
m = mk()
m.l3_log({"event":"TEST"})
assert len(m.l3_patterns()) == 1
print("✓ L3 OK")

def test_priority():
m = mk()
assert m.search("nothing")['found'] == False
print("✓ Priority search OK")

if __name__ == "__main__":
test_l1(); test_l3(); test_priority()
print("\n✅ All tests passed")
EOF

_save_phase 5

# ── Final banner ─────────────────────────────────────────
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}       ✅  ALL 5 PHASES COMPLETE!${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${YELLOW}Project:${NC}   $PROJECT_DIR"
echo ""
echo -e "  ${CYAN}Commands:${NC}"
echo -e "  ${GREEN}cd $PROJECT_DIR${NC}"
echo -e "  ${GREEN}./health_check.sh${NC}   ← check everything"
echo -e "  ${GREEN}./run.sh${NC}             ← start dashboard"
echo -e "  ${GREEN}./run_tui.sh${NC}         ← terminal UI"
echo ""
echo -e "  ${CYAN}Dashboard:${NC} http://localhost:${DASHBOARD_PORT}"
echo ""
echo -e "  ${YELLOW}Files:${NC}"
echo -e "  src/schemas.py  src/memory.py  src/brain.py"
echo -e "  src/agent.py    src/server.py  src/main.py  src/tui.py"
echo ""
}

# ════════════════════════════════════════════════════════════
# Helpers
# ════════════════════════════════════════════════════════════
_save_phase(){
sed -i "s/^CURRENT_PHASE=.*/CURRENT_PHASE=${1}/" "$STATE_FILE"
}
_done(){
echo ""
echo -e "${GREEN}✅ Phase ${1} complete${NC}"
echo -e "   ${YELLOW}Run script again for:${NC} ${2}"
echo ""
}

# ════════════════════════════════════════════════════════════
# Dispatcher
# ════════════════════════════════════════════════════════════
case $NEXT_PHASE in
  1) phase_0 ;;
  2) phase_1 ;;
  3) phase_2 ;;
  4) phase_3 ;;
  5) phase_4 ;;
  6) phase_5 ;;
  *)
echo -e "${GREEN}✅ All phases done!${NC}"
source "$STATE_FILE" 2>/dev/null
echo -e "   ${YELLOW}cd $PROJECT_DIR && ./run.sh${NC}"
;;
esac


---

## نحوه اجرا:

```bash
chmod +x jarvis_setup.sh

./jarvis_setup.sh   # Phase 0 — Base + .env
./jarvis_setup.sh   # Phase 1 — Brain (schemas + memory + brain)
./jarvis_setup.sh   # Phase 2 — Agent
./jarvis_setup.sh   # Phase 3 — FastAPI server
./jarvis_setup.sh   # Phase 4 — Dashboard HTML
./jarvis_setup.sh   # Phase 5 — main + TUI + scripts ✅
