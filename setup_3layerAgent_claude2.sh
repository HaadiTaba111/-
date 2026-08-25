#!/bin/bash
set -e

echo "=== بهینه‌سازی و تکمیل Personal Coding Agent ==="

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}[1/5] تکمیل فایل‌های ناقص...${NC}"

# تکمیل knowledge_search.py
cat > agent/tools/knowledge_search.py << 'EOF'
import os
import logging
import chromadb
from chromadb.config import Settings
from typing import List, Dict

logger = logging.getLogger(__name__)

class KnowledgeSearch:
    def __init__(self):
        chroma_url = os.getenv("CHROMA_URL", "http://localhost:8000")
        host = chroma_url.replace("http://", "").replace("https://", "").split(":")[0]
        port = int(chroma_url.split(":")[-1]) if ":" in chroma_url.split("//")[-1] else 8000
        
        try:
            self.client = chromadb.HttpClient(
                host=host,
                port=port,
                settings=Settings(anonymized_telemetry=False)
            )
            self.collection = self.client.get_or_create_collection(
                name="agent_memory",
                metadata={"description": "Agent learning memory"}
            )
            self.embedder = None
            logger.info("ChromaDB متصل شد")
        except Exception as e:
            logger.error(f"خطا در اتصال به ChromaDB: {e}")
            raise
    
    def _get_embedder(self):
        if self.embedder is None:
            from sentence_transformers import SentenceTransformer
            self.embedder = SentenceTransformer('all-MiniLM-L6-v2')
            logger.info("Embedding model loaded")
        return self.embedder
    
    async def search(self, query: str, n_results: int = 3) -> List[Dict]:
        try:
            embedder = self._get_embedder()
            query_embedding = embedder.encode([query])[0].tolist()
            
            results = self.collection.query(
                query_embeddings=[query_embedding],
                n_results=n_results
            )
            
            if not results["documents"] or not results["documents"][0]:
                return []
            
            return [
                {
                    "code": doc,
                    "metadata": meta
                }
                for doc, meta in zip(results["documents"][0], results["metadatas"][0])
            ]
        except Exception as e:
            logger.error(f"خطا در جستجو: {e}")
            return []
    
    async def store(self, query: str, code: str, result: Dict, metadata: Dict):
        try:
            embedder = self._get_embedder()
            embedding = embedder.encode([query])[0].tolist()
            
            doc_id = f"{metadata['timestamp']}_{abs(hash(query)) % 1000000}"
            
            self.collection.add(
                embeddings=[embedding],
                documents=[code],
                metadatas=[{
                    "query": query,
                    "status": result.get("status"),
                    "exit_code": result.get("exit_code"),
                    **metadata
                }],
                ids=[doc_id]
            )
            
            logger.info(f"دانش جدید ذخیره شد: {doc_id}")
        
        except Exception as e:
            logger.error(f"خطا در ذخیره دانش: {e}")
    
    async def health_check(self) -> bool:
        try:
            self.client.heartbeat()
            return True
        except Exception as e:
            logger.error(f"ChromaDB health check failed: {e}")
            return False
EOF

# تکمیل file_manager.py
cat > agent/tools/file_manager.py << 'EOF'
import os
import logging
from pathlib import Path
from typing import List

logger = logging.getLogger(__name__)

