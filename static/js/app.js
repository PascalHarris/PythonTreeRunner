/**
 * PyRunner - Frontend Application
 */

class PyRunner {
    constructor() {
        this.socket = null;
        this.currentScript = null;
        this.runtimeInterval = null;
        this.startTime = null;
        
        this.init();
    }
    
    init() {
        this.bindElements();
        this.bindEvents();
        this.connectSocket();
        this.loadScripts();
    }
    
    bindElements() {
        // Sections
        this.uploadSection = document.getElementById('uploadSection');
        this.validationSection = document.getElementById('validationSection');
        this.browserSection = document.getElementById('browserSection');
        this.executionSection = document.getElementById('executionSection');
        this.logSection = document.getElementById('logSection');
        
        // Upload
        this.uploadZone = document.getElementById('uploadZone');
        this.fileInput = document.getElementById('fileInput');
        
        // Validation
        this.validationContent = document.getElementById('validationContent');
        this.closeValidation = document.getElementById('closeValidation');
        
        // Browser
        this.fileList = document.getElementById('fileList');
        this.externalSection = document.getElementById('externalSection');
        this.externalList = document.getElementById('externalList');
        this.refreshBtn = document.getElementById('refreshBtn');
        
        // Execution
        this.execScriptName = document.getElementById('execScriptName');
        this.execRuntime = document.getElementById('execRuntime');
        this.execPid = document.getElementById('execPid');
        this.terminalOutput = document.getElementById('terminalOutput');
        this.terminalInput = document.getElementById('terminalInput');
        this.stopBtn = document.getElementById('stopBtn');
        this.backToListBtn = document.getElementById('backToListBtn');
        
        // Log
        this.logScriptName = document.getElementById('logScriptName');
        this.logContent = document.getElementById('logContent');
        this.closeLog = document.getElementById('closeLog');
        
        // Connection status
        this.connectionStatus = document.getElementById('connectionStatus');
        
        // Modal
        this.confirmModal = document.getElementById('confirmModal');
        this.confirmTitle = document.getElementById('confirmTitle');
        this.confirmMessage = document.getElementById('confirmMessage');
        this.confirmOk = document.getElementById('confirmOk');
        this.confirmCancel = document.getElementById('confirmCancel');
        
        // Toast container
        this.toastContainer = document.getElementById('toastContainer');
    }
    
    bindEvents() {
        // Upload zone - click
        this.uploadZone.addEventListener('click', () => this.fileInput.click());
        
        // Upload zone - drag & drop
        this.uploadZone.addEventListener('dragover', (e) => {
            e.preventDefault();
            this.uploadZone.classList.add('dragover');
        });
        
        this.uploadZone.addEventListener('dragleave', () => {
            this.uploadZone.classList.remove('dragover');
        });
        
        this.uploadZone.addEventListener('drop', (e) => {
            e.preventDefault();
            this.uploadZone.classList.remove('dragover');
            const files = e.dataTransfer.files;
            if (files.length > 0) {
                this.uploadFile(files[0]);
            }
        });
        
        // File input change
        this.fileInput.addEventListener('change', (e) => {
            if (e.target.files.length > 0) {
                this.uploadFile(e.target.files[0]);
            }
        });
        
        // Close validation
        this.closeValidation.addEventListener('click', () => {
            this.validationSection.classList.add('hidden');
        });
        
        // Refresh
        this.refreshBtn.addEventListener('click', () => this.loadScripts());
        
        // Terminal input
        this.terminalInput.addEventListener('keydown', (e) => {
            if (e.key === 'Enter') {
                const input = this.terminalInput.value;
                this.sendInput(input + '\n');
                this.terminalInput.value = '';
            }
        });
        
        // Stop button
        this.stopBtn.addEventListener('click', () => this.stopScript());
        
        // Back to list
        this.backToListBtn.addEventListener('click', () => this.showBrowser());
        
        // Close log
        this.closeLog.addEventListener('click', () => {
            this.logSection.classList.add('hidden');
            this.browserSection.classList.remove('hidden');
        });
        
        // Modal cancel
        this.confirmCancel.addEventListener('click', () => {
            this.confirmModal.classList.add('hidden');
        });
        
        // Click outside modal
        this.confirmModal.querySelector('.modal-backdrop').addEventListener('click', () => {
            this.confirmModal.classList.add('hidden');
        });
    }
    
