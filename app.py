#!/usr/bin/env python3
"""
PyRunner - Raspberry Pi Python Script Manager
A web interface for uploading, validating, and executing Python scripts.
"""

# Eventlet monkey-patching must happen first, before any other imports
try:
    import eventlet
    eventlet.monkey_patch()
    ASYNC_MODE = 'eventlet'
except ImportError:
    ASYNC_MODE = 'threading'
    print("Warning: eventlet not available, falling back to threading mode")

import os
import sys
import json
import socket
import signal
import pty
import select
import subprocess
import threading
import time
import fcntl
import termios
import struct
from datetime import datetime
from pathlib import Path
from typing import Optional

from flask import Flask, render_template, request, jsonify, send_from_directory
from flask_socketio import SocketIO, emit

from validator import PythonValidator
from config import Config

app = Flask(__name__, static_folder='static', template_folder='templates')
app.config['SECRET_KEY'] = os.urandom(24)
app.config['MAX_CONTENT_LENGTH'] = 16 * 1024 * 1024  # 16MB max upload

socketio = SocketIO(app, cors_allowed_origins="*", async_mode=ASYNC_MODE)

# Store running processes: {script_name: ProcessInfo}
running_processes = {}
process_lock = threading.Lock()

class ProcessInfo:
    """Information about a running Python process."""
    def __init__(self, script_name: str, pid: int, master_fd: int, start_time: float):
        self.script_name = script_name
        self.pid = pid
        self.master_fd = master_fd
        self.start_time = start_time
        self.output_log = []
        self.clients = set()  # Socket IDs watching this process
        self.thread: Optional[threading.Thread] = None

def get_hostname() -> str:
    """Get the hostname of this device."""
    return socket.gethostname()

def get_script_path(script_name: str) -> Path:
    """Get full path for a script in the code directory."""
    return Config.CODE_DIR / script_name

def get_log_path(script_name: str) -> Path:
    """Get path for a script's log file."""
    return Config.LOG_DIR / f"{script_name}.log"

def save_log(script_name: str, log_content: list):
    """Save execution log to file."""
    log_path = get_log_path(script_name)
    with open(log_path, 'w') as f:
        f.write(f"=== Execution Log for {script_name} ===\n")
        f.write(f"Timestamp: {datetime.now().isoformat()}\n")
        f.write("=" * 50 + "\n\n")
        for entry in log_content:
            f.write(entry)

def load_log(script_name: str) -> Optional[str]:
    """Load execution log from file."""
    log_path = get_log_path(script_name)
    if log_path.exists():
        with open(log_path, 'r') as f:
            return f.read()
    return None

def get_autoboot_script() -> Optional[str]:
    """Get the script configured for autoboot."""
    if Config.AUTOBOOT_FILE.exists():
        content = Config.AUTOBOOT_FILE.read_text().strip()
        if content and (Config.CODE_DIR / content).exists():
            return content
    return None

def set_autoboot_script(script_name: Optional[str]):
    """Set or clear the autoboot script."""
    if script_name:
        Config.AUTOBOOT_FILE.write_text(script_name)
    elif Config.AUTOBOOT_FILE.exists():
        Config.AUTOBOOT_FILE.unlink()

def list_scripts() -> list:
    """List all Python scripts with their status."""
    scripts = []
    autoboot = get_autoboot_script()
    
    for path in sorted(Config.CODE_DIR.glob('*.py')):
        script_name = path.name
        validator = PythonValidator(Config.CODE_DIR)
        
        with open(path, 'r') as f:
            code = f.read()
        
        is_valid, errors = validator.validate(code, script_name)
        missing_deps = validator.get_missing_local_imports(code)
        
        with process_lock:
            is_running = script_name in running_processes
        
        has_log = get_log_path(script_name).exists()
        
        scripts.append({
            'name': script_name,
            'is_valid': is_valid,
            'is_executable': is_valid and len(missing_deps) == 0,
            'is_running': is_running,
            'has_log': has_log,
            'is_autoboot': script_name == autoboot,
            'errors': errors,
            'missing_deps': missing_deps,
            'size': path.stat().st_size,
            'modified': datetime.fromtimestamp(path.stat().st_mtime).isoformat()
        })
    
    return scripts