class FileManager:
    def __init__(self):
        self.workspace = Path(os.getenv("WORKSPACE_PATH", "/workspace"))
        self.workspace.mkdir(parents=True, exist_ok=True)
        self.max_file_size = int(os.getenv("MAX_FILE_SIZE", "10485760"))
        self.allowed_extensions = os.getenv("ALLOWED_EXTENSIONS", ".py,.js,.html,.css,.json,.md,.txt").split(",")
    
    async def read_file(self, path: str) -> str:
        try:
            file_path = self.workspace / path
            
            if not file_path.exists():
                raise FileNotFoundError(f"فایل {path} پیدا نشد")
            
            if file_path.stat().st_size > self.max_file_size:
                raise ValueError(f"فایل بیش از حد بزرگ است")
            
            return file_path.read_text(encoding='utf-8')
        except Exception as e:
            logger.error(f"خطا در خواندن فایل: {e}")
            raise
    
    async def write_file(self, path: str, content: str):
        try:
            file_path = self.workspace / path
            
            if file_path.suffix not in self.allowed_extensions:
                raise ValueError(f"پسوند {file_path.suffix} مجاز نیست")
            
            file_path.parent.mkdir(parents=True, exist_ok=True)
            file_path.write_text(content, encoding='utf-8')
            logger.info(f"فایل ذخیره شد: {path}")
        except Exception as e:
            logger.error(f"خطا در نوشتن فایل: {e}")
            raise
    
    async def list_files(self, pattern: str = "*") -> List[str]:
        try:
            files = [str(f.relative_to(self.workspace)) for f in self.workspace.rglob(pattern) if f.is_file()]
            return files
        except Exception as e:
            logger.error(f"خطا در لیست فایل‌ها: {e}")
            return []
EOF

echo -e "${GREEN}✓ فایل‌های ناقص تکمیل شدند${NC}"

echo -e "${YELLOW}[2/5] اضافه کردن Auto-Fix Loop...${NC}"

# ساخت auto_fixer.py
cat > agent/tools/auto_fixer.py << 'EOF'
import logging
from typing import Dict, Optional
from .code_generator import CodeGenerator
from .code_executor import CodeExecutor

logger = logging.getLogger(__name__)

class AutoFixer:
    def __init__(self, code_gen: CodeGenerator, executor: CodeExecutor):
        self.code_gen = code_gen
        self.executor = executor
        self.max_attempts = 3
    
    async def fix_and_execute(self, original_code: str, original_prompt: str) -> Dict:
        """
        تلاش برای اصلاح خودکار کد در صورت خطا
        """
        current_code = original_code
        attempt = 1
        history = []
        
        while attempt <= self.max_attempts:
            logger.info(f"تلاش {attempt}/{self.max_attempts} برای اجرای کد")
            
            result = await self.executor.execute(current_code)
            
            history.append({
                "attempt": attempt,
                "code": current_code,
                "result": result
            })
            
            if result["status"] == "success":
                logger.info(f"✓ کد با موفقیت اجرا شد در تلاش {attempt}")
                return {
                    "status": "success",
                    "final_code": current_code,
                    "result": result,
                    "attempts": attempt,
                    "history": history
                }
            
            if attempt == self.max_attempts:
                logger.warning(f"✗ پس از {self.max_attempts} تلاش، کد اجرا نشد")
                return {
                    "status": "failed",
                    "final_code": current_code,
                    "result": result,
                    "attempts": attempt,
                    "history": history
                }
            
            logger.info(f"خطا یافت شد، تلاش برای اصلاح...")
            current_code = await self._fix_code(
                code=current_code,
                error=result.get("error", ""),
                original_prompt=original_prompt
            )
            
            attempt += 1
        
        return {
            "status": "failed",
            "final_code": current_code,
            "result": result,
            "attempts": self.max_attempts,
            "history": history
        }
    
    async def _fix_code(self, code: str, error: str, original_prompt: str) -> str:
        """
        درخواست اصلاح کد از مدل
        """
        fix_prompt = f"""کد زیر خطا دارد. آن را اصلاح کن.

درخواست اصلی:
{original_prompt}

کد فعلی:
```python
{code}

خطا:
{error}

قوانین:
1. فقط کد اصلاح‌شده را بنویس
2. خطا را برطرف کن
3. منطق اصلی را حفظ کن
4. کد را داخل 
```python قرار بده

کد اصلاح‌شده:"""

        try:
            fixed_code = await self.code_gen.generate(
                prompt=fix_prompt,
                context=[]
            )
            logger.info("کد اصلاح شد")
            return fixed_code
        except Exception as e:
            logger.error(f"خطا در اصلاح کد: {e}")
            return code