    connectSocket() {
        this.socket = io();
        
        this.socket.on('connect', () => {
            this.updateConnectionStatus(true);
        });
        
        this.socket.on('disconnect', () => {
            this.updateConnectionStatus(false);
        });
        
        this.socket.on('connected', (data) => {
            document.getElementById('hostname').textContent = data.hostname;
        });
        
        this.socket.on('started', (data) => {
            this.currentScript = data.script;
            this.startTime = data.start_time * 1000;
            this.execScriptName.textContent = data.script;
            this.execPid.textContent = `PID: ${data.pid}`;
            this.terminalOutput.innerHTML = '';
            this.showExecution();
            this.startRuntimeCounter();
            this.toast(`Started ${data.script}`, 'success');
        });
        
        this.socket.on('output', (data) => {
            this.appendOutput(data.data);
        });
        
        this.socket.on('process_ended', (data) => {
            this.stopRuntimeCounter();
            this.toast(`${data.script} finished`, 'success');
            this.loadScripts();
        });
        
        this.socket.on('watching', (data) => {
            this.currentScript = data.script;
            this.startTime = data.start_time * 1000;
            this.execScriptName.textContent = data.script;
            this.execPid.textContent = `PID: ${data.pid}`;
            this.showExecution();
            this.startRuntimeCounter();
        });
        
        this.socket.on('error', (data) => {
            this.toast(data.message, 'error');
            if (data.errors) {
                console.error('Validation errors:', data.errors);
            }
        });
        
        this.socket.on('external_stopped', (data) => {
            this.toast(`Stopped external process ${data.pid}`, 'success');
            this.loadScripts();
        });
    }
    
    updateConnectionStatus(connected) {
        const dot = this.connectionStatus.querySelector('.status-dot');
        const text = this.connectionStatus.querySelector('.status-text');
        
        if (connected) {
            dot.classList.remove('disconnected');
            dot.classList.add('connected');
            text.textContent = 'Connected';
        } else {
            dot.classList.remove('connected');
            dot.classList.add('disconnected');
            text.textContent = 'Disconnected';
        }
    }
    
    async uploadFile(file) {
        if (!file.name.endsWith('.py')) {
            this.toast('Only .py files are accepted', 'error');
            return;
        }
        
        const formData = new FormData();
        formData.append('file', file);
        
        try {
            const response = await fetch('/api/upload', {
                method: 'POST',
                body: formData
            });
            
            const result = await response.json();
            this.showValidationResult(result);
            
            if (result.saved) {
                this.loadScripts();
            }
        } catch (error) {
            this.toast('Upload failed: ' + error.message, 'error');
        }
        
        // Reset file input
        this.fileInput.value = '';
    }
    
    showValidationResult(result) {
        this.validationSection.classList.remove('hidden');
        
        const isSuccess = result.is_valid;
        const hasWarnings = result.missing_deps && result.missing_deps.length > 0;
        
        let html = `
            <div class="validation-result">
                <div class="validation-icon ${isSuccess ? 'success' : 'error'}">
                    ${isSuccess ? 
                        '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2"><polyline points="20 6 9 17 4 12"/></svg>' :
                        '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>'
                    }
                </div>
                <div class="validation-details">
                    <h3>${isSuccess ? 'Valid' : 'Invalid'}: <span class="filename">${result.filename}</span></h3>
                    ${isSuccess ? 
                        (result.is_executable ? 
                            '<p>File saved and ready to execute.</p>' :
                            '<p>File saved but has missing dependencies.</p>') :
                        '<p>File was not saved due to validation errors.</p>'
                    }
        `;
        
        if (result.errors && result.errors.length > 0) {
            html += `
                <ul class="validation-errors">
                    ${result.errors.map(e => `<li>${this.escapeHtml(e)}</li>`).join('')}
                </ul>
            `;
        }
        
        if (hasWarnings) {
            html += `
                <ul class="validation-warnings">
                    <li>Missing local imports: ${result.missing_deps.join(', ')}</li>
                    <li>Upload these files to make the script executable.</li>
                </ul>
            `;
        }
        
        html += '</div></div>';
        this.validationContent.innerHTML = html;
    }
    
