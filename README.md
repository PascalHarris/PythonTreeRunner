# Python Tree Runner

A web-based Python script runner for the Raspberry Pi Christmas Tree. Upload, validate, execute, and manage your Christmas Tree (and other Python scripts) through a web interface.

## Features

- **Drag & Drop Upload**: Upload Python files by dragging them into the browser
- **Security Validation**: Scripts are analyzed for dangerous operations (network, database, file system access)
- **Interactive Execution**: Run scripts with real-time I/O through a web terminal
- **Multiple Concurrent Scripts**: Run multiple different scripts simultaneously
- **Process Management**: Start, stop, and monitor running scripts
- **Execution Logs**: View logs from previous script executions
- **Autoboot**: Configure a script to run automatically at system startup
- **External Process Detection**: See and manage Python scripts started outside the web interface
- **GPIO Support**: Full access to Raspberry Pi GPIO through RPi.GPIO and gpiozero

## Installation

### Quick Install

1. Copy the Python Tree Runner files to your Raspberry Pi
2. Run the installation script:

```bash
chmod +x install.sh
./install.sh
```

### Manual Installation

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install system packages
sudo apt install -y python3 python3-pip python3-venv python3-dev \
    python3-rpi.gpio python3-gpiozero python3-smbus \
    libffi-dev libssl-dev

# Create directories
mkdir -p /home/pi/pyrunner /home/pi/pythoncode /home/pi/pyrunner/logs

# Create virtual environment
cd /home/pi/pyrunner
python3 -m venv venv
source venv/bin/activate

# Install Python packages
pip install flask flask-socketio python-socketio eventlet

# Copy application files to /home/pi/pyrunner
# (app.py, config.py, validator.py, templates/, static/)

# Install systemd services
sudo cp systemd/pyrunner.service /etc/systemd/system/
sudo cp systemd/pyrunner-autoboot.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable pyrunner pyrunner-autoboot

# Add user to GPIO groups
sudo usermod -a -G gpio,i2c,spi pi

# Start the service
sudo systemctl start pyrunner
```

## Usage

### Accessing the Web Interface

Open a browser and navigate to:
- `http://raspberrypi.local` (if mDNS is working)
- `http://<pi-ip-address>`

### Uploading Scripts

1. Drag a `.py` file onto the upload zone, or click to select a file
2. The script will be validated for security issues
3. If valid, it will be saved to `/home/pi/pythoncode`
4. If there are errors, they will be displayed

### Running Scripts

1. Click the play button (▶) next to an executable script
2. The terminal view will open showing output
3. Type in the input field and press Enter to send input
4. Click Stop to terminate the script
5. Click Back to return to the file list

### Viewing Logs

Click the document icon next to a script that has been executed to view its last execution log.

### Autoboot

Click the power icon to set a script as the autoboot script. It will run automatically when the Raspberry Pi starts up. Only one script can be set as autoboot at a time.

## Security Configuration

Edit `/home/pi/pyrunner/config.py` to customize blocked modules and functions.

### Blocked by Default

**Modules:**

- Network: `socket`, `urllib`, `requests`, `http`, etc.
- Database: `sqlite3`, `psycopg2`, `pymongo`, etc.
- Subprocess: `subprocess`, `pexpect`, etc.
- Code execution: `importlib`, `eval`, `exec`, etc.

**Allowed:**

- GPIO: `RPi.GPIO`, `gpiozero`, `pigpio`, `spidev`, `smbus`

### Customizing Blocks

Open `config.py` and comment out any items you want to allow:

```python
BLOCKED_MODULES = [
    'socket',
    # 'threading',  # Uncomment to allow threading
    'subprocess',
    # ...
]
```

## File Structure

```
/home/pi/
├── pyrunner/
│   ├── app.py              # Main Flask application
│   ├── config.py           # Security configuration
│   ├── validator.py        # Python code validator
│   ├── autoboot.txt        # Current autoboot script name
│   ├── autoboot-runner.sh  # Autoboot launcher script
│   ├── logs/               # Execution logs
│   ├── venv/               # Python virtual environment
│   ├── templates/
│   │   └── index.html
│   └── static/
│       ├── css/
│       │   └── style.css
│       └── js/
│           └── app.js
└── pythoncode/             # Your Python scripts
```

## Managing the Service

```bash
# Start
sudo systemctl start pyrunner

# Stop
sudo systemctl stop pyrunner

# Restart
sudo systemctl restart pyrunner

# Check status
sudo systemctl status pyrunner

# View logs
journalctl -u pyrunner -f

# Disable autostart
sudo systemctl disable pyrunner
```

## Troubleshooting

### "Connection: Disconnected" in browser
- Check if the service is running: `sudo systemctl status pyrunner`
- Check for errors: `journalctl -u pyrunner -n 50`

### Script won't run (validation errors)
- Check the error messages displayed
- Edit `config.py` to allow blocked modules if needed
- Ensure all local imports exist in `/home/pi/pythoncode`

### GPIO not working
- Ensure user is in gpio group: `groups pi`
- Add if needed: `sudo usermod -a -G gpio pi`
- Log out and back in for group changes to take effect

### Autoboot script not running
- Check service status: `sudo systemctl status pyrunner-autoboot`
- Check logs: `journalctl -u pyrunner-autoboot`
- Verify script path in `/home/pi/pyrunner/autoboot.txt`

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Main web interface |
| `/api/hostname` | GET | Get device hostname |
| `/api/scripts` | GET | List all scripts with status |
| `/api/scripts/<name>` | GET | Get script details |
| `/api/scripts/<name>` | DELETE | Delete a script |
| `/api/scripts/<name>/log` | GET | Get execution log |
| `/api/scripts/<name>/autoboot` | POST | Set/unset autoboot |
| `/api/upload` | POST | Upload a script |
| `/api/config/blocked` | GET | Get blocked modules list |

## WebSocket Events

| Event | Direction | Description |
|-------|-----------|-------------|
| `start` | Client → Server | Start script execution |
| `stop` | Client → Server | Stop script execution |
| `input` | Client → Server | Send input to script |
| `watch` | Client → Server | Watch running script |
| `started` | Server → Client | Script started |
| `output` | Server → Client | Script output |
| `process_ended` | Server → Client | Script finished |
| `error` | Server → Client | Error occurred |

