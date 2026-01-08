# Python Tree Runner User Guide

Welcome to Python Tree Runner! This guide will help you use the web interface to manage and run Python Tree Python scripts on your Raspberry Pi.

---

## Getting Started

### Opening Python Tree Runner

Open a web browser on any device connected to your network and go to:

```
http://raspberrypi.local
```

If that doesn't work, use your Raspberry Pi's IP address instead:

```
http://192.168.x.x
```

> 💡 **Tip:** You can find your Pi's IP address by running `hostname -I` in the terminal.

---

## Transferring Files with SFTP

Python Tree Runner uses SFTP (SSH File Transfer Protocol) for copying files to your Pi. SFTP is secure, lightweight, and built into SSH.

### Connection Details

| Setting | Value |
|---------|-------|
| Host | `raspberrypi.local` or your Pi's IP address |
| Port | `22` |
| Username | `pi` (or your username) |
| Password | Your SSH password |

### Recommended SFTP Clients

**Mac:**

- Finder: Press Cmd+K → enter `sftp://pi@raspberrypi.local`
- [Cyberduck](https://cyberduck.io) (free)
- [FileZilla](https://filezilla-project.org) (free)
- Command line: `sftp pi@raspberrypi.local`

**Linux:**

- File manager: enter `sftp://pi@raspberrypi.local` in location bar
- Command line: `sftp pi@raspberrypi.local`

**Windows:**

- Windows Explorer: type `sftp://pi@raspberrypi.local` in address bar
- [WinSCP](https://winscp.net) (free, recommended)
- [FileZilla](https://filezilla-project.org) (free)

### Where to Put Python Scripts

Upload your Python scripts to:
```
/home/pi/pythoncode
```

After uploading, refresh the Python Tree Runner web page to see your new scripts.

---

## The Main Screen

When you open the Python Tree Runner, you'll see three main areas:

1. **Header** — Shows the hostname of your Raspberry Pi and connection status
2. **Upload Zone** — Where you add new Python scripts
3. **Scripts List** — Shows all your uploaded scripts

### Connection Status

In the top-right corner, you'll see either:

- 🟢 **Connected** — Everything is working normally
- 🔴 **Disconnected** — The browser has lost connection to the Python Tree Runner (try refreshing the page)

---

## Uploading Scripts

### Method 1: Drag and Drop

1. Find a Python file (`.py`) on your computer
2. Drag it into the upload zone (the dashed box area)
3. Drop it when the box turns green

### Method 2: Click to Select

1. Click anywhere in the upload zone
2. A file picker will open
3. Navigate to your Python file and select it
4. Click "Open"

### What Happens Next

After uploading, Python Tree Runner checks your script for problems. You'll see one of these results:

| Result | What It Means |
|--------|---------------|
| ✅ **Valid** | Your script passed all checks and was saved |
| ⚠️ **Valid with warnings** | Script was saved but needs other files to run |
| ❌ **Invalid** | Script has problems and was not saved |

If there are any issues, they'll be listed so you can fix them.

### Common Upload Issues

| Message | What To Do |
|---------|------------|
| "Only .py files are accepted" | Make sure your file ends in `.py` |
| "Blocked import" | Your script uses a feature that isn't allowed (like internet access) |
| "Missing local imports" | Your script needs another Python file — upload that file too |

---

## The Scripts List

Each script in the list shows:

- **File name** — The name of your Python script
- **File size and date** — When the file was last modified
- **Status badges** — Special labels like "Autoboot" or "Running"

### Script Icons

The icon next to each script tells you its status:

| Icon Colour | Meaning |
|-------------|---------|
| 🟢 Green | Script is valid and ready to run |
| 🟡 Yellow | Script is valid but missing dependencies |
| 🔴 Red | Script has errors and cannot run |

---

## Running Scripts

### Starting a Script

1. Find the script you want to run in the list
2. Click the **Play** button (▶️) next to it

The screen will change to show the running script's output.

### The Execution Screen

When a script is running, you'll see:

- **Script name** — Which script is running
- **Runtime** — How long it's been running (HH:MM:SS)
- **PID** — The process ID (useful for troubleshooting)
- **Terminal** — Shows what your script prints out

### Sending Input to Your Script

If your script asks for input (like `input("Enter your name: ")`):

1. Type your response in the input box at the bottom
2. Press **Enter** to send it

### Stopping a Script

Click the red **Stop** button to terminate the script immediately.

> ⚠️ **Note:** Stopping a script ends it immediately. Any unsaved work in the script will be lost.

### Returning to the Scripts List

Click the **Back** button to return to the main screen. If the script is still running, it will continue in the background.

---

## Managing Running Scripts

### Multiple Scripts

You can run several different scripts at the same time. However, you cannot run the same script twice simultaneously.

### Scripts Running in the Background

If you click **Back** while a script is running:

- The script keeps running
- It appears in the list with a green "Running" badge
- Click the **Arrow** button (➡️) to return to its output

### Stopping a Background Script

From the scripts list, click the **Stop** button (⏹️) next to any running script.

---

## Viewing Logs

Python Tree Runner saves a log of the last time each script was run.

### To View a Log

1. Find the script in the list
2. Click the **Document** button (📄) next to it
3. The log will show the complete output from the last run

### What's in the Log

- Timestamp of when the script ran
- Everything the script printed
- Any error messages

Click the **X** button to close the log and return to the scripts list.

---

## Deleting Scripts

### To Delete a Script

1. Find the script in the list
2. Click the **Bin** button (🗑️) next to it
3. Confirm the deletion when asked

> ⚠️ **Warning:** Deletion is permanent. The script and its log will be removed.

### Scripts That Can't Be Deleted

You cannot delete a script while it's running. Stop it first, then delete it.

---

## Autoboot

Autoboot lets you choose one script to run automatically when your Raspberry Pi starts up.

### Setting an Autoboot Script

1. Find the script you want to run at startup
2. Click the **Power** button (⏻) next to it
3. The script will show an "Autoboot" badge

### Removing Autoboot

Click the **Power** button again on the current autoboot script to disable it.

### Important Notes

- Only one script can be set as autoboot
- Setting a new autoboot script replaces the previous one
- The autoboot script runs independently of Python Tree Runner's web interface

---

## External Processes

Sometimes Python scripts from your scripts folder might be started outside of Python Tree Runner (for example, from the command line or at boot).

### What You'll See

If Python Tree Runner detects these scripts, they appear in a separate "External Processes" section at the bottom of the scripts list.

### Managing External Processes

You can stop external processes by clicking their **Stop** button, but you cannot view their output through Python Tree Runner.

---

## Refreshing the List

Click the **Refresh** button (🔄) in the top-right of the scripts list to:

- Check for new scripts added outside the Python Tree Runner
- Update the status of running scripts
- Detect external processes

The list also refreshes automatically when you upload or delete scripts.

---

## Troubleshooting

### "Disconnected" Status

If the connection status shows "Disconnected":

1. Check that your Raspberry Pi is powered on
2. Check your network connection
3. Try refreshing the page (F5 or Ctrl+R)
4. If it persists, the PyRunner service (a component of the Python Tree Runner) may need restarting

### Script Won't Run

If the Play button isn't showing:

| Problem | Solution |
|---------|----------|
| Script is invalid (red icon) | Check the error message and fix the issues |
| Missing dependencies (yellow icon) | Upload the missing Python files shown in the warning |
| Script is already running | Only one instance can run at a time |

### Script Seems Stuck

If your script appears to hang:

1. Check if it's waiting for input
2. Look at the runtime to see if it's still counting
3. Use the **Stop** button to terminate it
4. Check the log for any error messages

### Can't See Script Output

If the terminal appears blank:

- Your script might not have printed anything yet
- Try adding `print()` statements to your script
- Check that your script doesn't have errors at startup

### Upload Failed

If uploads aren't working:

- Ensure you're uploading a `.py` file
- Check the file isn't too large (limit is 16 MB)
- Try refreshing the page and uploading again

---

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| **Enter** | Send input to running script |
| **F5** | Refresh the page |

---

## Quick Reference

### Button Guide

| Button | Name | What It Does |
|--------|------|--------------|
| ▶️ | Play | Run a script |
| ➡️ | Arrow | View a running script's output |
| ⏹️ | Stop | Terminate a running script |
| 📄 | Document | View last execution log |
| ⏻ | Power | Set/unset as autoboot script |
| 🗑️ | Bin | Delete a script |
| 🔄 | Refresh | Refresh the scripts list |

### Status Badges

| Badge | Meaning |
|-------|---------|
| **Running** | Script is currently executing |
| **Autoboot** | Script runs when Pi starts up |

---

## Getting Help

If you encounter issues not covered in this guide:

1. Check the script logs for error messages
2. Try stopping and restarting the script
3. Refresh the Python Tree Runner page
4. Restart the PyRunner service if necessary

---

*Python Tree Runner — Simple Python script management for Raspberry Pi*