    async loadScripts() {
        this.fileList.innerHTML = '<div class="loading">Loading scripts...</div>';
        
        try {
            const response = await fetch('/api/scripts');
            const data = await response.json();
            
            this.renderScripts(data.scripts);
            this.renderExternalProcesses(data.external_processes);
        } catch (error) {
            this.fileList.innerHTML = `<div class="empty-state">Failed to load scripts: ${error.message}</div>`;
        }
    }
    
    renderScripts(scripts) {
        if (scripts.length === 0) {
            this.fileList.innerHTML = `
                <div class="empty-state">
                    <svg viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="currentColor" stroke-width="1.5">
                        <path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/>
                        <polyline points="14 2 14 8 20 8"/>
                    </svg>
                    <p>No Python scripts yet</p>
                    <p>Upload a .py file to get started</p>
                </div>
            `;
            return;
        }
        
        const html = scripts.map(script => this.renderScriptItem(script)).join('');
        this.fileList.innerHTML = html;
        
        // Bind events
        this.fileList.querySelectorAll('[data-action]').forEach(btn => {
            btn.addEventListener('click', (e) => {
                e.stopPropagation();
                const action = btn.dataset.action;
                const scriptName = btn.dataset.script;
                
                switch (action) {
                    case 'play':
                        this.startScript(scriptName);
                        break;
                    case 'watch':
                        this.watchScript(scriptName);
                        break;
                    case 'stop':
                        this.stopScriptByName(scriptName);
                        break;
                    case 'log':
                        this.showLog(scriptName);
                        break;
                    case 'delete':
                        this.confirmDelete(scriptName);
                        break;
                    case 'autoboot':
                        this.toggleAutoboot(scriptName, btn.dataset.enabled === 'true');
                        break;
                }
            });
        });
    }
    