def find_external_processes() -> list:
    """Find Python processes running scripts from CODE_DIR that weren't started by us."""
    external = []
    try:
        result = subprocess.run(
            ['pgrep', '-a', 'python'],
            capture_output=True,
            text=True
        )
        for line in result.stdout.strip().split('\n'):
            if not line:
                continue
            parts = line.split(None, 1)
            if len(parts) < 2:
                continue
            pid, cmdline = parts
            # Check if running a script from our directory
            for script_path in Config.CODE_DIR.glob('*.py'):
                if str(script_path) in cmdline:
                    script_name = script_path.name
                    with process_lock:
                        if script_name not in running_processes:
                            external.append({
                                'name': script_name,
                                'pid': int(pid),
                                'cmdline': cmdline
                            })
    except Exception:
        pass
    return external

# ============== Routes ==============

@app.route('/')
def index():
    """Serve the main page."""
    return render_template('index.html', hostname=get_hostname())

@app.route('/api/hostname')
def api_hostname():
    """Get hostname."""
    return jsonify({'hostname': get_hostname()})

@app.route('/api/scripts')
def api_list_scripts():
    """List all scripts with status."""
    scripts = list_scripts()
    external = find_external_processes()
    return jsonify({
        'scripts': scripts,
        'external_processes': external
    })

@app.route('/api/scripts/<script_name>')
def api_get_script(script_name: str):
    """Get script content and info."""
    path = get_script_path(script_name)
    if not path.exists():
        return jsonify({'error': 'Script not found'}), 404
    
    with open(path, 'r') as f:
        code = f.read()
    
    validator = PythonValidator(Config.CODE_DIR)
    is_valid, errors = validator.validate(code, script_name)
    missing_deps = validator.get_missing_local_imports(code)
    
    return jsonify({
        'name': script_name,
        'content': code,
        'is_valid': is_valid,
        'is_executable': is_valid and len(missing_deps) == 0,
        'errors': errors,
        'missing_deps': missing_deps
    })

@app.route('/api/scripts/<script_name>/log')
def api_get_log(script_name: str):
    """Get script execution log."""
    log = load_log(script_name)
    if log is None:
        return jsonify({'error': 'No log found'}), 404
    return jsonify({'log': log})

@app.route('/api/upload', methods=['POST'])
def api_upload():
    """Upload and validate a Python script."""
    if 'file' not in request.files:
        return jsonify({'error': 'No file provided'}), 400
    
    file = request.files['file']
    if not file.filename:
        return jsonify({'error': 'No filename'}), 400
    
    if not file.filename.endswith('.py'):
        return jsonify({'error': 'Only .py files are accepted'}), 400
    
    # Read and decode content
    try:
        content = file.read().decode('utf-8')
    except UnicodeDecodeError:
        return jsonify({'error': 'File is not valid UTF-8 text'}), 400
    
    # Validate
    validator = PythonValidator(Config.CODE_DIR)
    is_valid, errors = validator.validate(content, file.filename)
    missing_deps = validator.get_missing_local_imports(content)
    
    result = {
        'filename': file.filename,
        'is_valid': is_valid,
        'is_executable': is_valid and len(missing_deps) == 0,
        'errors': errors,
        'missing_deps': missing_deps
    }
    
    if is_valid:
        # Save the file
        save_path = get_script_path(file.filename)
        with open(save_path, 'w') as f:
            f.write(content)
        result['saved'] = True
        result['message'] = f"File saved to {save_path}"
    else:
        result['saved'] = False
    
    return jsonify(result)

@app.route('/api/scripts/<script_name>', methods=['DELETE'])
def api_delete_script(script_name: str):
    """Delete a script."""
    path = get_script_path(script_name)
    if not path.exists():
        return jsonify({'error': 'Script not found'}), 404
    
    # Check if running
    with process_lock:
        if script_name in running_processes:
            return jsonify({'error': 'Cannot delete running script'}), 400
    
    path.unlink()
    
    # Also delete log if exists
    log_path = get_log_path(script_name)
    if log_path.exists():
        log_path.unlink()
    
    # Clear autoboot if this was the autoboot script
    if get_autoboot_script() == script_name:
        set_autoboot_script(None)
    
    return jsonify({'success': True})

@app.route('/api/scripts/<script_name>/autoboot', methods=['POST'])
def api_set_autoboot(script_name: str):
    """Set a script as the autoboot script."""
    path = get_script_path(script_name)
    if not path.exists():
        return jsonify({'error': 'Script not found'}), 404
    
    data = request.get_json() or {}
    enabled = data.get('enabled', True)
    
    if enabled:
        set_autoboot_script(script_name)
    else:
        if get_autoboot_script() == script_name:
            set_autoboot_script(None)
    
    return jsonify({'success': True, 'autoboot': get_autoboot_script()})