EOF

echo -e "${GREEN}✓ Auto-Fix Loop اضافه شد${NC}"

echo -e "${YELLOW}[3/5] آپدیت orchestrator برای استفاده از Auto-Fix...${NC}"

# آپدیت orchestrator.py
cat > agent/orchestrator.py << 'EOF'
import os
import json
import logging
from typing import Dict, Any, List
from datetime import datetime
from langgraph.graph import StateGraph, END
from tools.code_generator import CodeGenerator
from tools.code_executor import CodeExecutor
from tools.knowledge_search import KnowledgeSearch
from tools.file_manager import FileManager
from tools.auto_fixer import AutoFixer

logger = logging.getLogger(__name__)

class AgentState(dict):
    pass

class AgentOrchestrator:
    def __init__(self):
        self.ollama_url = os.getenv("OLLAMA_URL", "http://localhost:11434")
        self.model = os.getenv("DEFAULT_MODEL", "qwen2.5:7b-instruct-q4_K_M")
        
        self.code_gen = CodeGenerator(self.ollama_url, self.model)
        self.executor = CodeExecutor()
        self.knowledge = KnowledgeSearch()
        self.file_mgr = FileManager()
        self.auto_fixer = AutoFixer(self.code_gen, self.executor)
        
        self.sessions = {}
        
        self.workflow = self._build_workflow()
        logger.info("Orchestrator با Auto-Fix آماده شد")
    
    def _build_workflow(self) -> StateGraph:
        workflow = StateGraph(AgentState)
        
        workflow.add_node("understand", self._understand_task)
        workflow.add_node("search_knowledge", self._search_knowledge)
        workflow.add_node("generate_code", self._generate_code)
        workflow.add_node("auto_fix_execute", self._auto_fix_execute)
        workflow.add_node("learn", self._learn_from_result)
        workflow.add_node("respond", self._create_response)
        
        workflow.set_entry_point("understand")
        workflow.add_edge("understand", "search_knowledge")
        workflow.add_conditional_edges(
            "search_knowledge",
            self._should_generate_code,
            {
                "generate": "generate_code",
                "respond": "respond"
            }
        )
        workflow.add_edge("generate_code", "auto_fix_execute")
        workflow.add_edge("auto_fix_execute", "learn")
        workflow.add_edge("learn", "respond")
        workflow.add_edge("respond", END)
        
        return workflow.compile()
    
    async def process(self, message: str, session_id: str) -> Dict[str, Any]:
        initial_state = AgentState({
            "message": message,
            "session_id": session_id,
            "timestamp": datetime.now().isoformat(),
            "task_type": None,
            "context": [],
            "code": None,
            "execution_result": None,
            "response": None,
            "fix_attempts": 0
        })
        
        final_state = await self.workflow.ainvoke(initial_state)
        
        if session_id not in self.sessions:
            self.sessions[session_id] = []
        self.sessions[session_id].append({
            "message": message,
            "response": final_state.get("response"),
            "timestamp": final_state.get("timestamp")
        })
        
        return {
            "response": final_state.get("response", "خطایی رخ داد"),
            "code": final_state.get("code"),
            "execution_result": final_state.get("execution_result"),
            "task_type": final_state.get("task_type"),
            "fix_attempts": final_state.get("fix_attempts", 0)
        }
    
    async def _understand_task(self, state: AgentState) -> AgentState:
        message = state["message"].lower()
        
        if any(word in message for word in ["بنویس", "کد", "تابع", "کلاس", "write", "code", "function", "class"]):
            state["task_type"] = "code_generation"
        elif any(word in message for word in ["اجرا", "تست", "run", "execute", "test"]):
            state["task_type"] = "code_execution"
        elif any(word in message for word in ["توضیح", "چیه", "چطور", "explain", "what", "how"]):
            state["task_type"] = "explanation"
        elif any(word in message for word in ["فایل", "ذخیره", "بخون", "file", "save", "read"]):
            state["task_type"] = "file_operation"
        else:
            state["task_type"] = "general"
        
        logger.info(f"نوع task: {state['task_type']}")
        return state
    
    async def _search_knowledge(self, state: AgentState) -> AgentState:
        try:
            results = await self.knowledge.search(
                query=state["message"],
                n_results=3
            )
            state["context"] = results
            logger.info(f"{len(results)} نتیجه از حافظه پیدا شد")
        except Exception as e:
            logger.warning(f"خطا در جستجو: {e}")
            state["context"] = []
        return state
    
    def _should_generate_code(self, state: AgentState) -> str:
        if state["task_type"] in ["code_generation", "code_execution"]:
            return "generate"
        return "respond"
    
    async def _generate_code(self, state: AgentState) -> AgentState:
        try:
            code = await self.code_gen.generate(
                prompt=state["message"],
                context=state["context"]
            )
            state["code"] = code
            logger.info(f"کد تولید شد ({len(code)} کاراکتر)")
        except Exception as e:
            logger.error(f"خطا در تولید کد: {e}")
            state["code"] = None
        return state
    
    async def _auto_fix_execute(self, state: AgentState) -> AgentState:
        if state["code"]:
            try:
                result = await self.auto_fixer.fix_and_execute(
                    original_code=state["code"],
                    original_prompt=state["message"]
                )
                
                state["execution_result"] = result["result"]
                state["code"] = result["final_code"]
                state["fix_attempts"] = result["attempts"]
                
                if result["status"] == "success":
                    logger.info(f"✓ کد با موفقیت اجرا شد (تلاش {result['attempts']})")
                else:
                    logger.warning(f"✗ کد پس از {result['attempts']} تلاش اجرا نشد")
                
            except Exception as e:
                logger.error(f"خطا در Auto-Fix: {e}")
                state["execution_result"] = {
                    "status": "error",
                    "error": str(e)
                }
                state["fix_attempts"] = 0
        return state
    
    async def _learn_from_result(self, state: AgentState) -> AgentState:
        if state["code"] and state["execution_result"]:
            try:
                await self.knowledge.store(
                    query=state["message"],
                    code=state["code"],
                    result=state["execution_result"],
                    metadata={
                        "task_type": state["task_type"],
                        "timestamp": state["timestamp"],
                        "session_id": state["session_id"],
                        "fix_attempts": state.get("fix_attempts", 0)
                    }
                )
                logger.info("نتیجه در حافظه ذخیره شد")
            except Exception as e:
                logger.warning(f"خطا در ذخیره: {e}")
        return state
    
    async def _create_response(self, state: AgentState) -> AgentState:
        if state["task_type"] == "code_generation":
            if state["execution_result"]:
                attempts = state.get("fix_attempts", 1)
                
                if state["execution_result"]["status"] == "success":
                    if attempts > 1:
                        state["response"] = f"✅ کد پس از {attempts} تلاش اصلاح شد و اجرا شد!\n\n📤 خروجی:\n{state['execution_result']['output']}"
                    else:
                        state["response"] = f"✅ کد با موفقیت اجرا شد!\n\n📤 خروجی:\n{state['execution_result']['output']}"
                else:
                    state["response"] = f"❌ کد پس از {attempts} تلاش اصلاح نشد:\n{state['execution_result']['error']}"
            else:
                state["response"] = "کد تولید شد اما اجرا نشد."
        elif state["task_type"] == "explanation":
            state["response"] = await self._generate_explanation(state)
        else:
            state["response"] = "درخواست شما پردازش شد."
        
        return state
    
    async def _generate_explanation(self, state: AgentState) -> str:
        try:
            explanation = await self.code_gen.explain(
                query=state["message"],
                context=state["context"]
            )
            return explanation
        except:
            return "متاسفانه نتوانستم توضیح مناسبی تولید کنم."
    
    async def check_ollama(self) -> bool:
        try:
            import aiohttp
            async with aiohttp.ClientSession() as session:
                async with session.get(f"{self.ollama_url}/api/tags", timeout=aiohttp.ClientTimeout(total=5)) as resp:
                    return resp.status == 200
        except:
            return False
    
    async def check_chroma(self) -> bool:
        try:
            return await self.knowledge.health_check()
        except:
            return False
    
    def get_session_history(self, session_id: str) -> List[Dict]:
        return self.sessions.get(session_id, [])
