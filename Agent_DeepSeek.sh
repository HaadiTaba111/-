#!/bin/bash
# smart_agent_system.sh

echo "🚀 راه اندازی سیستم عامل هوشمند با Agent اجرایی"
echo "================================================"

# تنظیمات
PROJECT_DIR="$HOME/smart_agent_system"
MODEL_NAME="qwen2.5-4b-instruct-q4_k_m.gguf"
MODEL_URL="https://huggingface.co/Qwen/Qwen2.5-4B-Instruct-GGUF/resolve/main/qwen2.5-4b-instruct-q4_k_m.gguf"
PORT=5000

# ایجاد دایرکتوری‌ها
create_directories() {
    echo "📁 ایجاد ساختار دایرکتوری‌ها..."
    
    mkdir -p $PROJECT_DIR
    cd $PROJECT_DIR
    
    mkdir -p {models,agents,memory,dashboard,tasks,logs,scripts}
    
    echo "✅ ساختار دایرکتوری‌ها ایجاد شد"
}

# دانلود مدل
download_model() {
    echo "📥 بررسی وجود مدل..."
    
    if [ ! -f "models/$MODEL_NAME" ]; then
        echo "🔽 دانلود مدل از HuggingFace..."
        wget -O "models/$MODEL_NAME" "$MODEL_URL"
        
        if [ $? -eq 0 ]; then
            echo "✅ مدل با موفقیت دانلود شد"
        else
            echo "❌ خطا در دانلود مدل"
            echo "📝 لینک دانلود دستی: $MODEL_URL"
            exit 1
        fi
    else
        echo "✅ مدل از قبل وجود دارد"
    fi
}

# نصب dependencies
install_dependencies() {
    echo "📦 نصب کتابخانه‌های پایتون..."
    
    # ایجاد virtual environment
    python3 -m venv venv
    source venv/bin/activate
    
    # نصب requirements
    cat > requirements.txt << 'EOF'
llama-cpp-python>=0.2.56
flask>=2.3.0
flask-cors>=4.0.0
flask-socketio>=5.3.0
eventlet>=0.33.0
psutil>=5.9.0
sqlalchemy>=2.0.0
apscheduler>=3.10.0
python-dotenv>=1.0.0
requests>=2.31.0
pyyaml>=6.0
EOF
    
    pip install --upgrade pip
    pip install -r requirements.txt
    
    echo "✅ کتابخانه‌ها نصب شدند"
}