@app.route('/api/config/blocked')
def api_get_blocked():
    """Get the list of blocked modules/functions."""
    return jsonify({
        'blocked_modules': Config.BLOCKED_MODULES,
        'blocked_builtins': Config.BLOCKED_BUILTINS,
        'blocked_functions': Config.BLOCKED_FUNCTIONS
    })

# ============== WebSocket Events ==============

def read_output(process_info: ProcessInfo):
    """Thread function to read process output and broadcast to clients."""
    master_fd = process_info.master_fd
    script_name = process_info.script_name
    
    try:
        while True:
            try:
                ready, _, _ = select.select([master_fd], [], [], 0.1)
                if ready:
                    try:
                        data = os.read(master_fd, 4096)
                        if data:
                            text = data.decode('utf-8', errors='replace')
                            process_info.output_log.append(text)
                            socketio.emit('output', {
                                'script': script_name,
                                'data': text
                            })
                        else:
                            break
                    except OSError:
                        break
            except (ValueError, OSError):
                break
            
            # Check if process still running
            try:
                pid, status = os.waitpid(process_info.pid, os.WNOHANG)
                if pid != 0:
                    break
            except ChildProcessError:
                break
    finally:
        # Process ended
        try:
            os.close(master_fd)
        except OSError:
            pass
        
        # Save log
        save_log(script_name, process_info.output_log)
        
        # Clean up
        with process_lock:
            if script_name in running_processes:
                del running_processes[script_name]
        
        # Notify clients
        socketio.emit('process_ended', {
            'script': script_name,
            'runtime': time.time() - process_info.start_time
        })

@socketio.on('connect')
def handle_connect():
    """Handle client connection."""
    emit('connected', {'hostname': get_hostname()})

@socketio.on('start')
def handle_start(data):
    """Start executing a script."""
    script_name = data.get('script')
    if not script_name:
        emit('error', {'message': 'No script specified'})
        return
    
    path = get_script_path(script_name)
    if not path.exists():
        emit('error', {'message': 'Script not found'})
        return
    
    # Check if already running
    with process_lock:
        if script_name in running_processes:
            emit('error', {'message': 'Script is already running'})
            return
    
    # Validate before running
    with open(path, 'r') as f:
        code = f.read()
    
    validator = PythonValidator(Config.CODE_DIR)
    is_valid, errors = validator.validate(code, script_name)
    missing_deps = validator.get_missing_local_imports(code)
    
    if not is_valid:
        emit('error', {'message': 'Script has validation errors', 'errors': errors})
        return
    
    if missing_deps:
        emit('error', {'message': 'Script has missing dependencies', 'missing': missing_deps})
        return
    
    # Create pseudo-terminal and fork
    try:
        master_fd, slave_fd = pty.openpty()
        
        # Set terminal size
        winsize = struct.pack('HHHH', 24, 80, 0, 0)
        fcntl.ioctl(slave_fd, termios.TIOCSWINSZ, winsize)
        
        pid = os.fork()
        
        if pid == 0:
            # Child process
            os.close(master_fd)
            os.setsid()
            os.dup2(slave_fd, 0)
            os.dup2(slave_fd, 1)
            os.dup2(slave_fd, 2)
            os.close(slave_fd)
            
            # Change to code directory
            os.chdir(str(Config.CODE_DIR))
            
            # Set environment
            env = os.environ.copy()
            env['PYTHONUNBUFFERED'] = '1'
            env['TERM'] = 'xterm'
            
            # Execute
            os.execvpe(
                sys.executable,
                [sys.executable, '-u', str(path)],
                env
            )
        else:
            # Parent process
            os.close(slave_fd)
            
            # Set non-blocking
            flags = fcntl.fcntl(master_fd, fcntl.F_GETFL)
            fcntl.fcntl(master_fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)
            
            process_info = ProcessInfo(script_name, pid, master_fd, time.time())
            process_info.clients.add(request.sid)
            
            # Start output reader thread
            thread = threading.Thread(target=read_output, args=(process_info,))
            thread.daemon = True
            thread.start()
            process_info.thread = thread
            
            with process_lock:
                running_processes[script_name] = process_info
            
            emit('started', {
                'script': script_name,
                'pid': pid,
                'start_time': process_info.start_time
            })
            
    except Exception as e:
        emit('error', {'message': f'Failed to start: {str(e)}'})