    renderScriptItem(script) {
        const iconClass = script.is_running ? '' : 
                         (!script.is_valid ? 'invalid' : 
                         (!script.is_executable ? 'warning' : ''));
        
        let statusHtml = '';
        if (!script.is_valid && script.errors.length > 0) {
            statusHtml = `<div class="file-status error">${script.errors[0]}</div>`;
        } else if (!script.is_executable && script.missing_deps.length > 0) {
            statusHtml = `<div class="file-status warning">Missing: ${script.missing_deps.join(', ')}</div>`;
        }
        
        let actionsHtml = '';
        
        if (script.is_running) {
            // Running: show watch (arrow) and stop
            actionsHtml = `
                <button class="btn btn-icon play" data-action="watch" data-script="${script.name}" title="View execution">
                    <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2">
                        <polyline points="9 18 15 12 9 6"/>
                    </svg>
                </button>
                <button class="btn btn-icon stop" data-action="stop" data-script="${script.name}" title="Stop">
                    <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2">
                        <rect x="6" y="6" width="12" height="12" rx="1"/>
                    </svg>
                </button>
            `;
        } else {
            // Not running
            if (script.is_executable) {
                actionsHtml += `
                    <button class="btn btn-icon play" data-action="play" data-script="${script.name}" title="Run">
                        <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2">
                            <polygon points="5 3 19 12 5 21 5 3"/>
                        </svg>
                    </button>
                `;
            }
            
            if (script.has_log) {
                actionsHtml += `
                    <button class="btn btn-icon" data-action="log" data-script="${script.name}" title="View log">
                        <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2">
                            <path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/>
                            <polyline points="14 2 14 8 20 8"/>
                            <line x1="16" y1="13" x2="8" y2="13"/>
                            <line x1="16" y1="17" x2="8" y2="17"/>
                        </svg>
                    </button>
                `;
            }
            
            // Autoboot toggle
            if (script.is_executable) {
                actionsHtml += `
                    <button class="btn btn-icon ${script.is_autoboot ? 'play' : ''}" 
                            data-action="autoboot" 
                            data-script="${script.name}" 
                            data-enabled="${!script.is_autoboot}"
                            title="${script.is_autoboot ? 'Remove from autoboot' : 'Set as autoboot'}">
                        <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2">
                            <path d="M18.36 6.64a9 9 0 11-12.73 0"/>
                            <line x1="12" y1="2" x2="12" y2="12"/>
                        </svg>
                    </button>
                `;
            }
        }
        
        // Delete button (not for running scripts)
        if (!script.is_running) {
            actionsHtml += `
                <button class="btn btn-icon delete" data-action="delete" data-script="${script.name}" title="Delete">
                    <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2">
                        <polyline points="3 6 5 6 21 6"/>
                        <path d="M19 6v14a2 2 0 01-2 2H7a2 2 0 01-2-2V6m3 0V4a2 2 0 012-2h4a2 2 0 012 2v2"/>
                    </svg>
                </button>
            `;
        }
        
        return `
            <div class="file-item ${script.is_running ? 'running' : ''}">
                <div class="file-icon ${iconClass}">
                    <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2">
                        <path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/>
                        <polyline points="14 2 14 8 20 8"/>
                    </svg>
                </div>
                <div class="file-info">
                    <div class="file-name">
                        ${this.escapeHtml(script.name)}
                        ${script.is_autoboot ? '<span class="autoboot-badge">Autoboot</span>' : ''}
                        ${script.is_running ? '<span class="autoboot-badge" style="background: var(--accent-glow); color: var(--accent-primary);">Running</span>' : ''}
                    </div>
                    <div class="file-meta">${this.formatSize(script.size)} • ${this.formatDate(script.modified)}</div>
                    ${statusHtml}
                </div>
                <div class="file-actions">
                    ${actionsHtml}
                </div>
            </div>
        `;
    }
    
    renderExternalProcesses(processes) {
        if (processes.length === 0) {
            this.externalSection.classList.add('hidden');
            return;
        }
        
        this.externalSection.classList.remove('hidden');
        
        const html = processes.map(proc => `
            <div class="external-item">
                <div class="external-info">
                    <strong>${proc.name}</strong> (PID: ${proc.pid})
                </div>
                <button class="btn btn-icon stop" data-action="stop-external" data-pid="${proc.pid}" title="Stop">
                    <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2">
                        <rect x="6" y="6" width="12" height="12" rx="1"/>
                    </svg>
                </button>
            </div>
        `).join('');
        
        this.externalList.innerHTML = html;
        
        // Bind events
        this.externalList.querySelectorAll('[data-action="stop-external"]').forEach(btn => {
            btn.addEventListener('click', () => {
                this.socket.emit('stop_external', { pid: parseInt(btn.dataset.pid) });
            });
        });
    }
    
    startScript(scriptName) {
        this.socket.emit('start', { script: scriptName });
    }
    
    watchScript(scriptName) {
        this.terminalOutput.innerHTML = '';
        this.socket.emit('watch', { script: scriptName });
    }
    
    stopScript() {
        if (this.currentScript) {
            this.socket.emit('stop', { script: this.currentScript });
        }
    }
    
    stopScriptByName(scriptName) {
        this.socket.emit('stop', { script: scriptName });
    }
    
    sendInput(input) {
        if (this.currentScript) {
            this.socket.emit('input', { script: this.currentScript, data: input });
        }
    }
    
    async showLog(scriptName) {
        try {
            const response = await fetch(`/api/scripts/${scriptName}/log`);
            const data = await response.json();
            
            if (data.error) {
                this.toast(data.error, 'error');
                return;
            }
            
            this.logScriptName.textContent = scriptName;
            this.logContent.textContent = data.log;
            
            this.browserSection.classList.add('hidden');
            this.logSection.classList.remove('hidden');
        } catch (error) {
            this.toast('Failed to load log: ' + error.message, 'error');
        }
    }
    