EOF

echo -e "${GREEN}✓ Orchestrator آپدیت شد${NC}"

echo -e "${YELLOW}[4/5] ساخت UI و Executor...${NC}"

# executor/Dockerfile
cat > executor/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /sandbox

RUN apt-get update && apt-get install -y \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -u 1000 sandbox && \
    chown -R sandbox:sandbox /sandbox

USER sandbox

CMD ["tail", "-f", "/dev/null"]
EOF

# ui/Dockerfile
cat > ui/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

CMD ["python", "app.py"]
EOF

# ui/requirements.txt
cat > ui/requirements.txt << 'EOF'
gradio==4.16.0
requests==2.31.0
EOF

# ui/app.py
cat > ui/app.py << 'EOF'
import os
import gradio as gr
import requests
from typing import List, Tuple

AGENT_API = os.getenv("AGENT_API_URL", "http://localhost:8080")

def chat(message: str, history: List[Tuple[str, str]]) -> Tuple[List[Tuple[str, str]], str]:
    try:
        response = requests.post(
            f"{AGENT_API}/chat",
            json={"message": message, "session_id": "web_ui"},
            timeout=120
        )
        
        if response.status_code == 200:
            data = response.json()
            
            reply = data["response"]
            
            if data.get("code"):
                reply += f"\n\n
