"""
Python Code Validator

Uses AST analysis to check for blocked modules, functions, and file operations.
"""

import ast
from pathlib import Path
from typing import List, Tuple, Set

from config import Config


class SecurityVisitor(ast.NodeVisitor):
    """AST visitor that checks for blocked operations."""
    
    def __init__(self, code_dir: Path):
        self.errors: List[str] = []
        self.imports: Set[str] = set()
        self.local_imports: Set[str] = set()
        self.code_dir = code_dir
    
    def visit_Import(self, node: ast.Import):
        """Check import statements."""
        for alias in node.names:
            module_name = alias.name
            self.imports.add(module_name)
            
            # Check if blocked
            if self._is_blocked_module(module_name):
                self.errors.append(
                    f"Line {node.lineno}: Blocked import '{module_name}'"
                )
            
            # Check for local import
            if self._is_local_import(module_name):
                self.local_imports.add(module_name)
        
        self.generic_visit(node)
    
    def visit_ImportFrom(self, node: ast.ImportFrom):
        """Check from ... import statements."""
        module_name = node.module or ''
        self.imports.add(module_name)
        
        # Check if blocked
        if self._is_blocked_module(module_name):
            self.errors.append(
                f"Line {node.lineno}: Blocked import 'from {module_name}'"
            )
        
        # Check specific imports from allowed modules
        for alias in node.names:
            full_name = f"{module_name}.{alias.name}" if module_name else alias.name
            if self._is_blocked_module(full_name):
                self.errors.append(
                    f"Line {node.lineno}: Blocked import '{full_name}'"
                )
        
        # Check for local import
        if module_name and self._is_local_import(module_name):
            self.local_imports.add(module_name)
        
        self.generic_visit(node)
    
    def visit_Call(self, node: ast.Call):
        """Check function calls."""
        func_name = self._get_call_name(node)
        
        if func_name:
            # Check blocked builtins
            if func_name in Config.BLOCKED_BUILTINS:
                self.errors.append(
                    f"Line {node.lineno}: Blocked builtin '{func_name}()'"
                )
            
            # Check blocked functions
            if func_name in Config.BLOCKED_FUNCTIONS:
                self.errors.append(
                    f"Line {node.lineno}: Blocked function '{func_name}()'"
                )
            
            # Check for file operations
            self._check_file_operation(node, func_name)
        
        self.generic_visit(node)
    
    def visit_Attribute(self, node: ast.Attribute):
        """Check attribute access for blocked patterns."""
        attr_chain = self._get_attribute_chain(node)
        
        if attr_chain:
            # Check if it matches a blocked function pattern
            if attr_chain in Config.BLOCKED_FUNCTIONS:
                self.errors.append(
                    f"Line {node.lineno}: Blocked attribute '{attr_chain}'"
                )
            
            # Check for __dunder__ access that could bypass restrictions
            if '__' in node.attr and node.attr not in ('__init__', '__main__', '__name__', '__doc__', '__str__', '__repr__'):
                # Allow common dunder methods, block suspicious ones
                suspicious = ['__class__', '__bases__', '__mro__', '__subclasses__', 
                             '__globals__', '__code__', '__builtins__', '__import__',
                             '__getattribute__', '__reduce__', '__reduce_ex__']
                if node.attr in suspicious:
                    self.errors.append(
                        f"Line {node.lineno}: Blocked dunder access '{node.attr}'"
                    )
        
        self.generic_visit(node)
    
    def _is_blocked_module(self, module_name: str) -> bool:
        """Check if a module is blocked."""
        if not module_name:
            return False
        
        # First check if explicitly allowed (GPIO modules)
        for allowed in Config.ALLOWED_MODULES:
            if module_name == allowed or module_name.startswith(allowed + '.'):
                return False
        
        # Check against blocked list
        for blocked in Config.BLOCKED_MODULES:
            if module_name == blocked or module_name.startswith(blocked + '.'):
                return True
        
        return False
    
    def _is_local_import(self, module_name: str) -> bool:
        """Check if this is an import of a local file (not standard library)."""
        if not module_name:
            return False
        
        # Standard library modules that should NOT be flagged as local
        # This is not exhaustive but covers common ones
        STDLIB_MODULES = {
            # Built-in and common standard library
            'abc', 'aifc', 'argparse', 'array', 'ast', 'asynchat', 'asyncio', 'asyncore',
            'atexit', 'audioop', 'base64', 'bdb', 'binascii', 'binhex', 'bisect',
            'builtins', 'bz2', 'calendar', 'cgi', 'cgitb', 'chunk', 'cmath', 'cmd',
            'code', 'codecs', 'codeop', 'collections', 'colorsys', 'compileall',
            'concurrent', 'configparser', 'contextlib', 'contextvars', 'copy',
            'copyreg', 'cProfile', 'crypt', 'csv', 'ctypes', 'curses', 'dataclasses',
            'datetime', 'dbm', 'decimal', 'difflib', 'dis', 'distutils', 'doctest',
            'email', 'encodings', 'enum', 'errno', 'faulthandler', 'fcntl', 'filecmp',
            'fileinput', 'fnmatch', 'fractions', 'ftplib', 'functools', 'gc',
            'getopt', 'getpass', 'gettext', 'glob', 'graphlib', 'grp', 'gzip',
            'hashlib', 'heapq', 'hmac', 'html', 'http', 'imaplib', 'imghdr', 'imp',
            'importlib', 'inspect', 'io', 'ipaddress', 'itertools', 'json',
            'keyword', 'lib2to3', 'linecache', 'locale', 'logging', 'lzma',
            'mailbox', 'mailcap', 'marshal', 'math', 'mimetypes', 'mmap', 'modulefinder',
            'multiprocessing', 'netrc', 'nis', 'nntplib', 'numbers', 'operator', 'optparse',
            'os', 'ossaudiodev', 'pathlib', 'pdb', 'pickle', 'pickletools', 'pipes',
            'pkgutil', 'platform', 'plistlib', 'poplib', 'posix', 'posixpath', 'pprint',
            'profile', 'pstats', 'pty', 'pwd', 'py_compile', 'pyclbr', 'pydoc', 'queue',
            'quopri', 'random', 're', 'readline', 'reprlib', 'resource', 'rlcompleter',
            'runpy', 'sched', 'secrets', 'select', 'selectors', 'shelve', 'shlex',
            'shutil', 'signal', 'site', 'smtpd', 'smtplib', 'sndhdr', 'socket',
            'socketserver', 'spwd', 'sqlite3', 'ssl', 'stat', 'statistics', 'string',
            'stringprep', 'struct', 'subprocess', 'sunau', 'symtable', 'sys', 'sysconfig',
            'syslog', 'tabnanny', 'tarfile', 'telnetlib', 'tempfile', 'termios', 'test',
            'textwrap', 'threading', 'time', 'timeit', 'tkinter', 'token', 'tokenize',
            'trace', 'traceback', 'tracemalloc', 'tty', 'turtle', 'turtledemo', 'types',
            'typing', 'unicodedata', 'unittest', 'urllib', 'uu', 'uuid', 'venv',
            'warnings', 'wave', 'weakref', 'webbrowser', 'winreg', 'winsound', 'wsgiref',
            'xdrlib', 'xml', 'xmlrpc', 'zipapp', 'zipfile', 'zipimport', 'zlib',
            # Common third-party that might be installed system-wide
            'gpiozero', 'RPi', 'pigpio', 'numpy', 'PIL', 'cv2', 'pygame',
        }
        
        # Simple module name (no dots) could be local
        if '.' not in module_name:
            # If it's a known standard library module, it's not local
            if module_name in STDLIB_MODULES:
                return False
            # Otherwise, it might be a local import
            return True
        
        return False
    
    def _get_call_name(self, node: ast.Call) -> str:
        """Extract the function name from a Call node."""
        if isinstance(node.func, ast.Name):
            return node.func.id
        elif isinstance(node.func, ast.Attribute):
            return self._get_attribute_chain(node.func)
        return ''
    
    def _get_attribute_chain(self, node: ast.Attribute) -> str:
        """Get the full attribute chain (e.g., 'os.path.join')."""
        parts = []
        current = node
        
        while isinstance(current, ast.Attribute):
            parts.append(current.attr)
            current = current.value
        
        if isinstance(current, ast.Name):
            parts.append(current.id)
        
        return '.'.join(reversed(parts))
    
    def _check_file_operation(self, node: ast.Call, func_name: str):
        """Check file operations for path restrictions."""
        # Check open() calls
        if func_name == 'open':
            self._check_path_argument(node, 'open')
        
        # Check Path operations
        if func_name.endswith('.write_text') or func_name.endswith('.write_bytes'):
            self._check_path_argument(node, func_name)
        
        # Check os file operations
        dangerous_os_funcs = [
            'os.remove', 'os.unlink', 'os.rmdir', 'os.removedirs',
            'os.rename', 'os.renames', 'os.replace',
            'os.mkdir', 'os.makedirs', 'os.mknod', 'os.mkfifo',
            'os.link', 'os.symlink', 'os.truncate',
            'shutil.rmtree', 'shutil.copy', 'shutil.copy2', 'shutil.copytree',
            'shutil.move', 'shutil.chown'
        ]
        
        if func_name in dangerous_os_funcs:
            self._check_path_argument(node, func_name)
    
    def _check_path_argument(self, node: ast.Call, func_name: str):
        """Check if a path argument is within allowed directories."""
        if not node.args:
            return
        
        first_arg = node.args[0]
        
        # If it's a string literal, we can check it
        if isinstance(first_arg, ast.Constant) and isinstance(first_arg.value, str):
            path = first_arg.value
            if not self._is_path_allowed(path):
                self.errors.append(
                    f"Line {node.lineno}: File operation '{func_name}' on disallowed path '{path}'"
                )
        
        # Check for write mode in open()
        if func_name == 'open' and len(node.args) > 1:
            mode_arg = node.args[1]
            if isinstance(mode_arg, ast.Constant) and isinstance(mode_arg.value, str):
                mode = mode_arg.value
                if any(c in mode for c in 'wax+'):
                    # Write mode - need to verify path
                    if isinstance(first_arg, ast.Constant) and isinstance(first_arg.value, str):
                        if not self._is_path_allowed(first_arg.value):
                            self.errors.append(
                                f"Line {node.lineno}: Write operation on disallowed path"
                            )
                    else:
                        # Dynamic path with write mode - warn
                        self.errors.append(
                            f"Line {node.lineno}: Write operation with dynamic path - ensure path is within /home/pi/pythoncode"
                        )
        
        # Check keyword arguments
        for kw in node.keywords:
            if kw.arg == 'mode' and isinstance(kw.value, ast.Constant):
                if isinstance(kw.value.value, str) and any(c in kw.value.value for c in 'wax+'):
                    if isinstance(first_arg, ast.Constant) and isinstance(first_arg.value, str):
                        if not self._is_path_allowed(first_arg.value):
                            self.errors.append(
                                f"Line {node.lineno}: Write operation on disallowed path"
                            )
    
    def _is_path_allowed(self, path: str) -> bool:
        """Check if a path is within allowed directories."""
        try:
            # Resolve the path
            resolved = Path(path).resolve()
            
            # Check against allowed paths
            for allowed in Config.ALLOWED_PATHS:
                allowed_path = Path(allowed).resolve()
                try:
                    resolved.relative_to(allowed_path)
                    return True
                except ValueError:
                    continue
            
            return False
        except Exception:
            # If we can't resolve, assume not allowed
            return False