    confirmDelete(scriptName) {
        this.confirmTitle.textContent = 'Delete Script';
        this.confirmMessage.textContent = `Are you sure you want to delete "${scriptName}"? This action cannot be undone.`;
        
        this.confirmOk.onclick = async () => {
            this.confirmModal.classList.add('hidden');
            await this.deleteScript(scriptName);
        };
        
        this.confirmModal.classList.remove('hidden');
    }
    
    async deleteScript(scriptName) {
        try {
            const response = await fetch(`/api/scripts/${scriptName}`, {
                method: 'DELETE'
            });
            
            const data = await response.json();
            
            if (data.error) {
                this.toast(data.error, 'error');
            } else {
                this.toast(`Deleted ${scriptName}`, 'success');
                this.loadScripts();
            }
        } catch (error) {
            this.toast('Failed to delete: ' + error.message, 'error');
        }
    }
    
    async toggleAutoboot(scriptName, enable) {
        try {
            const response = await fetch(`/api/scripts/${scriptName}/autoboot`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ enabled: enable })
            });
            
            const data = await response.json();
            
            if (data.error) {
                this.toast(data.error, 'error');
            } else {
                this.toast(
                    enable ? `${scriptName} set as autoboot` : `Autoboot disabled for ${scriptName}`,
                    'success'
                );
                this.loadScripts();
            }
        } catch (error) {
            this.toast('Failed to update autoboot: ' + error.message, 'error');
        }
    }
    
    showBrowser() {
        this.executionSection.classList.add('hidden');
        this.browserSection.classList.remove('hidden');
        this.uploadSection.classList.remove('hidden');
        this.loadScripts();
    }
    
    showExecution() {
        this.browserSection.classList.add('hidden');
        this.uploadSection.classList.add('hidden');
        this.validationSection.classList.add('hidden');
        this.logSection.classList.add('hidden');
        this.executionSection.classList.remove('hidden');
        this.terminalInput.focus();
    }
    
    appendOutput(text) {
        // Convert ANSI escape codes to spans (basic support)
        const escaped = this.escapeHtml(text);
        this.terminalOutput.innerHTML += escaped;
        this.terminalOutput.scrollTop = this.terminalOutput.scrollHeight;
    }
    
    startRuntimeCounter() {
        this.stopRuntimeCounter();
        this.updateRuntime();
        this.runtimeInterval = setInterval(() => this.updateRuntime(), 1000);
    }
    
    stopRuntimeCounter() {
        if (this.runtimeInterval) {
            clearInterval(this.runtimeInterval);
            this.runtimeInterval = null;
        }
    }
    
    updateRuntime() {
        if (!this.startTime) return;
        
        const elapsed = Date.now() - this.startTime;
        const hours = Math.floor(elapsed / 3600000);
        const minutes = Math.floor((elapsed % 3600000) / 60000);
        const seconds = Math.floor((elapsed % 60000) / 1000);
        
        this.execRuntime.textContent = 
            `${hours.toString().padStart(2, '0')}:${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
    }
    
    toast(message, type = 'info') {
        const toast = document.createElement('div');
        toast.className = `toast ${type}`;
        toast.textContent = message;
        
        this.toastContainer.appendChild(toast);
        
        setTimeout(() => {
            toast.style.opacity = '0';
            toast.style.transform = 'translateX(100%)';
            setTimeout(() => toast.remove(), 300);
        }, 4000);
    }
    
    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }
    
    formatSize(bytes) {
        if (bytes < 1024) return bytes + ' B';
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
        return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
    }
    
    formatDate(isoString) {
        const date = new Date(isoString);
        const now = new Date();
        const diff = now - date;
        
        if (diff < 60000) return 'Just now';
        if (diff < 3600000) return Math.floor(diff / 60000) + ' min ago';
        if (diff < 86400000) return Math.floor(diff / 3600000) + ' hours ago';
        
        return date.toLocaleDateString();
    }
}

// Initialize on DOM ready
document.addEventListener('DOMContentLoaded', () => {
    window.pyrunner = new PyRunner();
});