```python\n{data['code']}\n
```"
            
            if data.get("fix_attempts", 0) > 1:
                reply += f"\n\n🔧 تعداد تلاش‌های اصلاح: {data['fix_attempts']}"
            
            history.append((message, reply))
            return history, ""
        else:
            history.append((message, f"❌ خطا: {response.status_code}"))
            return history, ""
    
    except Exception as e:
        history.append((message, f"❌ خطا در ارتباط: {str(e)}"))
        return history, ""

with gr.Blocks(title="Personal Coding Agent", theme=gr.themes.Soft()) as demo:
    gr.Markdown("# 🤖 Personal Coding Agent")
    gr.Markdown("دستیار کدنویسی شخصی شما - کاملاً آفلاین")
    
    chatbot = gr.Chatbot(height=500, label="گفتگو")
    msg = gr.Textbox(
        label="پیام شما",
        placeholder="مثال: یک تابع برای محاسبه فیبوناچی بنویس",
        lines=2
    )
    
    with gr.Row():
        submit = gr.Button("ارسال", variant="primary")
        clear = gr.Button("پاک کردن")
    
    submit.click(chat, inputs=[msg, chatbot], outputs=[chatbot, msg])
    msg.submit(chat, inputs=[msg, chatbot], outputs=[chatbot, msg])
    clear.click(lambda: ([], ""), outputs=[chatbot, msg])
    
    gr.Markdown("---")
    gr.Markdown("💡 **نکات:**\n- از زبان فارسی یا انگلیسی استفاده کنید\n- سیستم خودکار کد را اصلاح می‌کند\n- تمام داده‌ها روی سیستم شما ذخیره می‌شود")

if __name__ == "__main__":
    demo.launch(server_name="0.0.0.0", server_port=7860)
EOF

echo -e "${GREEN}✓ UI و Executor ساخته شدند${NC}"

echo -e "${YELLOW}[5/5] ساخت اسکریپت‌های مدیریت...${NC}"