class PythonValidator:
    """Validates Python code for security and correctness."""
    
    def __init__(self, code_dir: Path):
        self.code_dir = code_dir
    
    def validate(self, code: str, filename: str = '<unknown>') -> Tuple[bool, List[str]]:
        """
        Validate Python code.
        
        Returns:
            Tuple of (is_valid, list_of_errors)
        """
        errors = []
        
        # Step 1: Parse the code
        try:
            tree = ast.parse(code, filename=filename)
        except SyntaxError as e:
            return False, [f"Syntax error at line {e.lineno}: {e.msg}"]
        except Exception as e:
            return False, [f"Parse error: {str(e)}"]
        
        # Step 2: Run security visitor
        visitor = SecurityVisitor(self.code_dir)
        visitor.visit(tree)
        errors.extend(visitor.errors)
        
        # Step 3: Additional checks
        additional_errors = self._additional_checks(code, tree)
        errors.extend(additional_errors)
        
        return len(errors) == 0, errors
    
    def get_missing_local_imports(self, code: str) -> List[str]:
        """
        Get list of local imports that don't exist.
        
        Returns:
            List of missing module names
        """
        try:
            tree = ast.parse(code)
        except SyntaxError:
            return []
        
        visitor = SecurityVisitor(self.code_dir)
        visitor.visit(tree)
        
        missing = []
        for module in visitor.local_imports:
            # Check if the file exists
            module_path = self.code_dir / f"{module}.py"
            if not module_path.exists():
                missing.append(module)
        
        return missing
    
    def _additional_checks(self, code: str, tree: ast.AST) -> List[str]:
        """Run additional security checks."""
        errors = []
        
        # Check for string-based code execution patterns
        dangerous_patterns = [
            ('__import__', 'Dynamic import attempt'),
            ('getattr(', 'Dynamic attribute access'),
            ('setattr(', 'Dynamic attribute setting'),
            ('delattr(', 'Dynamic attribute deletion'),
            ("exec(", 'Dynamic code execution'),
            ("eval(", 'Dynamic code evaluation'),
            ('compile(', 'Dynamic code compilation'),
            ('__builtins__', 'Builtins access'),
            ('__globals__', 'Globals access'),
            ('__subclasses__', 'Subclass enumeration'),
        ]
        
        for pattern, description in dangerous_patterns:
            if pattern in code:
                # Find line number
                for i, line in enumerate(code.split('\n'), 1):
                    if pattern in line and not line.strip().startswith('#'):
                        errors.append(f"Line {i}: {description} detected ('{pattern}')")
        
        return errors


# For command-line testing
if __name__ == '__main__':
    import sys
    
    if len(sys.argv) < 2:
        print("Usage: python validator.py <file.py>")
        sys.exit(1)
    
    filepath = Path(sys.argv[1])
    if not filepath.exists():
        print(f"File not found: {filepath}")
        sys.exit(1)
    
    code = filepath.read_text()
    validator = PythonValidator(filepath.parent)
    
    is_valid, errors = validator.validate(code, filepath.name)
    missing = validator.get_missing_local_imports(code)
    
    if is_valid:
        print(f"✓ {filepath.name} is valid")
        if missing:
            print(f"  ⚠ Missing local imports: {', '.join(missing)}")
            print("  File is valid but not executable until dependencies are uploaded")
    else:
        print(f"✗ {filepath.name} has errors:")
        for error in errors:
            print(f"  - {error}")