# ایجاد فایل‌های پایتون
create_python_files() {
    echo "📝 ایجاد فایل‌های سیستم..."
    
    # 1. فایل پیکربندی
    cat > config.yaml << 'EOF'
system:
  name: "Smart Agent System"
  version: "1.0.0"
  
model:
  path: "models/qwen2.5-4b-instruct-q4_k_m.gguf"
  context_size: 8192
  temperature: 0.7
  max_tokens: 1024
  
agent:
  max_retries: 3
  timeout_seconds: 30
  ask_permission: true
  
memory:
  db_path: "memory/agent_memory.db"
  backup_interval_hours: 6
  
security:
  allowed_commands:
    - "ls"
    - "cd"
    - "mkdir"
    - "rm"
    - "cp"
    - "mv"
    - "cat"
    - "grep"
    - "find"
    - "ps"
    - "df"
    - "du"
  restricted_paths:
    - "/etc"
    - "/root"
    - "/var"
    - "/usr/bin"
EOF

    # 2. فایل main.py
    cat > main.py << 'EOF'
#!/usr/bin/env python3
"""
سیستم عامل هوشمند با Agent اجرایی
"""

import os
import sys
import json
import yaml
import logging
from datetime import datetime
from flask import Flask, render_template, request, jsonify, session
from flask_socketio import SocketIO, emit
from flask_cors import CORS
import threading
import sqlite3
from pathlib import Path

# اضافه کردن مسیر پروژه
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from agents.brain_agent import BrainAgent
from agents.executive_agent import ExecutiveAgent
from memory.memory_manager import MemoryManager

# تنظیمات لاگ
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/system.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# بارگذاری کانفیگ
with open('config.yaml', 'r') as f:
    config = yaml.safe_load(f)

app = Flask(__name__)
app.secret_key = os.urandom(24)
CORS(app)
socketio = SocketIO(app, cors_allowed_origins="*")

# ایجاد instanceهای اصلی
memory_manager = MemoryManager(config['memory']['db_path'])
brain_agent = BrainAgent(config['model'], memory_manager)
executive_agent = ExecutiveAgent(config['agent'], memory_manager, brain_agent)

@app.route('/')
def index():
    """صفحه اصلی داشبورد"""
    return render_template('dashboard.html')

@app.route('/api/chat', methods=['POST'])
def chat():
    """API چت با مغز"""
    try:
        data = request.json
        user_message = data.get('message', '')
        session_id = data.get('session_id', 'default')
        
        if not user_message:
            return jsonify({'error': 'پیام خالی است'}), 400
        
        # ارسال به مغز برای پردازش
        response = brain_agent.process_message(user_message, session_id)
        
        return jsonify({
            'response': response,
            'session_id': session_id,
            'timestamp': datetime.now().isoformat()
        })
        
    except Exception as e:
        logger.error(f"خطا در API چت: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/execute', methods=['POST'])
def execute_task():
    """اجرای یک task توسط Agent اجرایی"""
    try:
        data = request.json
        task_description = data.get('task', '')
        ask_permission = data.get('ask_permission', True)
        
        if not task_description:
            return jsonify({'error': 'Task description is empty'}), 400
        
        # اجرای task
        result = executive_agent.execute_task(
            task_description=task_description,
            ask_permission=ask_permission,
            user_session=session.get('user_id', 'anonymous')
        )
        
        return jsonify(result)
        
    except Exception as e:
        logger.error(f"خطا در اجرای task: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/tasks', methods=['GET'])
def get_tasks():
    """دریافت لیست tasks"""
    try:
        tasks = memory_manager.get_recent_tasks(limit=50)
        return jsonify({'tasks': tasks})
    except Exception as e:
        logger.error(f"خطا در دریافت tasks: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/errors', methods=['GET'])
def get_errors():
    """دریافت لیست خطاها"""
    try:
        errors = memory_manager.get_recent_errors(limit=50)
        return jsonify({'errors': errors})
    except Exception as e:
        logger.error(f"خطا در دریافت errors: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/learnings', methods=['GET'])
def get_learnings():
    """دریافت یادگیری‌ها"""
    try:
        learnings = memory_manager.get_learned_patterns(limit=50)
        return jsonify({'learnings': learnings})
    except Exception as e:
        logger.error(f"خطا در دریافت learnings: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/stats', methods=['GET'])
def get_stats():
    """آمار سیستم"""
    try:
        stats = {
            'total_tasks': memory_manager.get_total_tasks(),
            'successful_tasks': memory_manager.get_successful_tasks(),
            'failed_tasks': memory_manager.get_failed_tasks(),
            'total_errors': memory_manager.get_total_errors(),
            'learned_patterns': memory_manager.get_total_learned_patterns(),
            'brain_status': brain_agent.get_status(),
            'executive_status': executive_agent.get_status(),
            'memory_usage_mb': memory_manager.get_memory_usage_mb()
        }
        return jsonify(stats)
    except Exception as e:
        logger.error(f"خطا در دریافت stats: {e}")
        return jsonify({'error': str(e)}), 500

@socketio.on('connect')
def handle_connect():
    """اتصال SocketIO"""
    logger.info('Client connected')
    emit('status', {'message': 'Connected to Smart Agent System'})

@socketio.on('request_task_execution')
def handle_task_execution(data):
    """درخواست اجرای task از طریق WebSocket"""
    try:
        task_id = data.get('task_id')
        task_data = data.get('task_data')
        
        # اجرای task
        result = executive_agent.execute_task(
            task_description=task_data['description'],
            ask_permission=False,  # از طریق WebSocket قبلاً تأیید شده
            user_session=data.get('user_id')
        )
        
        emit('task_result', {
            'task_id': task_id,
            'result': result
        })
        
    except Exception as e:
        logger.error(f"خطا در اجرای task از طریق WebSocket: {e}")
        emit('task_error', {
            'task_id': data.get('task_id'),
            'error': str(e)
        })

def start_background_tasks():
    """شروع taskهای background"""
    logger.info("Starting background tasks...")
    
    # شروع memory cleanup scheduler
    memory_manager.start_cleanup_scheduler()
    
    # شروع health check
    executive_agent.start_health_check()

if __name__ == '__main__':
    # شروع background tasks
    bg_thread = threading.Thread(target=start_background_tasks, daemon=True)
    bg_thread.start()
    
    logger.info(f"🚀 شروع سیستم عامل هوشمند روی پورت {config.get('port', 5000)}")
    logger.info(f"📊 حافظه سیستم: {memory_manager.get_memory_usage_mb()} MB")
    logger.info(f"🧠 وضعیت Brain Agent: {brain_agent.get_status()}")
    logger.info(f"⚡ وضعیت Executive Agent: {executive_agent.get_status()}")
    
    socketio.run(
        app,
        host='0.0.0.0',
        port=config.get('port', 5000),
        debug=False,
        allow_unsafe_werkzeug=True
    )
EOF

    # 3. فایل agents/brain_agent.py
    mkdir -p agents
    cat > agents/brain_agent.py << 'EOF'
"""
Brain Agent - مغز هوشمند سیستم
"""

import json
import sqlite3
from datetime import datetime
from typing import Dict, List, Optional, Tuple
import hashlib
from llama_cpp import Llama
import yaml
import logging

logger = logging.getLogger(__name__)

class BrainAgent:
    def __init__(self, model_config: Dict, memory_manager):
        self.model_config = model_config
        self.memory = memory_manager
        self.model = None
        self.is_loaded = False
        self.load_model()
        
    def load_model(self):
        """بارگذاری مدل LLM"""
        try:
            logger.info(f"🧠 در حال بارگذاری مدل از: {self.model_config['path']}")
            
            self.model = Llama(
                model_path=self.model_config['path'],
                n_ctx=self.model_config.get('context_size', 8192),
                n_threads=4,
                n_gpu_layers=self.model_config.get('gpu_layers', 0),
                verbose=False
            )
            
            self.is_loaded = True
            logger.info("✅ مدل با موفقیت بارگذاری شد")
            
        except Exception as e:
            logger.error(f"❌ خطا در بارگذاری مدل: {e}")
            self.is_loaded = False
    
    def process_message(self, message: str, session_id: str = "default") -> str:
        """پردازش پیام کاربر"""
        if not self.is_loaded:
            return "❌ مدل بارگذاری نشده است. لطفا صبر کنید..."
        
        try:
            # دریافت تاریخچه مکالمه
            history = self.memory.get_conversation_history(session_id, limit=5)
            
            # دریافت یادگیری‌های مرتبط
            relevant_learnings = self.memory.get_relevant_learnings(message)
            
            # ساخت prompt
            prompt = self._build_prompt(message, history, relevant_learnings)
            
            # تولید پاسخ
            response = self._generate_response(prompt)
            
            # ذخیره مکالمه
            self.memory.save_conversation(session_id, message, response)
            
            # استخراج و ذخیره یادگیری
            self._extract_and_save_learning(message, response)
            
            return response
            
        except Exception as e:
            logger.error(f"خطا در پردازش پیام: {e}")
            return f"خطا در پردازش: {str(e)}"
    
    def analyze_error(self, error_data: Dict) -> Dict:
        """تحلیل خطا و ارائه راه‌حل"""
        if not self.is_loaded:
            return {"solution": "مدل در دسترس نیست", "retry": False}
        
        try:
            error_context = json.dumps(error_data, ensure_ascii=False)
            
            prompt = f"""
            خطای زیر در سیستم رخ داده است:
            
            {error_context}
            
            لطفا:
            1. علت خطا را تحلیل کن
            2. راه‌حل پیشنهادی بده
            3. مشخص کن آیا باید دوباره تلاش کرد (retry) یا نه
            
            پاسخ را به صورت JSON با فیلدهای زیر برگردان:
            - analysis: تحلیل خطا
            - solution: راه‌حل پیشنهادی
            - retry: true/false
            - confidence: اطمینان از تحلیل (0-1)
            """
            
            response = self._generate_response(prompt, max_tokens=500)
            
            # پارس کردن پاسخ JSON
            try:
                result = json.loads(response)
            except:
                # اگر JSON نبود، ساختار دستی بساز
                result = {
                    "analysis": "خطا در پارس کردن پاسخ مدل",
                    "solution": "لاگ خطا را بررسی کنید",
                    "retry": False,
                    "confidence": 0.0
                }
            
            # ذخیره تحلیل خطا
            self.memory.save_error_analysis(error_data, result)
            
            return result
            
        except Exception as e:
            logger.error(f"خطا در تحلیل خطا: {e}")
            return {
                "analysis": f"خطا در تحلیل: {str(e)}",
                "solution": "خطای سیستمی رخ داده است",
                "retry": False,
                "confidence": 0.0
            }
    
    def plan_task_execution(self, task_description: str) -> Dict:
        """برنامه‌ریزی اجرای task"""
        if not self.is_loaded:
            return {"steps": [], "resources": [], "estimated_time": 0}
        
        try:
            prompt = f"""
            برای انجام task زیر، یک برنامه اجرایی ایجاد کن:
            
            Task: {task_description}
            
            برنامه باید شامل موارد زیر باشد:
            1. مراحل اجرا (steps)
            2. منابع مورد نیاز (resources)
            3. زمان تخمینی (estimated_time در دقیقه)
            4. ریسک‌های احتمالی (risks)
            5. پیش‌نیازها (prerequisites)
            
            پاسخ را به صورت JSON برگردان.
            """
            
            response = self._generate_response(prompt, max_tokens=800)
            
            try:
                plan = json.loads(response)
            except:
                plan = {
                    "steps": ["1. تحلیل task", "2. اجرای دستورات", "3. بررسی نتایج"],
                    "resources": ["سیستم عامل", "دسترسی فایل‌سیستم"],
                    "estimated_time": 5,
                    "risks": ["خطای دسترسی", "خطای اجرا"],
                    "prerequisites": ["دسترسی معتبر"]
                }
            
            return plan
            
        except Exception as e:
            logger.error(f"خطا در برنامه‌ریزی task: {e}")
            return {
                "steps": [f"خطا در برنامه‌ریزی: {str(e)}"],
                "resources": [],
                "estimated_time": 0,
                "risks": ["خطای سیستمی"],
                "prerequisites": []
            }
    
    def _build_prompt(self, message: str, history: List, learnings: List) -> str:
        """ساخت prompt برای مدل"""
        prompt = "<|im_start|>system\n"
        prompt += "You are an intelligent assistant with memory and learning capabilities. "
        prompt += "Use conversation history and learned patterns to provide accurate responses.\n"
        
        if learnings:
            prompt += "\nRelevant learned patterns:\n"
            for learning in learnings[:3]:  # فقط ۳ یادگیری مرتبط
                prompt += f"- {learning['pattern']}\n"
        
        prompt += "<|im_end|>\n"
        
        # افزودن تاریخچه
        for conv in history:
            prompt += f"<|im_start|>user\n{conv['user_message']}<|im_end|>\n"
            prompt += f"<|im_start|>assistant\n{conv['assistant_response']}<|im_end|>\n"
        
        # پیام فعلی
        prompt += f"<|im_start|>user\n{message}<|im_end|>\n"
        prompt += "<|im_start|>assistant\n"
        
        return prompt
    
    def _generate_response(self, prompt: str, max_tokens: int = 1024) -> str:
        """تولید پاسخ از مدل"""
        try:
            output = self.model(
                prompt,
                max_tokens=max_tokens,
                temperature=self.model_config.get('temperature', 0.7),
                top_p=0.9,
                stop=["</s>", "<|im_end|>"],
                echo=False
            )
            
            response = output['choices'][0]['text'].strip()
            return response
            
        except Exception as e:
            logger.error(f"خطا در تولید پاسخ: {e}")
            return f"خطا در تولید پاسخ: {str(e)}"
    
    def _extract_and_save_learning(self, user_input: str, response: str):
        """استخراج و ذخیره یادگیری از مکالمه"""
        try:
            # استخراج الگوهای کلیدی
            learning_data = {
                "input_pattern": user_input[:100],  # ۱۰۰ کاراکتر اول
                "response_pattern": response[:200],  # ۲۰۰ کاراکتر اول
                "timestamp": datetime.now().isoformat(),
                "session_id": hashlib.md5(user_input.encode()).hexdigest()[:10]
            }
            
            # ذخیره در حافظه
            self.memory.save_learning(learning_data)
            
        except Exception as e:
            logger.error(f"خطا در استخراج یادگیری: {e}")
    
    def get_status(self) -> str:
        """دریافت وضعیت agent"""
        if self.is_loaded:
            return "🟢 فعال"
        else:
            return "🔴 غیرفعال"
EOF

    # 4. فایل agents/executive_agent.py
    cat > agents/executive_agent.py << 'EOF'
"""
Executive Agent - مجری اجرای دستورات
"""

import subprocess
import os
import sys
import json
import time
import threading
from datetime import datetime
from typing import Dict, List, Optional, Tuple
import logging
import shlex
from pathlib import Path

logger = logging.getLogger(__name__)

class ExecutiveAgent:
    def __init__(self, agent_config: Dict, memory_manager, brain_agent):
        self.config = agent_config
        self.memory = memory_manager
        self.brain = brain_agent
        self.running_tasks = {}
        self.task_counter = 0
        self.allowed_commands = agent_config.get('allowed_commands', [])
        self.restricted_paths = agent_config.get('restricted_paths', [])
        
    def execute_task(self, task_description: str, ask_permission: bool = True, user_session: str = "anonymous") -> Dict:
        """اجرای یک task"""
        task_id = f"task_{self.task_counter}_{int(time.time())}"
        self.task_counter += 1
        
        logger.info(f"🎯 شروع task {task_id}: {task_description}")
        
        # ذخیره task در حافظه
        task_record = {
            "task_id": task_id,
            "description": task_description,
            "user_session": user_session,
            "start_time": datetime.now().isoformat(),
            "status": "pending"
        }
        self.memory.save_task(task_record)
        
        try:
            # 1. برنامه‌ریزی توسط مغز
            logger.info(f"🧠 برنامه‌ریزی task {task_id}")
            plan = self.brain.plan_task_execution(task_description)
            
            # 2. اگر نیاز به تأیید کاربر است
            if ask_permission and self.config.get('ask_permission', True):
                # در اینجا می‌توانید از طریق API یا WebSocket از کاربر تأیید بگیرید
                logger.info(f"⏳ در انتظار تأیید کاربر برای task {task_id}")
                # فعلاً تأیید شده فرض می‌شود
                pass
            
            # 3. اجرای مراحل
            results = []
            for i, step in enumerate(plan.get('steps', []), 1):
                step_result = self._execute_step(step, task_id, i)
                results.append(step_result)
                
                # اگر خطا رخ داد، متوقف شو
                if not step_result.get('success', False):
                    break
            
            # 4. بررسی نتایج
            success = all(r.get('success', False) for r in results)
            
            # 5. ذخیره نتایج
            task_record.update({
                "end_time": datetime.now().isoformat(),
                "status": "completed" if success else "failed",
                "results": results,
                "plan": plan
            })
            self.memory.update_task(task_id, task_record)
            
            # 6. اگر خطا رخ داد، تحلیل توسط مغز
            if not success:
                error_data = {
                    "task_id": task_id,
                    "description": task_description,
                    "results": results,
                    "plan": plan
                }
                
                logger.info(f"🔍 تحلیل خطای task {task_id} توسط مغز")
                error_analysis = self.brain.analyze_error(error_data)
                
                # ذخیره تحلیل خطا
                self.memory.save_error(task_id, error_data, error_analysis)
                
                return {
                    "task_id": task_id,
                    "status": "failed_with_analysis",
                    "results": results,
                    "error_analysis": error_analysis,
                    "message": "Task failed. Error analysis completed."
                }
            
            logger.info(f"✅ تکمیل task {task_id}")
            return {
                "task_id": task_id,
                "status": "completed",
                "results": results,
                "plan": plan,
                "message": "Task completed successfully."
            }
            
        except Exception as e:
            logger.error(f"❌ خطا در اجرای task {task_id}: {e}")
            
            # ذخیره خطا
            error_data = {
                "task_id": task_id,
                "description": task_description,
                "error": str(e),
                "timestamp": datetime.now().isoformat()
            }
            
            task_record.update({
                "end_time": datetime.now().isoformat(),
                "status": "error",
                "error": str(e)
            })
            self.memory.update_task(task_id, task_record)
            
            return {
                "task_id": task_id,
                "status": "error",
                "error": str(e),
                "message": "خطای سیستمی رخ داده است"
            }
    
    def _execute_step(self, step_description: str, task_id: str, step_number: int) -> Dict:
        """اجرای یک مرحله"""
        step_id = f"{task_id}_step_{step_number}"
        
        logger.info(f"   ↳ اجرای مرحله {step_number}: {step_description}")
        
        try:
            # تشخیص نوع مرحله
            if step_description.lower().startswith(("run ", "execute ", "command: ")):
                # اجرای دستور shell
                command = self._extract_command(step_description)
                return self._execute_command(command, step_id)
                
            elif step_description.lower().startswith(("create file", "write to")):
                # ایجاد فایل
                return self._create_file(step_description, step_id)
                
            elif step_description.lower().startswith(("read file", "read from")):
                # خواندن فایل
                return self._read_file(step_description, step_id)
                
            elif step_description.lower().startswith(("check ", "verify ", "validate")):
                # بررسی وضعیت
                return self._check_status(step_description, step_id)
                
            else:
                # مرحله عمومی
                return {
                    "step_id": step_id,
                    "description": step_description,
                    "success": True,
                    "output": "Step executed (no specific action)",
                    "timestamp": datetime.now().isoformat()
                }
                
        except Exception as e:
            logger.error(f"خطا در اجرای مرحله {step_id}: {e}")
            return {
                "step_id": step_id,
                "description": step_description,
                "success": False,
                "error": str(e),
                "timestamp": datetime.now().isoformat()
            }
    
    def _execute_command(self, command: str, step_id: str) -> Dict:
        """اجرای دستور shell با امنیت"""
        
        # بررسی امنیت دستور
        security_check = self._check_command_security(command)
        if not security_check["allowed"]:
            return {
                "step_id": step_id,
                "command": command,
                "success": False,
                "error": f"Command not allowed: {security_check['reason']}",
                "timestamp": datetime.now().isoformat()
            }
        
        try:
            # اجرای دستور
            process = subprocess.run(
                command,
                shell=True,
                capture_output=True,
                text=True,
                timeout=self.config.get('timeout_seconds', 30)
            )
            
            result = {
                "step_id": step_id,
                "command": command,
                "success": process.returncode == 0,
                "return_code": process.returncode,
                "stdout": process.stdout,
                "stderr": process.stderr,
                "timestamp": datetime.now().isoformat()
            }
            
            # ذخیره در لاگ
            self.memory.save_command_execution(step_id, command, result)
            
            return result
            
        except subprocess.TimeoutExpired:
            return {
                "step_id": step_id,
                "command": command,
                "success": False,
                "error": "Command timeout",
                "timestamp": datetime.now().isoformat()
            }
        except Exception as e:
            return {
                "step_id": step_id,
                "command": command,
                "success": False,
                "error": str(e),
                "timestamp": datetime.now().isoformat()
            }
    
    def _check_command_security(self, command: str) -> Dict:
        """بررسی امنیت دستور"""
        
        # استخراج دستور اصلی
        cmd_parts = shlex.split(command)
        if not cmd_parts:
            return {"allowed": False, "reason": "Empty command"}
        
        base_cmd = cmd_parts[0].lower()
        
        # بررسی دستورهای مجاز
        if base_cmd not in self.allowed_commands:
            return {"allowed": False, "reason": f"Command '{base_cmd}' not in allowed list"}
        
        # بررسی مسیرهای محدود شده
        for part in cmd_parts:
            for restricted in self.restricted_paths:
                if restricted in part:
                    return {"allowed": False, "reason": f"Access to restricted path: {restricted}"}
        
        # بررسی دستورهای خطرناک
        dangerous_patterns = ["rm -rf /", "dd if=", "mkfs", ":(){:|:&};:"]
        for pattern in dangerous_patterns:
            if pattern in command:
                return {"allowed": False, "reason": f"Dangerous pattern detected: {pattern}"}
        
        return {"allowed": True, "reason": "Command is safe"}
    
    def _extract_command(self, step_description: str) -> str:
        """استخراج دستور از توصیف مرحله"""
        # الگوهای ساده برای استخراج
        prefixes = ["run ", "execute ", "command: ", "cmd: "]
        
        for prefix in prefixes:
            if step_description.lower().startswith(prefix):
                return step_description[len(prefix):].strip()
        
        return step_description
    
    def _create_file(self, step_description: str, step_id: str) -> Dict:
        """ایجاد فایل"""
        try:
            # استخراج مسیر و محتوا
            # این یک پیاده‌سازی ساده است - می‌توانید بهبود دهید
            lines = step_description.split('\n')
            path_line = lines[0]
            
            # پیدا کردن مسیر فایل
            import re
            path_match = re.search(r'/(?:[^/\s]+/)*[^/\s]+(?:\.[^/\s]+)?', path_line)
            
            if not path_match:
                return {
                    "step_id": step_id,
                    "description": step_description,
                    "success": False,
                    "error": "Could not extract file path",
                    "timestamp": datetime.now().isoformat()
                }
            
            file_path = path_match.group(0)
            content = '\n'.join(lines[1:]) if len(lines) > 1 else ""
            
            # ایجاد دایرکتوری اگر وجود ندارد
            os.makedirs(os.path.dirname(file_path), exist_ok=True)
            
            # نوشتن فایل
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(content)
            
            return {
                "step_id": step_id,
                "description": step_description,
                "success": True,
                "output": f"File created: {file_path}",
                "file_path": file_path,
                "timestamp": datetime.now().isoformat()
            }
            
        except Exception as e:
            return {
                "step_id": step_id,
                "description": step_description,
                "success": False,
                "error": str(e),
                "timestamp": datetime.now().isoformat()
            }
    
    def _read_file(self, step_description: str, step_id: str) -> Dict:
        """خواندن فایل"""
        try:
            # استخراج مسیر فایل
            import re
            path_match = re.search(r'/(?:[^/\s]+/)*[^/\s]+(?:\.[^/\s]+)?', step_description)
            
            if not path_match:
                return {
                    "step_id": step_id,
                    "description": step_description,
                    "success": False,
                    "error": "Could not extract file path",
                    "timestamp": datetime.now().isoformat()
                }
            
            file_path = path_match.group(0)
            
            # خواندن فایل
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            return {
                "step_id": step_id,
                "description": step_description,
                "success": True,
                "output": f"File read: {file_path}",
                "content": content[:1000],  # فقط ۱۰۰۰ کاراکتر اول
                "timestamp": datetime.now().isoformat()
            }
            
        except Exception as e:
            return {
                "step_id": step_id,
                "description": step_description,
                "success": False,
                "error": str(e),
                "timestamp": datetime.now().isoformat()
            }
    
    def _check_status(self, step_description: str, step_id: str) -> Dict:
        """بررسی وضعیت سیستم"""
        try:
            # بررسی‌های مختلف
            checks = []
            
            # بررسی فضای دیسک
            disk_usage = shutil.disk_usage("/")
            checks.append({
                "check": "disk_usage",
                "status": "ok" if disk_usage.free > 1e9 else "warning",  # کمتر از 1GB
                "details": f"Free: {disk_usage.free / 1e9:.2f} GB"
            })
            
            # بررسی حافظه
            import psutil
            memory = psutil.virtual_memory()
            checks.append({
                "check": "memory_usage",
                "status": "ok" if memory.percent < 90 else "warning",
                "details": f"Usage: {memory.percent}%"
            })
            
            # بررسی CPU
            cpu_percent = psutil.cpu_percent(interval=1)
            checks.append({
                "check": "cpu_usage",
                "status": "ok" if cpu_percent < 80 else "warning",
                "details": f"Usage: {cpu_percent}%"
            })
            
            return {
                "step_id": step_id,
                "description": step_description,
                "success": True,
                "output": "System checks completed",
                "checks": checks,
                "timestamp": datetime.now().isoformat()
            }
            
        except Exception as e:
            return {
                "step_id": step_id,
                "description": step_description,
                "success": False,
                "error": str(e),
                "timestamp": datetime.now().isoformat()
            }
    
    def ask_permission(self, task_description: str, plan: Dict) -> bool:
        """درخواست تأیید از کاربر"""
        # این تابع می‌تواند از طریق WebSocket یا API با کاربر ارتباط برقرار کند
        # فعلاً true برمی‌گرداند
        return True
    
    def start_health_check(self):
        """شروع بررسی سلامت دوره‌ای"""
        def health_check_loop():
            while True:
                try:
                    # بررسی سلامت سیستم
                    status = self.get_status()
                    logger.info(f"🏥 Health check: {status}")
                    
                    # ذخیره در حافظه
                    self.memory.save_health_check({
                        "timestamp": datetime.now().isoformat(),
                        "status": status,
                        "running_tasks": len(self.running_tasks)
                    })
                    
                except Exception as e:
                    logger.error(f"خطا در health check: {e}")
                
                time.sleep(300)  # هر ۵ دقیقه
        
        thread = threading.Thread(target=health_check_loop, daemon=True)
        thread.start()
    
    def get_status(self) -> str:
        """دریافت وضعیت agent"""
        return "🟢 فعال" if self.brain.is_loaded else "🟡 در حال بارگذاری"
EOF

    # 5. فایل memory/memory_manager.py
    mkdir -p memory
    cat > memory/memory_manager.py << 'EOF'
"""
Memory Manager - سیستم حافظه و ذخیره‌سازی
"""

import sqlite3
import json
import hashlib
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
import logging
from pathlib import Path
import threading
import time

logger = logging.getLogger(__name__)

class MemoryManager:
    def __init__(self, db_path: str = "memory/agent_memory.db"):
        self.db_path = db_path
        self.conn = None
        self.lock = threading.Lock()
        self.init_database()
        self.setup_cleanup_job()
    
    def init_database(self):
        """راه‌اندازی پایگاه داده"""
        try:
            # ایجاد دایرکتوری اگر وجود ندارد
            Path(self.db_path).parent.mkdir(parents=True, exist_ok=True)
            
            self.conn = sqlite3.connect(self.db_path, check_same_thread=False)
            self.conn.row_factory = sqlite3.Row
            
            self._create_tables()
            logger.info(f"✅ پایگاه داده در {self.db_path} راه‌اندازی شد")
            
        except Exception as e:
            logger.error(f"❌ خطا در راه‌اندازی پایگاه داده: {e}")
            raise
    
    def _create_tables(self):
        """ایجاد جداول پایگاه داده"""
        cursor = self.conn.cursor()
        
        # جدول مکالمات
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS conversations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                user_message TEXT NOT NULL,
                assistant_response TEXT NOT NULL,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                embedding_hash TEXT,
                metadata TEXT
            )
        """)
        
        # جدول tasks
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS tasks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                task_id TEXT UNIQUE NOT NULL,
                description TEXT NOT NULL,
                user_session TEXT,
                status TEXT NOT NULL,
                plan TEXT,
                results TEXT,
                error TEXT,
                start_time DATETIME,
                end_time DATETIME,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        """)
        
        # جدول خطاها
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS errors (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                task_id TEXT NOT NULL,
                error_data TEXT NOT NULL,
                analysis TEXT,
                solution TEXT,
                resolved BOOLEAN DEFAULT 0,
                resolved_at DATETIME,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        """)
        
        # جدول یادگیری‌ها
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS learnings (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                pattern_hash TEXT UNIQUE NOT NULL,
                pattern_type TEXT NOT NULL,
                pattern_data TEXT NOT NULL,
                success_count INTEGER DEFAULT 0,
                failure_count INTEGER DEFAULT 0,
                last_used DATETIME,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        """)
        
        # جدول اجرای دستورات
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS command_executions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                step_id TEXT NOT NULL,
                command TEXT NOT NULL,
                result TEXT NOT NULL,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        """)
        
        # جدول health checks
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS health_checks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                status TEXT NOT NULL,
                details TEXT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        """)
        
        # جدول daily_tasks
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS daily_tasks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                task_name TEXT NOT NULL,
                task_description TEXT NOT NULL,
                schedule TEXT,
                last_executed DATETIME,
                next_execution DATETIME,
                enabled BOOLEAN DEFAULT 1,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        """)
        
        # ایجاد ایندکس‌ها
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_conversations_session ON conversations(session_id)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_conversations_timestamp ON conversations(timestamp)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_tasks_user ON tasks(user_session)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_errors_resolved ON errors(resolved)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_learnings_pattern ON learnings(pattern_hash)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_learnings_last_used ON learnings(last_used)")
        
        self.conn.commit()
        logger.info("✅ جداول پایگاه داده ایجاد شدند")
    
    def save_conversation(self, session_id: str, user_message: str, assistant_response: str):
        """ذخیره مکالمه"""
        with self.lock:
            try:
                cursor = self.conn.cursor()
                
                # محاسبه hash برای جستجوی سریع
                message_hash = hashlib.md5(user_message.encode()).hexdigest()
                
                cursor.execute("""
                    INSERT INTO conversations 
                    (session_id, user_message, assistant_response, embedding_hash)
                    VALUES (?, ?, ?, ?)
                """, (session_id, user_message, assistant_response, message_hash))
                
                self.conn.commit()
                
            except Exception as e:
                logger.error(f"خطا در ذخیره مکالمه: {e}")
                self.conn.rollback()
    
    def get_conversation_history(self, session_id: str, limit: int = 10) -> List[Dict]:
        """دریافت تاریخچه مکالمه"""
        with self.lock:
            try:
                cursor = self.conn.cursor()
                cursor.execute("""
                    SELECT user_message, assistant_response, timestamp
                    FROM conversations 
                    WHERE session_id = ? 
                    ORDER BY timestamp DESC 
                    LIMIT ?
                """, (session_id, limit))
                
                rows = cursor.fetchall()
                history = []
                
                for row in rows:
                    history.append({
                        "user_message": row["user_message"],
                        "assistant_response": row["assistant_response"],
                        "timestamp": row["timestamp"]
                    })
                
                return history[::-1]  # مرتب کردن از قدیمی به جدید
                
            except Exception as e:
                logger.error(f"خطا در دریافت تاریخچه مکالمه: {e}")
                return []
    
    def save_task(self, task_data: Dict):
        """ذخیره task"""
        with self.lock:
            try:
                cursor = self.conn.cursor()
                
                cursor.execute("""
                    INSERT INTO tasks 
                    (task_id, description, user_session, status, start_time)
                    VALUES (?, ?, ?, ?, ?)
                """, (
                    task_data["task_id"],
                    task_data["description"],
                    task_data.get("user_session", "anonymous"),
                    task_data.get("status", "pending"),
                    task_data.get("start_time", datetime.now().isoformat())
                ))
                
                self.conn.commit()
                logger.info(f"✅ Task ذخیره شد: {task_data['task_id']}")
                
            except Exception as e:
                logger.error(f"خطا در ذخیره task: {e}")
                self.conn.rollback()
    
    def update_task(self, task_id: str, task_data: Dict):
        """به‌روزرسانی task"""
        with self.lock:
            try:
                cursor = self.conn.cursor()
                
                # تبدیل دیکشنری‌ها به JSON
                plan_json = json.dumps(task_data.get("plan", {})) if "plan" in task_data else None
                results_json = json.dumps(task_data.get("results", [])) if "results" in task_data else None
                
                cursor.execute("""
                    UPDATE tasks 
                    SET status = ?, 
                        plan = ?, 
                        results = ?, 
                        error = ?, 
                        end_time = ?
                    WHERE task_id = ?
                """, (
                    task_data.get("status", "unknown"),
                    plan_json,
                    results_json,
                    task_data.get("error"),
                    task_data.get("end_time"),
                    task_id
                ))
                
                self.conn.commit()
                logger.info(f"✅ Task به‌روزرسانی شد: {task_id}")
                
            except Exception as e:
                logger.error(f"خطا در به‌روزرسانی task: {e}")
                self.conn.rollback()
    
    def get_recent_tasks(self, limit: int = 50) -> List[Dict]:
        """دریافت tasks اخیر"""
        with self.lock:
            try:
                cursor = self.conn.cursor()
                cursor.execute("""
                    SELECT * FROM tasks 
                    ORDER BY created_at DESC 
                    LIMIT ?
                """, (limit,))
                
                rows = cursor.fetchall()
                tasks = []
                
                for row in rows:
                    task = dict(row)
                    
                    # پارس کردن JSON فیلدها
                    if task.get("plan"):
                        try:
                            task["plan"] = json.loads(task["plan"])
                        except:
                            task["plan"] = {}
                    
                    if task.get("results"):
                        try:
                            task["results"] = json.loads(task["results"])
                        except:
                            task["results"] = []
                    
                    tasks.append(task)
                
                return tasks
                
            except Exception as e:
                logger.error(f"خطا در دریافت tasks: {e}")
                return []
    
    def save_error(self, task_id: str, error_data: Dict, analysis: Dict = None):
        """ذخیره خطا"""
        with self.lock:
            try:
                cursor = self.conn.cursor()
                
                error_json = json.dumps(error_data, ensure_ascii=False)
                analysis_json = json.dumps(analysis, ensure_ascii=False) if analysis else None
                
                cursor.execute("""
                    INSERT INTO errors 
                    (task_id, error_data, analysis, solution, resolved)
                    VALUES (?, ?, ?, ?, ?)
                """, (
                    task_id,
                    error_json,
                    analysis_json,
                    analysis.get("solution") if analysis else None,
                    0  # unresolved
                ))
                
                self.conn.commit()
                logger.info(f"✅ خطا ذخیره شد برای task: {task_id}")
                
            except Exception as e:
                logger.error(f"خطا در ذخیره خطا: {e}")
                self.conn.rollback()
    
    def save_error_analysis(self, error_data: Dict, analysis: Dict):
        """ذخیره تحلیل خطا"""
        with self.lock:
            try:
                cursor = self.conn.cursor()
                
                error_json = json.dumps(error_data, ensure_ascii=False)
                analysis_json = json.dumps(analysis, ensure_ascii=False)
                
                cursor.execute("""
                    INSERT INTO errors 
                    (task_id, error_data, analysis, solution)
                    VALUES (?, ?, ?, ?)
                """, (
                    error_data.get("task_id", "unknown"),
                    error_json,
                    analysis_json,
                    analysis.get("solution", "No solution provided")
                ))
                
                self.conn.commit()
                
            except Exception as e:
                logger.error(f"خطا در ذخیره تحلیل خطا: {e}")
                self.conn.rollback()
    
    def get_recent_errors(self, limit: int = 50) -> List[Dict]:
        """دریافت خطاهای اخیر"""
        with self.lock:
            try:
                cursor = self.conn.cursor()
                cursor.execute("""
                    SELECT * FROM errors 
                    ORDER BY created_at DESC 
                    LIMIT ?
                """, (limit,))
                
                rows = cursor.fetchall()
                errors = []
                
                for row in rows:
                    error = dict(row)
                    
                    # پارس کردن JSON فیلدها
                    if error.get("error_data"):
                        try:
                            error["error_data"] = json.loads(error["error_data"])
                        except:
                            error["error_data"] = {}
                    
                    if error.get("analysis"):
                        try:
                            error["analysis"] = json.loads(error["analysis"])
                        except:
                            error["analysis"] = {}
                    
                    errors.append(error)
                
                return errors
                
            except Exception as e:
                logger.error(f"خطا در دریافت خطاها: {e}")
                return []
    
    def save_learning(self, learning_data: Dict):
        """ذخیره یادگیری"""
        with self.lock:
            try:
                cursor = self.conn.cursor()
                
                pattern_hash = hashlib.md5(
                    f"{learning_data['input_pattern']}_{learning_data['response_pattern']}".encode()
                ).hexdigest()
                
                pattern_json = json.dumps(learning_data, ensure_ascii=False)
                
                # بررسی وجود pattern
                cursor.execute("SELECT id FROM learnings WHERE pattern_hash = ?", (pattern_hash,))
                existing = cursor.fetchone()
                
                if existing:
                    # به‌روزرسانی
                    cursor.execute("""
                        UPDATE learnings 
                        SET success_count = success_count + 1,
                            last_used = CURRENT_TIMESTAMP
                        WHERE pattern_hash = ?
                    """, (pattern_hash,))
                else:
                    # درج جدید
                    cursor.execute("""
                        INSERT INTO learnings 
                        (pattern_hash, pattern_type, pattern_data, success_count, last_used)
                        VALUES (?, ?, ?, ?, ?)
                    """, (
                        pattern_hash,
                        "conversation_pattern",
                        pattern_json,
                        1,
                        datetime.now().isoformat()
                    ))
                
                self.conn.commit()
                
            except Exception as e:
                logger.error(f"خطا در ذخیره یادگیری: {e}")
                self.conn.rollback()
    
    def get_relevant_learnings(self, query: str, limit: int = 5) -> List[Dict]:
        """دریافت یادگیری‌های مرتبط"""
        with self.lock:
            try:
                cursor = self.conn.cursor()
                
                # جستجوی ساده بر اساس کلمات کلیدی
                keywords = query.lower().split()[:5]  # ۵ کلمه اول
                
                if not keywords:
                    return []
                
                # ساخت query برای جستجو
                like_conditions = " OR ".join(["pattern_data LIKE ?"] * len(keywords))
                params = [f"%{keyword}%" for keyword in keywords]
                
                cursor.execute(f"""
                    SELECT pattern_data, success_count, last_used
                    FROM learnings 
                    WHERE {like_conditions}
                    ORDER BY success_count DESC, last_used DESC
                    LIMIT ?
                """, params + [limit])
                
                rows = cursor.fetchall()
                learnings = []
                
                for row in rows:
                    try:
                        pattern_data = json.loads(row["pattern_data"])
                        learnings.append({
                            "pattern": pattern_data.get("input_pattern", ""),
                            "response": pattern_data.get("response_pattern", ""),
                            "success_count": row["success_count"],
                            "last_used": row["last_used"]
                        })
                    except:
                        continue
                
                return learnings
                
            except Exception as e:
                logger.error(f"خطا در دریافت یادگیری‌ها: {e}")
                return []
    
    def get_learned_patterns(self, limit: int = 50) -> List[Dict]:
        """دریافت الگوهای یادگیری شده"""
        with self.lock:
            try:
                cursor = self.conn.cursor()
                cursor.execute("""
                    SELECT * FROM learnings 
                    ORDER BY success_count DESC, last_used DESC
                    LIMIT ?
                """, (limit,))
                
                rows = cursor.fetchall()
                patterns = []
                
                for row in rows:
                    pattern = dict(row)
                    
                    if pattern.get("pattern_data"):
                        try:
                            pattern["pattern_data"] = json.loads(pattern["pattern_data"])
                        except:
                            pattern["pattern_data"] = {}
                    
                    patterns.append(pattern)
                
                return patterns
                
            except Exception as e:
                logger.error(f"خطا در دریافت الگوهای یادگیری: {e}")
                return []
    
    def save_command_execution(self, step_id: str, command: str, result: Dict):
        """ذخیره اجرای دستور"""
        with self.lock:
            try:
                cursor = self.conn.cursor()
                
                result_json = json.dumps(result, ensure_ascii=False)
                
                cursor.execute("""
                    INSERT INTO command_executions 
                    (step_id, command, result)
                    VALUES (?, ?, ?)
                """, (step_id, command, result_json))
                
                self.conn.commit()
                
            except Exception as e:
                logger.error(f"خطا در ذخیره اجرای دستور: {e}")
                self.conn.rollback()
    
    def save_health_check(self, health_data: Dict):
        """ذخیره health check"""
        with self.lock:
            try:
                cursor = self.conn.cursor()
                
                details_json = json.dumps(health_data, ensure_ascii=False)
                
                cursor.execute("""
                    INSERT INTO health_checks 
                    (status, details)
                    VALUES (?, ?)
                """, (health_data.get("status", "unknown"), details_json))
                
                self.conn.commit()
                
            except Exception as e:
                logger.error(f"خطا در ذخیره health check: {e}")
                self.conn.rollback()
    
    def setup_cleanup_job(self):
        """تنظیم job پاک‌سازی دوره‌ای"""
        def cleanup_old_data():
            while True:
                try:
                    self._cleanup_old_conversations()
                    self._cleanup_old_health_checks()
                    logger.info("🧹 پاک‌سازی داده‌های قدیمی انجام شد")
                except Exception as e:
                    logger.error(f"خطا در پاک‌سازی داده‌ها: {e}")
                
                time.sleep(3600)  # هر ۱ ساعت
        
        thread = threading.Thread(target=cleanup_old_data, daemon=True)
        thread.start()
    
    def _cleanup_old_conversations(self, days: int = 30):
        """پاک‌سازی مکالمات قدیمی"""
        with self.lock:
            try:
                cursor = self.conn.cursor()
                cutoff_date = (datetime.now() - timedelta(days=days)).isoformat()
                
                cursor.execute("""
                    DELETE FROM conversations 
                    WHERE timestamp < ?
                """, (cutoff_date,))
                
                self.conn.commit()
                logger.info(f"🧹 مکالمات قدیمی‌تر از {days} روز پاک شدند")
                
            except Exception as e:
                logger.error(f"خطا در پاک‌سازی مکالمات: {e}")
    
    def _cleanup_old_health_checks(self, days: int = 7):
        """پاک‌سازی health checks قدیمی"""
        with self.lock:
            try:
                cursor = self.conn.cursor()
                cutoff_date = (datetime.now() - timedelta(days=days)).isoformat()
                
                cursor.execute("""
                    DELETE FROM health_checks 
                    WHERE timestamp < ?
                """, (cutoff_date,))
                
                self.conn.commit()
                
            except Exception as e:
                logger.error(f"خطا در پاک‌سازی health checks: {e}")
    
    def get_total_tasks(self) -> int:
        """تعداد کل tasks"""
        with self.lock:
            try:
                cursor = self.conn.cursor()
                cursor.execute("SELECT COUNT(*) as count FROM tasks")
                return cursor.fetchone()["count"]
            except:
                return 0
    
    def get_successful_tasks(self) -> int:
        """تعداد tasks موفق"""
        with self.lock:
            try:
                cursor = self.conn.cursor()
                cursor.execute("SELECT COUNT(*) as count FROM tasks WHERE status = 'completed'")
                return cursor.fetchone()["count"]
            except:
                return 0
    
    def get_failed_tasks(self) -> int:
        """تعداد tasks ناموفق"""
        with self.lock:
            try:
                cursor = self.conn.cursor()
                cursor.execute("SELECT COUNT(*) as count FROM tasks WHERE status IN ('failed', 'error')")
                return cursor.fetchone()["count"]
            except:
                return 0
    
    def get_total_errors(self) -> int:
        """تعداد کل خطاها"""
        with self.lock:
            try:
                cursor = self.conn.cursor()
                cursor.execute("SELECT COUNT(*) as count FROM errors")
                return cursor.fetchone()["count"]
            except:
                return 0
    
    def get_total_learned_patterns(self) -> int:
        """تعداد کل الگوهای یادگیری شده"""
        with self.lock:
            try:
                cursor = self.conn.cursor()
                cursor.execute("SELECT COUNT(*) as count FROM learnings")
                return cursor.fetchone()["count"]
            except:
                return 0
    
    def get_memory_usage_mb(self) -> float:
        """مقدار حافظه استفاده شده (MB)"""
        try:
            import os
            if os.path.exists(self.db_path):
                size_bytes = os.path.getsize(self.db_path)
                return size_bytes / (1024 * 1024)  # به MB
            return 0.0
        except:
            return 0.0
    
    def start_cleanup_scheduler(self):
        """شروع scheduler پاک‌سازی"""
        # قبلاً در setup_cleanup_job شروع شده
        pass
    
    def close(self):
        """بستن اتصال پایگاه داده"""
        if self.conn:
            self.conn.close()
            logger.info("✅ اتصال پایگاه داده بسته شد")
EOF

    # 6. فایل dashboard.html
    mkdir -p templates
    cat > templates/dashboard.html << 'EOF'
<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>سیستم عامل هوشمند با Agent اجرایی</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <script src="https://cdn.socket.io/4.5.4/socket.io.min.js"></script>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        }
        
        :root {
            --primary: #2563eb;
            --primary-dark: #1d4ed8;
            --secondary: #10b981;
            --danger: #ef4444;
            --warning: #f59e0b;
            --dark: #1f2937;
            --light: #f9fafb;
            --gray: #6b7280;
            --border: #e5e7eb;
        }
        
        body {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
            color: var(--dark);
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
            overflow: hidden;
        }
        
        header {
            background: linear-gradient(to right, var(--primary), var(--primary-dark));
            color: white;
            padding: 25px 40px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            border-bottom: 3px solid rgba(255, 255, 255, 0.1);
        }
        
        .logo {
            display: flex;
            align-items: center;
            gap: 15px;
        }
        
        .logo i {
            font-size: 2.5rem;
            background: rgba(255, 255, 255, 0.2);
            padding: 15px;
            border-radius: 15px;
        }
        
        .logo h1 {
            font-size: 1.8rem;
            font-weight: 700;
        }
        
        .logo p {
            opacity: 0.9;
            font-size: 0.9rem;
        }
        
        .status-indicators {
            display: flex;
            gap: 20px;
        }
        
        .status-item {
            display: flex;
            flex-direction: column;
            align-items: center;
            background: rgba(255, 255, 255, 0.15);
            padding: 15px 25px;
            border-radius: 12px;
            min-width: 120px;
        }
        
        .status-item i {
            font-size: 1.5rem;
            margin-bottom: 8px;
        }
        
        .status-item span {
            font-size: 0.9rem;
            opacity: 0.9;
        }
        
        .status-item .value {
            font-size: 1.4rem;
            font-weight: 700;
            margin-top: 5px;
        }
        
        .main-content {
            display: grid;
            grid-template-columns: 1fr 400px;
            gap: 0;
            min-height: 800px;
        }
        
        .chat-section {
            padding: 30px;
            border-left: 1px solid var(--border);
            display: flex;
            flex-direction: column;
        }
        
        .chat-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 25px;
            padding-bottom: 15px;
            border-bottom: 2px solid var(--border);
        }
        
        .chat-header h2 {
            color: var(--primary);
            font-size: 1.5rem;
        }
        
        .chat-messages {
            flex: 1;
            overflow-y: auto;
            padding: 20px;
            background: var(--light);
            border-radius: 15px;
            margin-bottom: 25px;
            border: 1px solid var(--border);
            max-height: 500px;
        }
        
        .message {
            margin-bottom: 20px;
            padding: 15px 20px;
            border-radius: 15px;
            max-width: 80%;
            animation: fadeIn 0.3s ease;
        }
        
        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(10px); }
            to { opacity: 1; transform: translateY(0); }
        }
        
        .user-message {
            background: linear-gradient(to left, var(--primary), var(--primary-dark));
            color: white;
            margin-right: auto;
            border-bottom-right-radius: 5px;
        }
        
        .assistant-message {
            background: white;
            border: 1px solid var(--border);
            margin-left: auto;
            border-bottom-left-radius: 5px;
            box-shadow: 0 5px 15px rgba(0, 0, 0, 0.05);
        }
        
        .message-header {
            display: flex;
            justify-content: space-between;
            margin-bottom: 8px;
            font-size: 0.85rem;
            opacity: 0.8;
        }
        
        .message-content {
            line-height: 1.6;
        }
        
        .chat-input {
            display: flex;
            gap: 15px;
            margin-top: auto;
        }
        
        .chat-input textarea {
            flex: 1;
            padding: 18px 20px;
            border: 2px solid var(--border);
            border-radius: 12px;
            font-size: 1rem;
            resize: none;
            height: 60px;
            transition: all 0.3s;
        }
        
        .chat-input textarea:focus {
            outline: none;
            border-color: var(--primary);
            box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.1);
        }
        
        .chat-input button {
            background: linear-gradient(to right, var(--secondary), #0da271);
            color: white;
            border: none;
            padding: 0 35px;
            border-radius: 12px;
            font-size: 1rem;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        
        .chat-input button:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 20px rgba(16, 185, 129, 0.3);
        }
        
        .chat-input button:disabled {
            opacity: 0.6;
            cursor: not-allowed;
        }
        
        .sidebar {
            background: linear-gradient(to bottom, #f8fafc, #f1f5f9);
            padding: 30px;
            overflow-y: auto;
            border-right: 1px solid var(--border);
        }
        
        .section {
            background: white;
            padding: 25px;
            border-radius: 15px;
            margin-bottom: 25px;
            box-shadow: 0 5px 15px rgba(0, 0, 0, 0.05);
            border: 1px solid var(--border);
        }
        
        .section h3 {
            color: var(--primary);
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 2px solid var(--border);
            display: flex;
            align-items: center;
            gap: 10px;
            font-size: 1.2rem;
        }
        
        .section h3 i {
            color: var(--secondary);
        }
        
        .stats-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 15px;
        }
        
        .stat-item {
            background: var(--light);
            padding: 15px;
            border-radius: 10px;
            text-align: center;
            border: 1px solid var(--border);
        }
        
        .stat-item .value {
            font-size: 1.8rem;
            font-weight: 700;
            color: var(--primary);
            margin: 10px 0;
        }
        
        .stat-item .label {
            font-size: 0.9rem;
            color: var(--gray);
        }
        
        .task-list, .error-list, .learning-list {
            max-height: 300px;
            overflow-y: auto;
        }
        
        .task-item, .error-item, .learning-item {
            padding: 15px;
            margin-bottom: 12px;
            background: var(--light);
            border-radius: 10px;
            border-right: 4px solid var(--primary);
            transition: all 0.3s;
        }
        
        .task-item:hover, .error-item:hover, .learning-item:hover {
            transform: translateX(-5px);
            box-shadow: 0 5px 15px rgba(0, 0, 0, 0.1);
        }
        
        .task-header, .error-header, .learning-header {
            display: flex;
            justify-content: space-between;
            margin-bottom: 8px;
            font-size: 0.85rem;
        }
        
        .task-id, .error-id, .learning-id {
            font-family: monospace;
            background: rgba(37, 99, 235, 0.1);
            padding: 3px 8px;
            border-radius: 5px;
            font-size: 0.8rem;
        }
        
        .task-status {
            padding: 3px 10px;
            border-radius: 20px;
            font-size: 0.8rem;
            font-weight: 600;
        }
        
        .status-completed {
            background: rgba(16, 185, 129, 0.15);
            color: var(--secondary);
        }
        
        .status-failed {
            background: rgba(239, 68, 68, 0.15);
            color: var(--danger);
        }
        
        .status-pending {
            background: rgba(245, 158, 11, 0.15);
            color: var(--warning);
        }
        
        .task-description, .error-message, .learning-pattern {
            font-size: 0.95rem;
            line-height: 1.5;
            margin-bottom: 8px;
        }
        
        .task-time, .error-time, .learning-time {
            font-size: 0.8rem;
            color: var(--gray);
            text-align: left;
        }
        
        .error-item {
            border-right-color: var(--danger);
        }
        
        .learning-item {
            border-right-color: var(--secondary);
        }
        
        .quick-actions {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 15px;
            margin-top: 20px;
        }
        
        .action-btn {
            padding: 12px;
            border: none;
            border-radius: 10px;
            background: var(--primary);
            color: white;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s;
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 8px;
        }
        
        .action-btn:hover {
            background: var(--primary-dark);
            transform: translateY(-2px);
        }
        
        .action-btn.secondary {
            background: var(--secondary);
        }
        
        .action-btn.secondary:hover {
            background: #0da271;
        }
        
        .action-btn.danger {
            background: var(--danger);
        }
        
        .action-btn.danger:hover {
            background: #dc2626;
        }
        
        .empty-state {
            text-align: center;
            padding: 40px 20px;
            color: var(--gray);
        }
        
        .empty-state i {
            font-size: 3rem;
            margin-bottom: 15px;
            opacity: 0.5;
        }
        
        .notification {
            position: fixed;
            bottom: 30px;
            right: 30px;
            padding: 15px 25px;
            background: white;
            border-radius: 10px;
            box-shadow: 0 10px 30px rgba(0, 0, 0, 0.2);
            display: flex;
            align-items: center;
            gap: 15px;
            z-index: 1000;
            animation: slideIn 0.3s ease;
            border-right: 4px solid var(--primary);
        }
        
        @keyframes slideIn {
            from { transform: translateX(100%); opacity: 0; }
            to { transform: translateX(0); opacity: 1; }
        }
        
        .notification.success {
            border-right-color: var(--secondary);
        }
        
        .notification.error {
            border-right-color: var(--danger);
        }
        
        .notification.warning {
            border-right-color: var(--warning);
        }
        
        .notification i {
            font-size: 1.5rem;
        }
        
        .notification.success i {
            color: var(--secondary);
        }
        
        .notification.error i {
            color: var(--danger);
        }
        
        .notification.warning i {
            color: var(--warning);
        }
        
        .loader {
            display: inline-block;
            width: 20px;
            height: 20px;
            border: 3px solid rgba(37, 99, 235, 0.3);
            border-radius: 50%;
            border-top-color: var(--primary);
            animation: spin 1s ease-in-out infinite;
        }
        
        @keyframes spin {
            to { transform: rotate(360deg); }
        }
        
        @media (max-width: 1200px) {
            .main-content {
                grid-template-columns: 1fr;
            }
            
            .sidebar {
                border-right: none;
                border-top: 1px solid var(--border);
            }
        }
        
        @media (max-width: 768px) {
            header {
                flex-direction: column;
                gap: 20px;
                text-align: center;
            }
            
            .status-indicators {
                flex-wrap: wrap;
                justify-content: center;
            }
            
            .stats-grid {
                grid-template-columns: 1fr;
            }
            
            .quick-actions {
                grid-template-columns: 1fr;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <div class="logo">
                <i class="fas fa-brain"></i>
                <div>
                    <h1>سیستم عامل هوشمند با Agent اجرایی</h1>
                    <p>یادگیری مستمر و اجرای خودکار وظایف</p>
                </div>
            </div>
            
            <div class="status-indicators">
                <div class="status-item">
                    <i class="fas fa-microchip"></i>
                    <span>Brain Agent</span>
                    <div class="value" id="brain-status">🟢</div>
                </div>
                <div class="status-item">
                    <i class="fas fa-cogs"></i>
                    <span>Executive Agent</span>
                    <div class="value" id="executive-status">🟢</div>
                </div>
                <div class="status-item">
                    <i class="fas fa-database"></i>
                    <span>Memory</span>
                    <div class="value" id="memory-usage">0 MB</div>
                </div>
            </div>
        </header>
        
        <div class="main-content">
            <div class="sidebar">
                <div class="section">
                    <h3><i class="fas fa-chart-bar"></i> آمار سیستم</h3>
                    <div class="stats-grid">
                        <div class="stat-item">
                            <div class="value" id="total-tasks">0</div>
                            <div class="label">کل وظایف</div>
                        </div>
                        <div class="stat-item">
                            <div class="value" id="successful-tasks">0</div>
                            <div class="label">موفق</div>
                        </div>
                        <div class="stat-item">
                            <div class="value" id="failed-tasks">0</div>
                            <div class="label">ناموفق</div>
                        </div>
                        <div class="stat-item">
                            <div class="value" id="learned-patterns">0</div>
                            <div class="label">الگوهای یادگیری</div>
                        </div>
                    </div>
                </div>
                
                <div class="section">
                    <h3><i class="fas fa-tasks"></i> وظایف اخیر</h3>
                    <div class="task-list" id="recent-tasks">
                        <div class="empty-state">
                            <i class="fas fa-tasks"></i>
                            <p>هنوز وظیفه‌ای اجرا نشده است</p>
                        </div>
                    </div>
                </div>
                
                <div class="section">
                    <h3><i class="fas fa-exclamation-triangle"></i> خطاهای اخیر</h3>
                    <div class="error-list" id="recent-errors">
                        <div class="empty-state">
                            <i class="fas fa-check-circle"></i>
                            <p>هیچ خطایی گزارش نشده است</p>
                        </div>
                    </div>
                </div>
                
                <div class="section">
                    <h3><i class="fas fa-lightbulb"></i> یادگیری‌های اخیر</h3>
                    <div class="learning-list" id="recent-learnings">
                        <div class="empty-state">
                            <i class="fas fa-graduation-cap"></i>
                            <p>هنوز یادگیری‌ای ثبت نشده است</p>
                        </div>
                    </div>
                </div>
                
                <div class="quick-actions">
                    <button class="action-btn" onclick="executeQuickTask('بررسی وضعیت سیستم')">
                        <i class="fas fa-heartbeat"></i>
                        بررسی سلامت
                    </button>
                    <button class="action-btn secondary" onclick="executeQuickTask('نمایش فایل‌های پروژه')">
                        <i class="fas fa-folder-open"></i>
                        لیست فایل‌ها
                    </button>
                    <button class="action-btn" onclick="executeQuickTask('بررسی فضای دیسک')">
                        <i class="fas fa-hdd"></i>
                        فضای دیسک
                    </button>
                    <button class="action-btn danger" onclick="clearChat()">
                        <i class="fas fa-trash"></i>
                        پاک‌سازی چت
                    </button>
                </div>
            </div>
            
            <div class="chat-section">
                <div class="chat-header">
                    <h2><i class="fas fa-comments"></i> چت با مغز هوشمند</h2>
                    <div style="display: flex; gap: 10px; align-items: center;">
                        <span id="connection-status" style="color: var(--secondary);">
                            <i class="fas fa-wifi"></i> متصل
                        </span>
                        <button class="action-btn" onclick="loadStats()" style="padding: 8px 15px; font-size: 0.9rem;">
                            <i class="fas fa-sync-alt"></i>
                            به‌روزرسانی
                        </button>
                    </div>
                </div>
                
                <div class="chat-messages" id="chat-messages">
                    <div class="message assistant-message">
                        <div class="message-header">
                            <span><i class="fas fa-robot"></i> سیستم عامل هوشمند</span>
                            <span>هم‌اکنون</span>
                        </div>
                        <div class="message-content">
                            سلام! من سیستم عامل هوشمند شما هستم. می‌توانم:
                            <br>• با شما چت کنم و سوالاتتان را پاسخ دهم
                            <br>• وظایف را اجرا کنم (مانند بررسی فایل‌ها، اجرای دستورات)
                            <br>• از خطاها یاد بگیرم و بهبود یابم
                            <br>• وضعیت سیستم را مانیتور کنم
                            <br><br>چه کاری می‌توانم برای شما انجام دهم؟
                        </div>
                    </div>
                </div>
                
                <div class="chat-input">
                    <textarea 
                        id="message-input" 
                        placeholder="پیام خود را بنویسید یا یک task برای اجرا وارد کنید... (مثال: 'لیست فایل‌های دایرکتوری فعلی' یا 'بررسی مصرف حافظه')"
                        onkeydown="if(event.key === 'Enter' && !event.shiftKey) { event.preventDefault(); sendMessage(); }"
                    ></textarea>
                    <button id="send-button" onclick="sendMessage()">
                        <i class="fas fa-paper-plane"></i>
                        ارسال
                    </button>
                </div>
            </div>
        </div>
    </div>
    
    <div id="notification-container"></div>
    
    <script>
        // متغیرهای سراسری
        let socket = null;
        let sessionId = 'session_' + Date.now();
        let isProcessing = false;
        
        // اتصال به WebSocket
        function connectWebSocket() {
            const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
            const wsUrl = `${protocol}//${window.location.host}`;
            
            socket = io(wsUrl);
            
            socket.on('connect', function() {
                showNotification('✅ به سیستم متصل شدید', 'success');
                updateConnectionStatus(true);
            });
            
            socket.on('disconnect', function() {
                showNotification('❌ اتصال قطع شد', 'error');
                updateConnectionStatus(false);
            });
            
            socket.on('status', function(data) {
                console.log('Status:', data);
            });
            
            socket.on('task_result', function(data) {
                console.log('Task result:', data);
                addMessage('سیستم', `✅ Task تکمیل شد: ${JSON.stringify(data.result, null, 2)}`, 'assistant');
                loadStats();
                loadRecentTasks();
            });
            
            socket.on('task_error', function(data) {
                console.log('Task error:', data);
                addMessage('سیستم', `❌ خطا در اجرای Task: ${data.error}`, 'assistant');
                loadRecentErrors();
            });
        }
        
        // ارسال پیام
        function sendMessage() {
            const input = document.getElementById('message-input');
            const message = input.value.trim();
            const button = document.getElementById('send-button');
            
            if (!message || isProcessing) return;
            
            // اضافه کردن پیام کاربر
            addMessage('شما', message, 'user');
            input.value = '';
            button.disabled = true;
            isProcessing = true;
            
            // نمایش loader
            const loader = document.createElement('div');
            loader.className = 'loader';
            loader.style.margin = '10px auto';
            document.getElementById('chat-messages').appendChild(loader);
            
            // ارسال به سرور
            fetch('/api/chat', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    message: message,
                    session_id: sessionId
                })
            })
            .then(response => response.json())
            .then(data => {
                // حذف loader
                const loader = document.querySelector('#chat-messages .loader');
                if (loader) loader.remove();
                
                if (data.error) {
                    addMessage('سیستم', `❌ خطا: ${data.error}`, 'assistant');
                } else {
                    addMessage('سیستم', data.response, 'assistant')
             // اگر پیام
            // اگر task_id برگردانده شده، یعنی یک task ایجاد شده
                    if (data.task_id) {
                        showNotification(`📋 Task جدید ایجاد شد: ${data.task_id}`, 'success');
                        loadRecentTasks();
                    }
                }
                
                button.disabled = false;
                isProcessing = false;
            })
            .catch(error => {
                console.error('Error:', error);
                addMessage('سیستم', '❌ خطا در ارتباط با سرور', 'assistant');
                button.disabled = false;
                isProcessing = false;
            });
        }
        
        // اجرای task سریع
        function executeQuickTask(taskDescription) {
            const input = document.getElementById('message-input');
            input.value = taskDescription;
            sendMessage();
        }
        
        // اضافه کردن پیام به چت
        function addMessage(sender, content, type) {
            const messagesDiv = document.getElementById('chat-messages');
            const messageDiv = document.createElement('div');
            
            messageDiv.className = `message ${type === 'user' ? 'user-message' : 'assistant-message'}`;
            messageDiv.innerHTML = `
                <div class="message-header">
                    <span><i class="fas fa-${type === 'user' ? 'user' : 'robot'}"></i> ${sender}</span>
                    <span>${new Date().toLocaleTimeString('fa-IR')}</span>
                </div>
                <div class="message-content">${content.replace(/\n/g, '<br>')}</div>
            `;
            
            messagesDiv.appendChild(messageDiv);
            messagesDiv.scrollTop = messagesDiv.scrollHeight;
        }
        
        // بارگذاری آمار
        function loadStats() {
            fetch('/api/stats')
                .then(response => response.json())
                .then(data => {
                    document.getElementById('total-tasks').textContent = data.total_tasks || 0;
                    document.getElementById('successful-tasks').textContent = data.successful_tasks || 0;
                    document.getElementById('failed-tasks').textContent = data.failed_tasks || 0;
                    document.getElementById('learned-patterns').textContent = data.learned_patterns || 0;
                    document.getElementById('memory-usage').textContent = `${data.memory_usage_mb || 0} MB`;
                })
                .catch(error => {
                    console.error('Error loading stats:', error);
                });
        }
        
        // بارگذاری tasks اخیر
        function loadRecentTasks() {
            fetch('/api/tasks')
                .then(response => response.json())
                .then(data => {
                    const tasksDiv = document.getElementById('recent-tasks');
                    
                    if (!data.tasks || data.tasks.length === 0) {
                        tasksDiv.innerHTML = `
                            <div class="empty-state">
                                <i class="fas fa-tasks"></i>
                                <p>هنوز وظیفه‌ای اجرا نشده است</p>
                            </div>
                        `;
                        return;
                    }
                    
                    tasksDiv.innerHTML = '';
                    data.tasks.slice(0, 5).forEach(task => {
                        const taskDiv = document.createElement('div');
                        taskDiv.className = 'task-item';
                        
                        let statusClass = 'status-pending';
                        if (task.status === 'completed') statusClass = 'status-completed';
                        if (task.status === 'failed' || task.status === 'error') statusClass = 'status-failed';
                        
                        taskDiv.innerHTML = `
                            <div class="task-header">
                                <span class="task-id">${task.task_id.substring(0, 8)}...</span>
                                <span class="task-status ${statusClass}">${task.status}</span>
                            </div>
                            <div class="task-description">${task.description || 'بدون توضیح'}</div>
                            <div class="task-time">${new Date(task.created_at).toLocaleString('fa-IR')}</div>
                        `;
                        
                        tasksDiv.appendChild(taskDiv);
                    });
                })
                .catch(error => {
                    console.error('Error loading tasks:', error);
                });
        }
        
        // بارگذاری خطاهای اخیر
        function loadRecentErrors() {
            fetch('/api/errors')
                .then(response => response.json())
                .then(data => {
                    const errorsDiv = document.getElementById('recent-errors');
                    
                    if (!data.errors || data.errors.length === 0) {
                        errorsDiv.innerHTML = `
                            <div class="empty-state">
                                <i class="fas fa-check-circle"></i>
                                <p>هیچ خطایی گزارش نشده است</p>
                            </div>
                        `;
                        return;
                    }
                    
                    errorsDiv.innerHTML = '';
                    data.errors.slice(0, 5).forEach(error => {
                        const errorDiv = document.createElement('div');
                        errorDiv.className = 'error-item';
                        
                        let errorMessage = 'خطای ناشناخته';
                        if (error.error_data && typeof error.error_data === 'object') {
                            errorMessage = error.error_data.message || JSON.stringify(error.error_data);
                        } else if (typeof error.error_data === 'string') {
                            errorMessage = error.error_data;
                        }
                        
                        errorDiv.innerHTML = `
                            <div class="error-header">
                                <span class="error-id">${error.id}</span>
                                <span style="color: var(--danger);">
                                    <i class="fas fa-exclamation-circle"></i>
                                    ${error.resolved ? 'رفع شده' : 'رفع نشده'}
                                </span>
                            </div>
                            <div class="error-message">${errorMessage.substring(0, 100)}${errorMessage.length > 100 ? '...' : ''}</div>
                            <div class="error-time">${new Date(error.created_at).toLocaleString('fa-IR')}</div>
                        `;
                        
                        errorsDiv.appendChild(errorDiv);
                    });
                })
                .catch(error => {
                    console.error('Error loading errors:', error);
                });
        }
        
        // بارگذاری یادگیری‌های اخیر
        function loadRecentLearnings() {
            fetch('/api/learnings')
                .then(response => response.json())
                .then(data => {
                    const learningsDiv = document.getElementById('recent-learnings');
                    
                    if (!data.learnings || data.learnings.length === 0) {
                        learningsDiv.innerHTML = `
                            <div class="empty-state">
                                <i class="fas fa-graduation-cap"></i>
                                <p>هنوز یادگیری‌ای ثبت نشده است</p>
                            </div>
                        `;
                        return;
                    }
                    
                    learningsDiv.innerHTML = '';
                    data.learnings.slice(0, 5).forEach(learning => {
                        const learningDiv = document.createElement('div');
                        learningDiv.className = 'learning-item';
                        
                        let pattern = 'الگوی ناشناخته';
                        if (learning.pattern_data && typeof learning.pattern_data === 'object') {
                            pattern = learning.pattern_data.input_pattern || 'بدون الگو';
                        }
                        
                        learningDiv.innerHTML = `
                            <div class="learning-header">
                                <span class="learning-id">${learning.id}</span>
                                <span style="color: var(--secondary);">
                                    <i class="fas fa-star"></i>
                                    ${learning.success_count} بار موفق
                                </span>
                            </div>
                            <div class="learning-pattern">${pattern.substring(0, 80)}${pattern.length > 80 ? '...' : ''}</div>
                            <div class="learning-time">آخرین استفاده: ${new Date(learning.last_used).toLocaleString('fa-IR')}</div>
                        `;
                        
                        learningsDiv.appendChild(learningDiv);
                    });
                })
                .catch(error => {
                    console.error('Error loading learnings:', error);
                });
        }
        
        // پاک‌سازی چت
        function clearChat() {
            if (confirm('آیا از پاک‌سازی تاریخچه چت مطمئن هستید؟')) {
                document.getElementById('chat-messages').innerHTML = `
                    <div class="message assistant-message">
                        <div class="message-header">
                            <span><i class="fas fa-robot"></i> سیستم عامل هوشمند</span>
                            <span>هم‌اکنون</span>
                        </div>
                        <div class="message-content">
                            تاریخچه چت پاک شد. چطور می‌توانم کمک کنم؟
                        </div>
                    </div>
                `;
                showNotification('✅ تاریخچه چت پاک شد', 'success');
            }
        }
        
        // نمایش نوتیفیکیشن
        function showNotification(message, type = 'info') {
            const container = document.getElementById('notification-container');
            const notification = document.createElement('div');
            notification.className = `notification ${type}`;
            
            let icon = 'fas fa-info-circle';
            if (type === 'success') icon = 'fas fa-check-circle';
            if (type === 'error') icon = 'fas fa-exclamation-circle';
            if (type === 'warning') icon = 'fas fa-exclamation-triangle';
            
            notification.innerHTML = `
                <i class="${icon}"></i>
                <span>${message}</span>
            `;
            
            container.appendChild(notification);
            
            // حذف خودکار بعد از 5 ثانیه
            setTimeout(() => {
                notification.style.animation = 'slideIn 0.3s ease reverse';
                setTimeout(() => {
                    if (notification.parentNode) {
                        notification.parentNode.removeChild(notification);
                    }
                }, 300);
            }, 5000);
        }
        
        // به‌روزرسانی وضعیت اتصال
        function updateConnectionStatus(connected) {
            const statusElement = document.getElementById('connection-status');
            if (connected) {
                statusElement.innerHTML = '<i class="fas fa-wifi"></i> متصل';
                statusElement.style.color = 'var(--secondary)';
                document.getElementById('brain-status').textContent = '🟢';
                document.getElementById('executive-status').textContent = '🟢';
            } else {
                statusElement.innerHTML = '<i class="fas fa-wifi-slash"></i> قطع';
                statusElement.style.color = 'var(--danger)';
                document.getElementById('brain-status').textContent = '🔴';
                document.getElementById('executive-status').textContent = '🔴';
            }
        }
        
        // بارگذاری اولیه
        document.addEventListener('DOMContentLoaded', function() {
            connectWebSocket();
            loadStats();
            loadRecentTasks();
            loadRecentErrors();
            loadRecentLearnings();
            
            // به‌روزرسانی خودکار هر 30 ثانیه
            setInterval(() => {
                loadStats();
                loadRecentTasks();
                loadRecentErrors();
                loadRecentLearnings();
            }, 30000);
            
            // فوکوس روی input
            document.getElementById('message-input').focus();
        });
    </script>
</body>
</html>
EOF

    # 7. فایل requirements.txt
    cat > requirements.txt << 'EOF'
flask==2.3.3
flask-socketio==5.3.4
python-socketio==5.9.0
eventlet==0.33.3
llama-cpp-python==0.2.26
sqlite3
psutil==5.9.5
pyyaml==6.0
requests==2.31.0
EOF

    # 8. فایل config.yaml
    cat > config.yaml << 'EOF'
# تنظیمات سیستم عامل هوشمند

# تنظیمات مدل
model:
  name: "Qwen2.5-4B-Instruct-Q4_K_M"
  path: "./models/Qwen2.5-4B-Instruct-Q4_K_M.gguf"
  n_ctx: 2048  # context length
  n_gpu_layers: 20  # تعداد لایه‌های GPU (0 برای CPU فقط)
  n_threads: 4  # تعداد threadهای CPU

# تنظیمات Agentها
agents:
  brain:
    temperature: 0.7
    max_tokens: 1024
    top_p: 0.9
    top_k: 40
    
  executive:
    allowed_commands:  # لیست دستورات مجاز
      - "ls"
      - "pwd"
      - "df"
      - "du"
      - "ps"
      - "top"
      - "free"
      - "cat"
      - "grep"
      - "find"
      - "mkdir"
      - "rmdir"
      - "touch"
      - "cp"
      - "mv"
      - "chmod"
      - "chown"
      - "python"
      - "pip"
      - "git"
    
    forbidden_paths:  # مسیرهای ممنوعه
      - "/"
      - "/etc"
      - "/var"
      - "/usr"
      - "/bin"
      - "/sbin"
      - "/root"
      - "/home/*/.ssh"
      - "/home/*/.bash_history"
      - "/home/*/.config"
    
    require_permission_for:  # دستوراتی که نیاز به مجوز دارند
      - "rm"
      - "chmod"
      - "chown"
      - "sudo"
      - "apt"
      - "yum"
      - "dnf"
      - "pacman"

# تنظیمات حافظه
memory:
  database_path: "./data/smart_agent.db"
  cleanup_days: 30  # پاک‌سازی مکالمات قدیمی‌تر از این تعداد روز
  max_conversations: 1000  # حداکثر تعداد مکالمات ذخیره شده
  max_tasks: 500  # حداکثر تعداد tasks ذخیره شده

# تنظیمات سرور
server:
  host: "0.0.0.0"
  port: 5000
  debug: false
  secret_key: "smart_agent_secret_key_2024"

# تنظیمات یادگیری
learning:
  enable_learning: true
  min_pattern_length: 10  # حداقل طول الگو برای یادگیری
  max_patterns: 1000  # حداکثر تعداد الگوهای ذخیره شده
  similarity_threshold: 0.8  # آستانه تشابه برای بازیابی الگوها

# تنظیمات لاگ‌گیری
logging:
  level: "INFO"
  file: "./logs/smart_agent.log"
  max_file_size: 10  # MB
  backup_count: 5

# تنظیمات امنیتی
security:
  enable_permission_check: true
  max_command_length: 1000
  timeout_seconds: 30
  max_concurrent_tasks: 5
EOF

    # 9. فایل setup.py
    cat > setup.py << 'EOF'
#!/usr/bin/env python3
"""
فایل راه‌اندازی سیستم عامل هوشمند
"""

import os
import sys
import subprocess
import shutil
from pathlib import Path

def print_header():
    """نمایش هدر برنامه"""
    print("=" * 70)
    print("سیستم عامل هوشمند با Agent اجرایی و یادگیری مستمر")
    print("نسخه: 1.0.0")
    print("=" * 70)
    print()

def check_python_version():
    """بررسی نسخه پایتون"""
    print("🔍 بررسی نسخه پایتون...")
    if sys.version_info < (3, 8):
        print("❌ پایتون 3.8 یا بالاتر نیاز است")
        sys.exit(1)
    print(f"✅ پایتون {sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro} نصب است")
    print()

def create_directories():
    """ایجاد دایرکتوری‌های مورد نیاز"""
    print("📁 ایجاد دایرکتوری‌های مورد نیاز...")
    
    directories = [
        "agents",
        "memory",
        "models",
        "data",
        "logs",
        "templates"
    ]
    
    for directory in directories:
        Path(directory).mkdir(parents=True, exist_ok=True)
        print(f"   ✅ دایرکتوری {directory}/ ایجاد شد")
    
    print()

def setup_virtualenv():
    """راه‌اندازی محیط مجازی"""
    print("🐍 راه‌اندازی محیط مجازی پایتون...")
    
    if not Path("venv").exists():
        print("   ایجاد محیط مجازی...")
        result = subprocess.run([sys.executable, "-m", "venv", "venv"], 
                              capture_output=True, text=True)
        if result.returncode != 0:
            print(f"❌ خطا در ایجاد محیط مجازی: {result.stderr}")
            sys.exit(1)
        print("   ✅ محیط مجازی ایجاد شد")
    else:
        print("   ✅ محیط مجازی از قبل وجود دارد")
    
    print()

def install_dependencies():
    """نصب dependencies"""
    print("📦 نصب dependencies...")
    
    # فعال‌سازی محیط مجازی
    if os.name == 'nt':  # ویندوز
        pip_path = Path("venv/Scripts/pip")
    else:  # لینوکس/مک
        pip_path = Path("venv/bin/pip")
    
    if not pip_path.exists():
        print("❌ pip در محیط مجازی یافت نشد")
        sys.exit(1)
    
    # نصب requirements
    print("   در حال نصب packages...")
    result = subprocess.run([str(pip_path), "install", "-r", "requirements.txt"],
                          capture_output=True, text=True)
    
    if result.returncode != 0:
        print(f"❌ خطا در نصب dependencies: {result.stderr}")
        sys.exit(1)
    
    print("   ✅ تمام packages با موفقیت نصب شدند")
    print()

def download_model():
    """دانلود مدل LLM"""
    print("🤖 دانلود مدل Qwen2.5-4B-Instruct-Q4_K_M...")
    
    model_path = Path("models/Qwen2.5-4B-Instruct-Q4_K_M.gguf")
    
    if model_path.exists():
        print("   ✅ مدل از قبل دانلود شده است")
        print(f"   📊 حجم مدل: {model_path.stat().st_size / (1024**3):.2f} GB")
        print()
        return
    
    print("   ⚠️  توجه: دانلود مدل ممکن است چند دقیقه طول بکشد")
    print("   در حال دانلود از HuggingFace...")
    
    import requests
    from tqdm import tqdm
    
    # URL مدل GGUF
    model_url = "https://huggingface.co/Qwen/Qwen2.5-4B-Instruct-GGUF/resolve/main/Qwen2.5-4B-Instruct-Q4_K_M.gguf"
    
    try:
        response = requests.get(model_url, stream=True)
        response.raise_for_status()
        
        total_size = int(response.headers.get('content-length', 0))
        
        with open(model_path, 'wb') as f, tqdm(
            desc="   دانلود",
            total=total_size,
            unit='iB',
            unit_scale=True,
            unit_divisor=1024,
        ) as pbar:
            for data in response.iter_content(chunk_size=8192):
                size = f.write(data)
                pbar.update(size)
        
        print(f"   ✅ مدل با موفقیت دانلود شد: {model_path}")
        
    except Exception as e:
        print(f"❌ خطا در دانلود مدل: {e}")
        print("   لطفاً مدل را به صورت دستی دانلود کنید:")
        print(f"   {model_url}")
        print(f"   و در مسیر {model_path} قرار دهید")
        sys.exit(1)
    
    print()

def check_system_resources():
    """بررسی منابع سیستم"""
    print("💻 بررسی منابع سیستم...")
    
    import psutil
    
    # بررسی RAM
    ram = psutil.virtual_memory()
    ram_gb = ram.total / (1024**3)
    print(f"   RAM کل: {ram_gb:.1f} GB")
    
    if ram_gb < 8:
        print("   ⚠️  هشدار: سیستم شما کمتر از 8GB RAM دارد")
        print("   ممکن است عملکرد مدل محدود باشد")
    else:
        print("   ✅ RAM کافی است")
    
    # بررسی فضای دیسک
    disk = psutil.disk_usage('/')
    disk_gb = disk.free / (1024**3)
    print(f"   فضای دیسک آزاد: {disk_gb:.1f} GB")
    
    if disk_gb < 5:
        print("   ⚠️  هشدار: فضای دیسک کم است")
    else:
        print("   ✅ فضای دیسک کافی است")
    
    # بررسی CPU
    cpu_count = psutil.cpu_count()
    print(f"   تعداد هسته‌های CPU: {cpu_count}")
    
    print()

def create_database():
    """ایجاد پایگاه داده"""
    print("🗄️ ایجاد پایگاه داده...")
    
    from memory.memory_manager import MemoryManager
    
    try:
        memory_manager = MemoryManager()
        memory_manager.initialize_database()
        memory_manager.close()
        print("   ✅ پایگاه داده ایجاد شد")
    except Exception as e:
        print(f"❌ خطا در ایجاد پایگاه داده: {e}")
        sys.exit(1)
    
    print()

def setup_complete():
    """پیام تکمیل نصب"""
    print("=" * 70)
    print("🎉 نصب و راه‌اندازی با موفقیت تکمیل شد!")
    print("=" * 70)
    print()
    print("📋 مراحل بعدی:")
    print("1. فعال‌سازی محیط مجازی:")
    print("   - ویندوز: venv\\Scripts\\activate")
    print("   - لینوکس/مک: source venv/bin/activate")
    print()
    print("2. راه‌اندازی سرور:")
    print("   python main.py")
    print()
    print("3. دسترسی به داشبورد:")
    print("   مرورگر خود را باز کنید و به آدرس زیر بروید:")
    print("   http://localhost:5000")
    print()
    print("4. شروع کار:")
    print("   - با سیستم از طریق چت تعامل کنید")
    print("   - وظایف را به سیستم محول کنید")
    print("   - عملکرد سیستم را از طریق داشبورد مانیتور کنید")
    print()
    print("⚠️  نکات امنیتی:")
    print("   - این سیستم را در شبکه‌های عمومی اجرا نکنید")
    print("   - تنظیمات امنیتی را در config.yaml بررسی کنید")
    print("   - دسترسی‌های Executive Agent را محدود نگه دارید")
    print()

def main():
    """تابع اصلی"""
    print_header()
    check_python_version()
    create_directories()
    setup_virtualenv()
    install_dependencies()
    download_model()
    check_system_resources()
    create_database()
    setup_complete()

if __name__ == "__main__":
    main()
EOF

    # 10. فایل README.md
    cat > README.md << 'EOF'
# سیستم عامل هوشمند با Agent اجرایی و یادگیری مستمر

یک سیستم عامل هوشمند محلی با قابلیت اجرای وظایف، یادگیری از خطاها و تعامل از طریق داشبورد وب.

## 🚀 ویژگی‌ها

### 🤖 Agentهای هوشمند
- **Brain Agent**: پردازش زبان طبیعی، برنامه‌ریزی وظایف، تحلیل خطاها
- **Executive Agent**: اجرای امن دستورات سیستم، مدیریت مجوزها
- **Memory System**: ذخیره‌سازی پایدار مکالمات، وظایف، خطاها و یادگیری‌ها

### 🎯 قابلیت‌های کلیدی
- **چت هوشمند**: تعامل طبیعی با سیستم
- **اجرای وظایف**: اجرای دستورات سیستم به صورت امن
- **یادگیری مستمر**: یادگیری از تعاملات و خطاها
- **داشبورد پیشرفته**: رابط کاربری زیبا و واکنش‌گرا
- **مدیریت حافظه**: ذخیره‌سازی و بازیابی هوشمند اطلاعات
- **امنیت**: بررسی دستورات، لیست سفید، درخواست مجوز

## 📋 نیازمندی‌های سیستم

- **سیستم عامل**: لینوکس، ویندوز، مک‌اواس
- **پایتون**: نسخه 3.8 یا بالاتر
- **RAM**: حداقل 8GB (توصیه: 16GB)
- **فضای دیسک**: حداقل 5GB فضای آزاد
- **اینترنت**: برای دانلود اولیه مدل

## 🛠️ نصب و راه‌اندازی

### روش ۱: اجرای اسکریپت خودکار (توصیه شده)
```bash
# دانلود اسکریپت
wget https://raw.githubusercontent.com/your-repo/smart-agent-system/main/smart_agent_system.sh

# اجرای اسکریپت
chmod +x smart_agent_system.sh
./smart_agent_system.sh

### روش ۲: نصب دستی

bash
# 1. کلون ریپازیتوری
git clone https://github.com/your-repo/smart-agent-system.git
cd smart-agent-system

# 2. ایجاد محیط مجازی
python -m venv venv

# 3. فعال‌سازی محیط مجازی
# لینوکس/مک:
source venv/bin/activate
# ویندوز:
venv\Scripts\activate

# 4. نصب dependencies
pip install -r requirements.txt

# 5. دانلود مدل (به صورت خودکار)
python setup.py

# 6. راه‌اندازی سیستم
python main.py

## 🎮 استفاده از سیستم

### راه‌اندازی سرور

bash
# فعال‌سازی محیط مجازی
source venv/bin/activate  # لینوکس/مک
# یا
venv\Scripts\activate     # ویندوز

# اجرای سرور
python main.py

### دسترسی به داشبورد

1. مرورگر خود را باز کنید
2. به آدرس زیر بروید:
   