@socketio.on('input')
def handle_input(data):
    """Send input to a running script."""
    script_name = data.get('script')
    input_data = data.get('data', '')
    
    with process_lock:
        if script_name not in running_processes:
            emit('error', {'message': 'Script is not running'})
            return
        
        process_info = running_processes[script_name]
        try:
            os.write(process_info.master_fd, input_data.encode('utf-8'))
        except OSError as e:
            emit('error', {'message': f'Failed to send input: {str(e)}'})

@socketio.on('stop')
def handle_stop(data):
    """Stop a running script."""
    script_name = data.get('script')
    
    with process_lock:
        if script_name not in running_processes:
            emit('error', {'message': 'Script is not running'})
            return
        
        process_info = running_processes[script_name]
        try:
            os.kill(process_info.pid, signal.SIGTERM)
            # Give it a moment, then SIGKILL if needed
            time.sleep(0.5)
            try:
                os.kill(process_info.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        except ProcessLookupError:
            pass
        except Exception as e:
            emit('error', {'message': f'Failed to stop: {str(e)}'})

@socketio.on('stop_external')
def handle_stop_external(data):
    """Stop an external process."""
    pid = data.get('pid')
    if not pid:
        emit('error', {'message': 'No PID specified'})
        return
    
    try:
        os.kill(int(pid), signal.SIGTERM)
        time.sleep(0.5)
        try:
            os.kill(int(pid), signal.SIGKILL)
        except ProcessLookupError:
            pass
        emit('external_stopped', {'pid': pid})
    except Exception as e:
        emit('error', {'message': f'Failed to stop process: {str(e)}'})

@socketio.on('watch')
def handle_watch(data):
    """Start watching a running script's output."""
    script_name = data.get('script')
    
    with process_lock:
        if script_name not in running_processes:
            emit('error', {'message': 'Script is not running'})
            return
        
        process_info = running_processes[script_name]
        process_info.clients.add(request.sid)
        
        # Send existing output
        emit('output', {
            'script': script_name,
            'data': ''.join(process_info.output_log)
        })
        
        emit('watching', {
            'script': script_name,
            'start_time': process_info.start_time,
            'pid': process_info.pid
        })

@socketio.on('status')
def handle_status(data):
    """Get status of running processes."""
    script_name = data.get('script')
    
    if script_name:
        with process_lock:
            if script_name in running_processes:
                pi = running_processes[script_name]
                emit('status', {
                    'script': script_name,
                    'running': True,
                    'pid': pi.pid,
                    'runtime': time.time() - pi.start_time
                })
            else:
                emit('status', {'script': script_name, 'running': False})
    else:
        # Return all running
        with process_lock:
            statuses = {}
            for name, pi in running_processes.items():
                statuses[name] = {
                    'pid': pi.pid,
                    'runtime': time.time() - pi.start_time
                }
        emit('all_status', {'running': statuses})

# ============== Main ==============

if __name__ == '__main__':
    import logging
    
    # Set up logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    logger = logging.getLogger('pyrunner')
    
    try:
        # Ensure directories exist
        Config.CODE_DIR.mkdir(parents=True, exist_ok=True)
        Config.LOG_DIR.mkdir(parents=True, exist_ok=True)
        
        hostname = get_hostname()
        logger.info(f"PyRunner starting on {hostname}")
        logger.info(f"Code directory: {Config.CODE_DIR}")
        logger.info(f"Log directory: {Config.LOG_DIR}")
        logger.info(f"Async mode: {ASYNC_MODE}")
        
        print(f"\n{'='*50}")
        print(f"PyRunner - Python Script Manager")
        print(f"{'='*50}")
        print(f"Host: {hostname}")
        print(f"URL:  http://0.0.0.0:5000")
        print(f"Code: {Config.CODE_DIR}")
        print(f"Mode: {ASYNC_MODE}")
        print(f"{'='*50}\n")
        
        # Run the server
        socketio.run(
            app, 
            host='0.0.0.0', 
            port=5000, 
            debug=False, 
            use_reloader=False, 
            allow_unsafe_werkzeug=True
        )
    except Exception as e:
        logger.error(f"Failed to start PyRunner: {e}")
        print(f"\nERROR: Failed to start PyRunner: {e}")
        print("\nTroubleshooting:")
        print("  1. Check if port 5000 is already in use: ss -tlnp | grep 5000")
        print("  2. Check Python packages: pip list | grep -E 'flask|eventlet|socketio'")
        print("  3. View logs: sudo journalctl -u pyrunner -n 50")
        sys.exit(1)