# start.sh
cat > start.sh << 'EOF'
#!/bin/bash
echo "🚀 راه‌اندازی Personal Coding Agent..."

docker-compose up -d

echo ""
echo "✓ سرویس‌ها راه‌اندازی شدند"
echo ""
echo "📍 آدرس‌ها:"
echo "  - UI: http://localhost:7860"
echo "  - API: http://localhost:8080"
echo "  - Ollama: http://localhost:11434"
echo ""
echo "⏳ منتظر بمانید تا مدل‌ها لود شوند (30-60 ثانیه)"
echo ""
echo "📊 برای مشاهده لاگ‌ها: ./logs.sh"
EOF

chmod +x start.sh

# stop.sh
cat > stop.sh << 'EOF'
#!/bin/bash
echo "🛑 متوقف کردن سرویس‌ها..."
docker-compose down
echo "✓ تمام سرویس‌ها متوقف شدند"
EOF

chmod +x stop.sh

# logs.sh
cat > logs.sh << 'EOF'
#!/bin/bash
if [ -z "$1" ]; then
    echo "📊 لاگ تمام سرویس‌ها:"
    docker-compose logs -f
else
    echo "📊 لاگ $1:"
    docker-compose logs -f $1
fi
EOF

chmod +x logs.sh

# status.sh
cat > status.sh << 'EOF'
#!/bin/bash
echo "📊 وضعیت سرویس‌ها:"
echo ""
docker-compose ps
echo ""
echo "💾 مصرف منابع:"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
EOF

chmod +x status.sh

# pull-model.sh
cat > pull-model.sh << 'EOF'
#!/bin/bash
MODEL=${1:-qwen2.5:7b-instruct-q4_K_M}

echo "📥 دانلود مدل $MODEL..."
echo "⚠️  این کار ممکن است چند دقیقه طول بکشد"
echo ""

docker exec -it agent-brain ollama pull $MODEL

echo ""
echo "✓ مدل دانلود شد"
echo ""
echo "📋 لیست مدل‌های نصب شده:"
docker exec -it agent-brain ollama list
EOF

chmod +x pull-model.sh

echo -e "${GREEN}✓ اسکریپت‌های مدیریت ساخته شدند${NC}"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ بهینه‌سازی کامل شد!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}تغییرات اعمال شده:${NC}"
echo "  1. ✓ Lazy loading برای Embedding model (صرفه‌جویی ~120MB RAM)"
echo "  2. ✓ Auto-Fix Loop (اصلاح خودکار کد تا 3 بار)"
echo "  3. ✓ تکمیل فایل‌های ناقص"
echo "  4. ✓ UI با Gradio"
echo "  5. ✓ اسکریپت‌های مدیریت"
echo ""
echo -e "${YELLOW}مراحل بعدی:${NC}"
echo "  1. اجرای setup اولیه (اگر هنوز نکردید)"
echo "  2. ./pull-model.sh (دانلود مدل)"
echo "  3. ./start.sh (راه‌اندازی)"
echo "  4. مراجعه به http://localhost:7860"
echo ""
echo -e "${BLUE}دستورات مفید:${NC}"
echo "  ./start.sh      - راه‌اندازی"
echo "  ./stop.sh       - توقف"
echo "  ./logs.sh       - مشاهده لاگ‌ها"
echo "  ./status.sh     - وضعیت سیستم"
echo ""


این شل:
- فایل‌های ناقص را تکمیل می‌کند
- Auto-Fix Loop را اضافه می‌کند (اصلاح خودکار کد)
- Lazy loading برای embedding model (صرفه‌جویی RAM)
- UI کامل با Gradio
- اسکریپت‌های مدیریت (start/stop/logs/status)

حالا سیستم تو یک Agent واقعی است که می‌تواند کد بنویسد، اجرا کند، و در صورت خطا خودش اصلاح کند.