"""
PyRunner Configuration

Edit the lists below to customize which Python features are blocked.
Comment out (or remove) items to allow them.
"""

from pathlib import Path

class Config:
    # Directories
    CODE_DIR = Path('/home/pi/pythoncode')
    LOG_DIR = Path('/home/pi/pyrunner/logs')
    AUTOBOOT_FILE = Path('/home/pi/pyrunner/autoboot.txt')
    
    # ============================================================
    # BLOCKED MODULES
    # These imports will be rejected during validation.
    # Comment out any you need to allow.
    # ============================================================
    BLOCKED_MODULES = [
        # === Network/Internet ===
        'socket',
        'socketserver',
        'ssl',
        'urllib',
        'urllib.request',
        'urllib.parse',
        'urllib.error',
        'urllib.robotparser',
        'http',
        'http.client',
        'http.server',
        'http.cookies',
        'http.cookiejar',
        'ftplib',
        'poplib',
        'imaplib',
        'smtplib',
        'telnetlib',
        'xmlrpc',
        'xmlrpc.client',
        'xmlrpc.server',
        'ipaddress',
        'asyncio',  # Can be used for networking
        'aiohttp',
        'requests',
        'httpx',
        'urllib3',
        'websocket',
        'websockets',
        'paramiko',
        'fabric',
        'pycurl',
        'tornado',
        'twisted',
        'flask',
        'django',
        'fastapi',
        'bottle',
        'cherrypy',
        
        # === Database ===
        'sqlite3',
        'dbm',
        'dbm.gnu',
        'dbm.ndbm',
        'dbm.dumb',
        'shelve',
        'psycopg2',
        'pymysql',
        'mysql',
        'mysql.connector',
        'pymongo',
        'redis',
        'sqlalchemy',
        'peewee',
        'cx_Oracle',
        'pyodbc',
        
        # === Subprocess/OS Command Execution ===
        'subprocess',
        'popen2',
        'commands',
        'pexpect',
        'pty',  # We use this, but user scripts shouldn't
        
        # === Code Execution/Import Manipulation ===
        'importlib',
        'importlib.util',
        'importlib.abc',
        'importlib.machinery',
        'importlib.resources',
        'imp',
        'runpy',
        'code',
        'codeop',
        'compileall',
        'py_compile',
        'ast',  # Can be used to analyze/modify code
        'dis',
        'inspect',  # Can access source code
        'types',  # Can create new types dynamically
        
        # === System/Process Control ===
        # 'signal',  # Allowed - needed for gpiozero pause()
        'multiprocessing',
        'concurrent',
        'concurrent.futures',
        '_thread',
        'threading',  # Comment out if you need threading
        'sched',
        'resource',
        'sysconfig',
        'platform',
        'ctypes',  # Can call arbitrary C functions
        'cffi',
        
        # === Serialization (can be security risks) ===
        'pickle',
        'cPickle',
        'marshal',
        'dill',
        'cloudpickle',
    ]
    
    # ============================================================
    # BLOCKED BUILTINS
    # These built-in functions will be rejected.
    # Comment out any you need to allow.
    # ============================================================
    BLOCKED_BUILTINS = [
        'eval',
        'exec',
        'compile',
        '__import__',
        'globals',
        'locals',
        'vars',
        'dir',  # Can be used for introspection
        'getattr',  # Can access private attributes
        'setattr',
        'delattr',
        'hasattr',
        'breakpoint',
        'memoryview',
        'bytearray',  # Comment out if needed
    ]
    
    # ============================================================
    # BLOCKED FUNCTIONS/METHODS
    # These specific function calls will be rejected.
    # Format: 'module.function' or 'object.method'
    # Comment out any you need to allow.
    # ============================================================
    BLOCKED_FUNCTIONS = [
        # OS functions that could be dangerous
        'os.system',
        'os.popen',
        'os.spawn',
        'os.spawnl',
        'os.spawnle',
        'os.spawnlp',
        'os.spawnlpe',
        'os.spawnv',
        'os.spawnve',
        'os.spawnvp',
        'os.spawnvpe',
        'os.exec',
        'os.execl',
        'os.execle',
        'os.execlp',
        'os.execlpe',
        'os.execv',
        'os.execve',
        'os.execvp',
        'os.execvpe',
        'os.fork',
        'os.forkpty',
        'os.kill',
        'os.killpg',
        'os.plock',
        'os.startfile',
        
        # File operations outside allowed directory
        # (these are checked contextually in validator)
    ]
    
    # ============================================================
    # ALLOWED FILE PATHS
    # Scripts can only read/write within these directories
    # ============================================================
    ALLOWED_PATHS = [
        '/home/pi/pythoncode',
    ]
    
    # ============================================================
    # GPIO - ALLOWED
    # These modules are explicitly allowed for GPIO access
    # ============================================================
    ALLOWED_MODULES = [
        'RPi',
        'RPi.GPIO',
        'gpiozero',
        'pigpio',
        'RPIO',
        'wiringpi',
        'spidev',
        'smbus',
        'smbus2',
    ]
