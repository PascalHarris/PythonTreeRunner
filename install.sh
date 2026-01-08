#!/bin/bash
#
# PyRunner Installation Script
# ============================
# Installs and configures PyRunner on Raspberry Pi (optimized for Pi Zero)
# Uses SFTP for file transfer (built into SSH - lightweight)
# Offers to remove unnecessary packages to free memory and storage
#

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

INSTALL_DIR="/home/pi/pyrunner"
CODE_DIR="/home/pi/pythoncode"
LOG_DIR="/home/pi/pyrunner/logs"
VENV_DIR="/home/pi/pyrunner/venv"
SERVICE_USER="pi"
SERVICE_GROUP="pi"
WEB_PORT=5000
NGINX_PORT=80

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Error collection
declare -a ERRORS=()
declare -a WARNINGS=()

# Detected packages (global arrays to avoid nameref issues)
declare -a DETECTED_GUI=()
declare -a DETECTED_OFFICE=()
declare -a DETECTED_MEDIA=()
declare -a DETECTED_DEV=()
declare -a DETECTED_DOC=()
declare -a DETECTED_SAMBA=()

# User choices
CLEANUP_PACKAGES="N"

# Spinner characters
SPINNER_CHARS='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
SPINNER_PID=""

# ============================================================================
# Unnecessary Packages for Headless Pi Zero
# ============================================================================

GUI_PACKAGES=(
    "raspberrypi-ui-mods"
    "rpd-wallpaper"
    "rpd-icons"
    "rpd-plym-splash"
    "piwiz"
    "pixel-wallpaper"
    "desktop-file-utils"
    "gnome-icon-theme"
    "gnome-themes-extra-data"
    "gtk2-engines"
    "gtk2-engines-pixbuf"
    "lxde"
    "lxde-common"
    "lxde-core"
    "lxappearance"
    "lxinput"
    "lxmenu-data"
    "lxpanel"
    "lxrandr"
    "lxsession"
    "lxsession-edit"
    "lxtask"
    "lxterminal"
    "pcmanfm"
    "openbox"
    "obconf"
    "xarchiver"
    "xcompmgr"
    "xdg-utils"
    "xinit"
    "lightdm"
    "lightdm-gtk-greeter"
    "desktop-base"
    "plymouth"
    "plymouth-themes"
    "pix-icons"
    "pix-plym-splash"
    "zenity"
)

OFFICE_PACKAGES=(
    "geany"
    "geany-common"
    "idle"
    "idle3"
    "thonny"
    "mu-editor"
    "scratch"
    "scratch2"
    "scratch3"
    "sonic-pi"
    "smartsim"
    "penguinspuzzle"
)

MEDIA_PACKAGES=(
    "chromium-browser"
    "chromium-browser-l10n"
    "chromium-codecs-ffmpeg-extra"
    "rpi-chromium-mods"
    "epiphany-browser"
    "epiphany-browser-data"
    "dillo"
    "minecraft-pi"
    "python-minecraftpi"
    "python3-minecraftpi"
    "realvnc-vnc-server"
    "realvnc-vnc-viewer"
    "gpicview"
    "feh"
    "qpdfview"
    "mupdf"
    "gimp"
    "inkscape"
    "ffmpeg"
    "omxplayer"
    "arandr"
    "lxmusic"
    "pulseaudio"
)

DEV_PACKAGES=(
    "code-the-classics"
    "bluej"
    "greenfoot"
    "nodered"
    "nodejs"
    "npm"
    "wolfram-engine"
    "mathematica"
    "claws-mail"
    "cups"
    "cups-bsd"
    "cups-client"
    "cups-common"
    "hplip"
    "system-config-printer"
)

DOC_PACKAGES=(
    "man-db"
    "manpages"
    "manpages-dev"
    "info"
    "doc-debian"
    "libraspberrypi-doc"
)

SAMBA_PACKAGES=(
    "samba"
    "samba-common"
    "samba-common-bin"
    "samba-libs"
    "smbclient"
)

# ============================================================================
# Progress Indicator Functions
# ============================================================================

start_spinner() {
    local message="$1"
    
    if [ ! -t 1 ]; then
        echo -n "  $message... "
        return
    fi
    
    printf "  %s... " "$message"
    
    (
        local i=0
        while true; do
            printf "\b${SPINNER_CHARS:i++%${#SPINNER_CHARS}:1}"
            sleep 0.1
        done
    ) &
    SPINNER_PID=$!
    
    trap 'stop_spinner 2>/dev/null' EXIT
}

stop_spinner() {
    local result="${1:-}"
    
    if [ -n "$SPINNER_PID" ]; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
        SPINNER_PID=""
    fi
    
    printf "\b"
    
    case "$result" in
        ok|OK|0)
            echo -e "${GREEN}OK${NC}"
            ;;
        fail|FAIL|1)
            echo -e "${RED}FAIL${NC}"
            ;;
        warn|WARN)
            echo -e "${YELLOW}WARN${NC}"
            ;;
        skip|SKIP)
            echo -e "${YELLOW}SKIP${NC}"
            ;;
        *)
            echo -e "$result"
            ;;
    esac
}

run_with_spinner() {
    local message="$1"
    shift
    local log_file
    log_file=$(mktemp)
    
    start_spinner "$message"
    
    if "$@" > "$log_file" 2>&1; then
        stop_spinner "OK"
        rm -f "$log_file"
        return 0
    else
        local exit_code=$?
        stop_spinner "FAIL"
        
        if [ -s "$log_file" ]; then
            echo -e "    ${RED}Error output:${NC}"
            head -20 "$log_file" | sed 's/^/    /'
        fi
        
        rm -f "$log_file"
        return $exit_code
    fi
}

show_progress() {
    local current=$1
    local total=$2
    local message="${3:-}"
    local width=40
    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    printf "\r  ["
    printf "%${filled}s" '' | tr ' ' '█'
    printf "%${empty}s" '' | tr ' ' '░'
    printf "] %3d%% %s" "$percent" "$message"
    
    if [ "$current" -eq "$total" ]; then
        echo ""
    fi
}

# ============================================================================
# Helper Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}►${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
    WARNINGS+=("$1")
}

log_error() {
    echo -e "${RED}✗${NC} $1"
    ERRORS+=("$1")
}

log_step() {
    echo -e "\n${GREEN}[$1/$TOTAL_STEPS]${NC} $2"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

package_installed() {
    dpkg -s "$1" >/dev/null 2>&1
}

service_running() {
    systemctl is-active --quiet "$1" 2>/dev/null
}

get_package_size() {
    local pkg="$1"
    local size
    size=$(dpkg-query -W -f='${Installed-Size}' "$pkg" 2>/dev/null || echo "0")
    echo $((size / 1024))
}

apt_install_safe() {
    local packages=("$@")
    
    sync
    echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1 || true
    
    if ! sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        --no-install-recommends \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        "${packages[@]}" 2>&1; then
        return 1
    fi
    
    return 0
}

apt_remove_safe() {
    local packages=("$@")
    
    sync
    echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1 || true
    
    if ! sudo DEBIAN_FRONTEND=noninteractive apt-get remove -y \
        "${packages[@]}" 2>&1; then
        return 1
    fi
    
    return 0
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================================
# System Information Functions
# ============================================================================

get_available_memory_mb() {
    awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo
}

get_available_disk_mb() {
    df -m / | awk 'NR==2 {print $4}'
}

# ============================================================================
# Package Detection Functions
# ============================================================================

# Detect installed packages from a list and add to a global array
detect_packages_in_list() {
    local target_array_name=$1
    shift
    local package_list=("$@")
    
    for pkg in "${package_list[@]}"; do
        if package_installed "$pkg"; then
            eval "${target_array_name}+=(\"\$pkg\")"
        fi
    done
}

# Scan for all bloatware
detect_all_bloatware() {
    # Clear arrays
    DETECTED_GUI=()
    DETECTED_OFFICE=()
    DETECTED_MEDIA=()
    DETECTED_DEV=()
    DETECTED_DOC=()
    DETECTED_SAMBA=()
    
    # Detect each category
    detect_packages_in_list DETECTED_GUI "${GUI_PACKAGES[@]}"
    detect_packages_in_list DETECTED_OFFICE "${OFFICE_PACKAGES[@]}"
    detect_packages_in_list DETECTED_MEDIA "${MEDIA_PACKAGES[@]}"
    detect_packages_in_list DETECTED_DEV "${DEV_PACKAGES[@]}"
    detect_packages_in_list DETECTED_DOC "${DOC_PACKAGES[@]}"
    detect_packages_in_list DETECTED_SAMBA "${SAMBA_PACKAGES[@]}"
}

calculate_package_size() {
    local packages=("$@")
    local total=0
    
    for pkg in "${packages[@]}"; do
        local size
        size=$(get_package_size "$pkg")
        total=$((total + size))
    done
    
    echo $total
}

remove_package_category() {
    local category_name="$1"
    shift
    local packages=("$@")
    
    if [ ${#packages[@]} -eq 0 ]; then
        return 0
    fi
    
    local total_size
    total_size=$(calculate_package_size "${packages[@]}")
    
    echo ""
    echo -e "${YELLOW}Found ${#packages[@]} $category_name packages (~${total_size} MB):${NC}"
    
    local count=0
    for pkg in "${packages[@]}"; do
        printf "  %-35s" "$pkg"
        count=$((count + 1))
        if [ $((count % 2)) -eq 0 ]; then
            echo ""
        fi
    done
    [ $((count % 2)) -ne 0 ] && echo ""
    
    echo ""
    read -p "Remove these $category_name packages? [y/N]: " response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo -e "  Removing packages... ${CYAN}(this may take a while)${NC}"
        
        if apt_remove_safe "${packages[@]}" >/dev/null 2>&1; then
            echo -e "  ${GREEN}OK${NC} - Removed ${#packages[@]} packages (~${total_size} MB freed)"
            return 0
        else
            echo -e "  ${YELLOW}WARN${NC} - Some packages could not be removed"
            return 1
        fi
    else
        echo -e "  ${BLUE}Skipped${NC}"
        return 0
    fi
}

# ============================================================================
# System Optimization
# ============================================================================

run_system_optimization() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}           System Optimization for Pi Zero${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    local mem_available disk_available
    mem_available=$(get_available_memory_mb)
    disk_available=$(get_available_disk_mb)
    
    echo "Current system status:"
    echo -e "  Available memory: ${CYAN}${mem_available} MB${NC}"
    echo -e "  Available disk:   ${CYAN}${disk_available} MB${NC}"
    echo ""
    
    if [ "$mem_available" -lt 200 ]; then
        echo -e "${RED}Warning: Very low memory available!${NC}"
        echo "Removing unnecessary packages is strongly recommended."
        echo ""
    fi
    
    echo "Scanning for unnecessary packages..."
    echo ""
    
    start_spinner "Scanning installed packages"
    detect_all_bloatware
    stop_spinner "OK"
    
    local total_found=$((${#DETECTED_GUI[@]} + ${#DETECTED_OFFICE[@]} + ${#DETECTED_MEDIA[@]} + ${#DETECTED_DEV[@]} + ${#DETECTED_DOC[@]} + ${#DETECTED_SAMBA[@]}))
    
    if [ $total_found -eq 0 ]; then
        echo ""
        echo -e "${GREEN}No unnecessary packages found - system is already optimized!${NC}"
        return 0
    fi
    
    local total_size=0
    [ ${#DETECTED_GUI[@]} -gt 0 ] && total_size=$((total_size + $(calculate_package_size "${DETECTED_GUI[@]}")))
    [ ${#DETECTED_OFFICE[@]} -gt 0 ] && total_size=$((total_size + $(calculate_package_size "${DETECTED_OFFICE[@]}")))
    [ ${#DETECTED_MEDIA[@]} -gt 0 ] && total_size=$((total_size + $(calculate_package_size "${DETECTED_MEDIA[@]}")))
    [ ${#DETECTED_DEV[@]} -gt 0 ] && total_size=$((total_size + $(calculate_package_size "${DETECTED_DEV[@]}")))
    [ ${#DETECTED_DOC[@]} -gt 0 ] && total_size=$((total_size + $(calculate_package_size "${DETECTED_DOC[@]}")))
    [ ${#DETECTED_SAMBA[@]} -gt 0 ] && total_size=$((total_size + $(calculate_package_size "${DETECTED_SAMBA[@]}")))
    
    echo ""
    echo -e "Found ${YELLOW}$total_found${NC} unnecessary packages (~${YELLOW}${total_size} MB${NC} total)"
    echo ""
    echo "Package categories found:"
    [ ${#DETECTED_GUI[@]} -gt 0 ] && echo -e "  • Desktop/GUI:      ${#DETECTED_GUI[@]} packages"
    [ ${#DETECTED_OFFICE[@]} -gt 0 ] && echo -e "  • Office/Education: ${#DETECTED_OFFICE[@]} packages"
    [ ${#DETECTED_MEDIA[@]} -gt 0 ] && echo -e "  • Media/Browsers:   ${#DETECTED_MEDIA[@]} packages"
    [ ${#DETECTED_DEV[@]} -gt 0 ] && echo -e "  • Development:      ${#DETECTED_DEV[@]} packages"
    [ ${#DETECTED_DOC[@]} -gt 0 ] && echo -e "  • Documentation:    ${#DETECTED_DOC[@]} packages"
    [ ${#DETECTED_SAMBA[@]} -gt 0 ] && echo -e "  • Samba (use SFTP): ${#DETECTED_SAMBA[@]} packages"
    echo ""
    
    read -p "Would you like to review and remove unnecessary packages? [Y/n]: " response
    response="${response:-Y}"
    
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Skipping package cleanup${NC}"
        return 0
    fi
    
    # Remove each category with confirmation
    [ ${#DETECTED_GUI[@]} -gt 0 ] && remove_package_category "Desktop/GUI" "${DETECTED_GUI[@]}"
    [ ${#DETECTED_OFFICE[@]} -gt 0 ] && remove_package_category "Office/Education" "${DETECTED_OFFICE[@]}"
    [ ${#DETECTED_MEDIA[@]} -gt 0 ] && remove_package_category "Media/Browser" "${DETECTED_MEDIA[@]}"
    [ ${#DETECTED_DEV[@]} -gt 0 ] && remove_package_category "Development" "${DETECTED_DEV[@]}"
    [ ${#DETECTED_DOC[@]} -gt 0 ] && remove_package_category "Documentation" "${DETECTED_DOC[@]}"
    
    # Samba removal with explanation
    if [ ${#DETECTED_SAMBA[@]} -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}Found Samba file sharing installed${NC}"
        echo ""
        echo "Samba is memory-intensive and unnecessary on Pi Zero."
        echo "This script uses SFTP instead, which is:"
        echo "  • Built into SSH (already installed)"
        echo "  • Zero additional memory usage"
        echo "  • More secure (encrypted)"
        echo "  • Works with FileZilla, WinSCP, Cyberduck, etc."
        echo ""
        
        local samba_size
        samba_size=$(calculate_package_size "${DETECTED_SAMBA[@]}")
        echo -e "Samba packages (~${samba_size} MB): ${DETECTED_SAMBA[*]}"
        echo ""
        read -p "Remove Samba packages? [Y/n]: " response
        response="${response:-Y}"
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            echo -e "  Removing Samba... ${CYAN}(this may take a moment)${NC}"
            
            sudo systemctl stop smbd 2>/dev/null || true
            sudo systemctl stop nmbd 2>/dev/null || true
            sudo systemctl disable smbd 2>/dev/null || true
            sudo systemctl disable nmbd 2>/dev/null || true
            
            if apt_remove_safe "${DETECTED_SAMBA[@]}" >/dev/null 2>&1; then
                echo -e "  ${GREEN}OK${NC} - Samba removed (~${samba_size} MB freed)"
            else
                echo -e "  ${YELLOW}WARN${NC} - Some Samba packages could not be removed"
            fi
        else
            echo -e "  ${BLUE}Skipped${NC}"
        fi
    fi
    
    # Clean up after removal
    echo ""
    start_spinner "Removing unused dependencies"
    sudo apt-get autoremove -y >/dev/null 2>&1 || true
    stop_spinner "OK"
    
    start_spinner "Cleaning package cache"
    sudo apt-get clean >/dev/null 2>&1 || true
    stop_spinner "OK"
    
    local new_mem new_disk
    new_mem=$(get_available_memory_mb)
    new_disk=$(get_available_disk_mb)
    
    echo ""
    echo "Updated system status:"
    echo -e "  Available memory: ${GREEN}${new_mem} MB${NC} (was ${mem_available} MB)"
    echo -e "  Available disk:   ${GREEN}${new_disk} MB${NC} (was ${disk_available} MB)"
    
    local disk_saved=$((new_disk - disk_available))
    
    if [ $disk_saved -gt 0 ]; then
        echo ""
        echo -e "${GREEN}Freed approximately ${disk_saved} MB of disk space${NC}"
    fi
}

# ============================================================================
# SFTP Configuration
# ============================================================================

configure_sftp() {
    echo ""
    echo -e "${BLUE}Configuring SFTP file access...${NC}"
    
    start_spinner "Checking SSH service"
    if service_running sshd || service_running ssh; then
        stop_spinner "OK"
        log_success "SSH/SFTP is already running"
    else
        stop_spinner "WARN"
        
        start_spinner "Enabling SSH service"
        if sudo systemctl enable ssh 2>/dev/null && sudo systemctl start ssh 2>/dev/null; then
            stop_spinner "OK"
            log_success "SSH/SFTP enabled and started"
        else
            stop_spinner "FAIL"
            log_warning "Could not start SSH. SFTP may not be available."
            return 1
        fi
    fi
    
    start_spinner "Verifying SFTP subsystem"
    if grep -q "Subsystem.*sftp" /etc/ssh/sshd_config 2>/dev/null; then
        stop_spinner "OK"
    else
        echo "Subsystem sftp /usr/lib/openssh/sftp-server" | sudo tee -a /etc/ssh/sshd_config >/dev/null
        sudo systemctl restart ssh 2>/dev/null || sudo systemctl restart sshd 2>/dev/null || true
        stop_spinner "OK"
    fi
    
    log_success "SFTP file access configured"
}

# ============================================================================
# Nginx Configuration
# ============================================================================

configure_nginx() {
    log_step 9 "Configuring nginx web server"
    
    # Check if nginx is installed
    if ! package_installed "nginx-light" && ! package_installed "nginx"; then
        log_info "Installing nginx-light (minimal nginx for Pi Zero)..."
        
        if ! run_with_spinner "Updating package lists" sudo apt-get update -qq; then
            log_warning "Failed to update apt"
        fi
        
        echo -e "  Installing nginx-light... ${CYAN}(this may take a minute)${NC}"
        if apt_install_safe nginx-light; then
            echo -e "  ${GREEN}OK${NC}"
        else
            echo -e "  ${YELLOW}WARN${NC} - Trying full nginx package..."
            if apt_install_safe nginx; then
                echo -e "  ${GREEN}OK${NC}"
            else
                echo -e "  ${RED}FAIL${NC}"
                log_warning "Could not install nginx. PyRunner will run without reverse proxy."
                return 1
            fi
        fi
    else
        echo -e "  ${GREEN}✓${NC} nginx is already installed"
    fi
    
    # Create nginx configuration for PyRunner
    start_spinner "Creating nginx configuration"
    
    local nginx_conf="/etc/nginx/sites-available/pyrunner"
    
    sudo tee "$nginx_conf" > /dev/null << EOF
# PyRunner nginx configuration
# Reverse proxy with WebSocket support

upstream pyrunner_backend {
    server 127.0.0.1:5000;
    keepalive 32;
}

server {
    listen ${NGINX_PORT} default_server;
    listen [::]:${NGINX_PORT} default_server;
    
    server_name _;
    
    # Logging (minimal for Pi Zero)
    access_log off;
    error_log /var/log/nginx/pyrunner_error.log error;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    
    # Gzip compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml;
    gzip_min_length 256;
    
    # Static files - served directly by nginx (more efficient)
    location /static/ {
        alias ${INSTALL_DIR}/static/;
        expires 1d;
        add_header Cache-Control "public, immutable";
    }
    
    # WebSocket support for Socket.IO
    location /socket.io/ {
        proxy_pass http://pyrunner_backend/socket.io/;
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket timeouts
        proxy_connect_timeout 7d;
        proxy_send_timeout 7d;
        proxy_read_timeout 7d;
    }
    
    # All other requests to Flask
    location / {
        proxy_pass http://pyrunner_backend;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Connection "";
        
        # Timeouts for long-running requests
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffering settings
        proxy_buffering off;
        proxy_request_buffering off;
        
        # Max upload size
        client_max_body_size 16M;
    }
}
EOF
    stop_spinner "OK"
    
    # Enable the site
    start_spinner "Enabling PyRunner site"
    
    # Remove default site if it exists
    if [ -L /etc/nginx/sites-enabled/default ]; then
        sudo rm -f /etc/nginx/sites-enabled/default
    fi
    
    # Create symlink for our site
    if [ ! -L /etc/nginx/sites-enabled/pyrunner ]; then
        sudo ln -sf "$nginx_conf" /etc/nginx/sites-enabled/pyrunner
    fi
    stop_spinner "OK"
    
    # Test nginx configuration
    start_spinner "Testing nginx configuration"
    if sudo nginx -t 2>/dev/null; then
        stop_spinner "OK"
    else
        stop_spinner "FAIL"
        log_error "nginx configuration test failed"
        sudo nginx -t
        return 1
    fi
    
    # Restart nginx
    if ! run_with_spinner "Restarting nginx" sudo systemctl restart nginx; then
        log_error "Failed to restart nginx"
        return 1
    fi
    
    # Enable nginx at boot
    start_spinner "Enabling nginx at boot"
    sudo systemctl enable nginx >/dev/null 2>&1
    stop_spinner "OK"
    
    log_success "nginx configured as reverse proxy"
}

show_sftp_instructions() {
    local hostname ip
    hostname=$(hostname)
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}           SFTP File Access Instructions${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Connect using any SFTP client with your SSH credentials:"
    echo ""
    echo -e "  Host:     ${GREEN}${hostname}.local${NC} or ${GREEN}${ip}${NC}"
    echo -e "  Port:     ${GREEN}22${NC}"
    echo -e "  Username: ${GREEN}${SERVICE_USER}${NC}"
    echo -e "  Password: ${GREEN}(your SSH password)${NC}"
    echo ""
    echo -e "${BLUE}Recommended SFTP Clients:${NC}"
    echo ""
    echo -e "  ${CYAN}Windows:${NC}"
    echo "    • WinSCP (free): https://winscp.net"
    echo "    • FileZilla (free): https://filezilla-project.org"
    echo "    • Windows Explorer: type  sftp://${SERVICE_USER}@${ip}  in address bar"
    echo ""
    echo -e "  ${CYAN}Mac:${NC}"
    echo "    • Finder: Cmd+K → sftp://${SERVICE_USER}@${hostname}.local"
    echo "    • Cyberduck (free): https://cyberduck.io"
    echo "    • FileZilla (free): https://filezilla-project.org"
    echo ""
    echo -e "  ${CYAN}Linux:${NC}"
    echo "    • File manager: sftp://${SERVICE_USER}@${hostname}.local"
    echo "    • Command line: sftp ${SERVICE_USER}@${hostname}.local"
    echo ""
    echo -e "${BLUE}Python Scripts Location:${NC}"
    echo -e "  ${GREEN}${CODE_DIR}${NC}"
    echo ""
}

# ============================================================================
# Initial Setup (runs before file check)
# ============================================================================

initial_setup() {
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}       PyRunner Installation Script (Pi Zero Optimized)${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Basic checks
    if [ "$EUID" -eq 0 ]; then
        echo -e "${RED}✗${NC} Do not run this script as root. Run as '$SERVICE_USER' user."
        exit 1
    fi
    
    if ! id "$SERVICE_USER" >/dev/null 2>&1; then
        echo -e "${RED}✗${NC} User '$SERVICE_USER' does not exist."
        exit 1
    fi
    
    if [ "$(whoami)" != "$SERVICE_USER" ]; then
        echo -e "${YELLOW}⚠${NC} Running as '$(whoami)' but service will run as '$SERVICE_USER'."
    fi
    
    if ! sudo -n true 2>/dev/null; then
        echo -e "${YELLOW}This script requires sudo access for some operations.${NC}"
        echo "Please enter your password if prompted."
        if ! sudo true; then
            echo -e "${RED}✗${NC} Could not obtain sudo access."
            exit 1
        fi
    fi
    
    echo -e "${GREEN}✓${NC} Basic checks passed"
    echo ""
    
    # Step 1: Offer system optimization
    echo -e "${BLUE}────────────────────────────────────────────────────────────${NC}"
    echo -e "${BLUE}Step 1: System Optimization${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────────────${NC}"
    echo ""
    echo "The Pi Zero has limited memory and storage. This script can remove"
    echo "unnecessary packages (GUI, office apps, games, Samba, etc.)"
    echo ""
    
    read -p "Check for and offer to remove unnecessary packages? [Y/n]: " CLEANUP_PACKAGES
    CLEANUP_PACKAGES="${CLEANUP_PACKAGES:-Y}"
    
    if [[ "$CLEANUP_PACKAGES" =~ ^[Yy]$ ]]; then
        run_system_optimization
    else
        echo -e "${BLUE}Skipping system optimization${NC}"
    fi
    
    # Step 2: Configure SFTP
    echo ""
    echo -e "${BLUE}────────────────────────────────────────────────────────────${NC}"
    echo -e "${BLUE}Step 2: File Transfer Setup (SFTP)${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────────────${NC}"
    echo ""
    echo "SFTP is built into SSH and requires no additional software."
    echo "Verifying SFTP is available..."
    
    configure_sftp
}

# ============================================================================
# Check Required Files
# ============================================================================

check_required_files() {
    echo ""
    echo -e "${BLUE}────────────────────────────────────────────────────────────${NC}"
    echo -e "${BLUE}Step 3: Check Installation Files${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────────────${NC}"
    echo ""
    
    local missing_files=()
    local required_files=("app.py" "config.py" "validator.py" "templates/index.html" "static/css/style.css" "static/js/app.js" "systemd/pyrunner.service" "autoboot-runner.sh")
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$SCRIPT_DIR/$file" ]; then
            missing_files+=("$file")
        fi
    done
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        echo -e "${YELLOW}The following required files are missing:${NC}"
        for file in "${missing_files[@]}"; do
            echo -e "  ${RED}✗${NC} $file"
        done
        echo ""
        echo "Use SFTP to copy the remaining PyRunner files to:"
        echo -e "  ${GREEN}${SCRIPT_DIR}${NC}"
        echo ""
        show_sftp_instructions
        echo ""
        echo "After copying all files, run this script again:"
        echo -e "  ${GREEN}cd ${SCRIPT_DIR} && ./install.sh${NC}"
        echo ""
        exit 1
    fi
    
    echo -e "${GREEN}✓${NC} All required files found"
}

# ============================================================================
# User Questions (for full installation)
# ============================================================================

ask_questions() {
    echo ""
    echo -e "${BLUE}────────────────────────────────────────────────────────────${NC}"
    echo -e "${BLUE}Step 4: Configuration${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────────────${NC}"
    echo ""
    
    read -p "Installation directory [$INSTALL_DIR]: " input
    INSTALL_DIR="${input:-$INSTALL_DIR}"
    
    read -p "Python scripts directory [$CODE_DIR]: " input
    CODE_DIR="${input:-$CODE_DIR}"
    
    echo ""
    echo "PyRunner uses nginx as a reverse proxy for better performance."
    echo "nginx listens on port 80 (public) and forwards to Flask on port 5000 (internal)."
    echo ""
    
    read -p "nginx public port [$NGINX_PORT]: " input
    NGINX_PORT="${input:-$NGINX_PORT}"
    
    if ! [[ "$NGINX_PORT" =~ ^[0-9]+$ ]] || [ "$NGINX_PORT" -lt 1 ] || [ "$NGINX_PORT" -gt 65535 ]; then
        log_error "Invalid port number: $NGINX_PORT"
        exit 1
    fi
    
    read -p "Flask internal port [$WEB_PORT]: " input
    WEB_PORT="${input:-$WEB_PORT}"
    
    if ! [[ "$WEB_PORT" =~ ^[0-9]+$ ]] || [ "$WEB_PORT" -lt 1 ] || [ "$WEB_PORT" -gt 65535 ]; then
        log_error "Invalid port number: $WEB_PORT"
        exit 1
    fi
    
    if [ "$NGINX_PORT" -eq "$WEB_PORT" ]; then
        log_error "nginx port and Flask port cannot be the same"
        exit 1
    fi
    
    read -p "Start PyRunner after installation? [Y/n]: " START_AFTER
    START_AFTER="${START_AFTER:-Y}"
    
    read -p "Enable PyRunner at system boot? [Y/n]: " ENABLE_BOOT
    ENABLE_BOOT="${ENABLE_BOOT:-Y}"
    
    LOG_DIR="$INSTALL_DIR/logs"
    VENV_DIR="$INSTALL_DIR/venv"
    
    echo ""
    echo -e "${BLUE}────────────────────────────────────────────────────────────${NC}"
    echo "Configuration Summary:"
    echo "  Install directory:   $INSTALL_DIR"
    echo "  Scripts directory:   $CODE_DIR"
    echo "  nginx port:          $NGINX_PORT (public)"
    echo "  Flask port:          $WEB_PORT (internal)"
    echo "  Start after install: $START_AFTER"
    echo "  Enable at boot:      $ENABLE_BOOT"
    echo "  File transfer:       SFTP (via SSH)"
    echo -e "${BLUE}────────────────────────────────────────────────────────────${NC}"
    echo ""
    
    read -p "Proceed with installation? [Y/n]: " CONFIRM
    CONFIRM="${CONFIRM:-Y}"
    
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
    
    echo ""
    echo -e "${GREEN}Starting installation...${NC}"
    echo ""
}

# ============================================================================
# Installation Steps
# ============================================================================

TOTAL_STEPS=10

install_system_deps() {
    log_step 1 "Checking system dependencies"
    
    local packages_to_install=()
    
    local required_packages=(
        "python3"
        "python3-pip"
        "python3-venv"
    )
    
    local dev_packages=(
        "python3-dev"
        "libffi-dev"
    )
    
    local total_checks=${#required_packages[@]}
    local current=0
    
    for pkg in "${required_packages[@]}"; do
        current=$((current + 1))
        show_progress $current $total_checks "Checking $pkg"
        if ! package_installed "$pkg"; then
            packages_to_install+=("$pkg")
        fi
    done
    
    for pkg in "${dev_packages[@]}"; do
        if ! package_installed "$pkg"; then
            packages_to_install+=("$pkg")
        fi
    done
    
    if ! package_installed "python3-gpiozero"; then
        if apt-cache show "python3-gpiozero" >/dev/null 2>&1; then
            packages_to_install+=("python3-gpiozero")
        fi
    fi
    
    if [ ${#packages_to_install[@]} -gt 0 ]; then
        echo ""
        log_info "Need to install: ${packages_to_install[*]}"
        
        if ! run_with_spinner "Updating package lists" sudo apt-get update -qq; then
            log_error "Failed to update apt"
            return 1
        fi
        
        echo -e "  Installing packages... ${CYAN}(this may take a few minutes)${NC}"
        if ! apt_install_safe "${packages_to_install[@]}"; then
            echo -e "  ${RED}FAIL${NC}"
            log_error "Failed to install system packages"
            return 1
        fi
        echo -e "  ${GREEN}OK${NC}"
        
        log_success "System packages installed"
    else
        log_success "All system packages already installed"
    fi
}

verify_python() {
    log_step 2 "Verifying Python installation"
    
    start_spinner "Checking Python version"
    
    if ! command_exists python3; then
        stop_spinner "FAIL"
        log_error "Python 3 is not installed"
        return 1
    fi
    
    local python_version
    python_version=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    
    local major minor
    major=$(echo "$python_version" | cut -d. -f1)
    minor=$(echo "$python_version" | cut -d. -f2)
    
    if [ "$major" -lt 3 ] || ([ "$major" -eq 3 ] && [ "$minor" -lt 7 ]); then
        stop_spinner "FAIL"
        log_error "Python 3.7+ required, found $python_version"
        return 1
    fi
    
    stop_spinner "OK"
    log_success "Python $python_version detected"
}

create_directories() {
    log_step 3 "Creating directories"
    
    local dirs=("$INSTALL_DIR" "$CODE_DIR" "$LOG_DIR" "$INSTALL_DIR/templates" "$INSTALL_DIR/static/css" "$INSTALL_DIR/static/js" "$INSTALL_DIR/systemd")
    local total=${#dirs[@]}
    local current=0
    
    for dir in "${dirs[@]}"; do
        current=$((current + 1))
        show_progress $current $total "$dir"
        if [ ! -d "$dir" ]; then
            if ! mkdir -p "$dir" 2>/dev/null; then
                if ! sudo mkdir -p "$dir"; then
                    echo ""
                    log_error "Failed to create directory: $dir"
                    return 1
                fi
                sudo chown "$SERVICE_USER:$SERVICE_GROUP" "$dir"
            fi
        fi
    done
    
    log_success "Directories created"
}

create_venv() {
    log_step 4 "Setting up Python virtual environment"
    
    if [ -d "$VENV_DIR" ]; then
        if [ ! -f "$VENV_DIR/bin/python" ]; then
            start_spinner "Removing corrupted virtual environment"
            rm -rf "$VENV_DIR"
            stop_spinner "OK"
        fi
    fi
    
    if [ ! -d "$VENV_DIR" ]; then
        if ! run_with_spinner "Creating virtual environment" python3 -m venv "$VENV_DIR"; then
            log_error "Failed to create virtual environment"
            return 1
        fi
    else
        echo -e "  ${GREEN}✓${NC} Virtual environment already exists"
    fi
    
    start_spinner "Verifying virtual environment"
    if ! "$VENV_DIR/bin/python" -c "import sys; sys.exit(0)" 2>/dev/null; then
        stop_spinner "FAIL"
        log_error "Virtual environment is not functional"
        return 1
    fi
    stop_spinner "OK"
    
    log_success "Virtual environment ready"
}

install_python_packages() {
    log_step 5 "Installing Python packages"
    
    if ! run_with_spinner "Upgrading pip" "$VENV_DIR/bin/pip" install --quiet --upgrade pip; then
        log_error "Failed to upgrade pip"
        return 1
    fi
    
    # Core packages - order matters for compatibility
    local packages=("eventlet" "dnspython" "flask" "python-socketio" "flask-socketio")
    local total=${#packages[@]}
    local current=0
    
    for pkg in "${packages[@]}"; do
        current=$((current + 1))
        if ! "$VENV_DIR/bin/pip" show "$pkg" >/dev/null 2>&1; then
            if ! run_with_spinner "Installing $pkg ($current/$total)" "$VENV_DIR/bin/pip" install --quiet "$pkg"; then
                log_error "Failed to install $pkg"
                return 1
            fi
        else
            show_progress $current $total "$pkg (already installed)"
        fi
    done
    
    for pkg in "RPi.GPIO" "gpiozero"; do
        if ! "$VENV_DIR/bin/pip" show "$pkg" >/dev/null 2>&1; then
            start_spinner "Installing $pkg (optional)"
            if "$VENV_DIR/bin/pip" install --quiet "$pkg" 2>/dev/null; then
                stop_spinner "OK"
            else
                stop_spinner "SKIP"
            fi
        fi
    done
    
    log_success "Python packages installed"
}

copy_application() {
    log_step 6 "Installing application files"
    
    local files=(
        "app.py"
        "config.py"
        "validator.py"
        "templates/index.html"
        "static/css/style.css"
        "static/js/app.js"
        "autoboot-runner.sh"
    )
    
    local total=${#files[@]}
    local current=0
    
    for file in "${files[@]}"; do
        current=$((current + 1))
        show_progress $current $total "$file"
        
        local dest="$INSTALL_DIR/$file"
        local dest_dir
        dest_dir=$(dirname "$dest")
        
        mkdir -p "$dest_dir" 2>/dev/null || true
        cp "$SCRIPT_DIR/$file" "$dest"
    done
    
    chmod +x "$INSTALL_DIR/autoboot-runner.sh"
    
    if [ "$CODE_DIR" != "/home/pi/pythoncode" ] || [ "$LOG_DIR" != "/home/pi/pyrunner/logs" ]; then
        start_spinner "Updating configuration paths"
        sed -i "s|CODE_DIR = Path('/home/pi/pythoncode')|CODE_DIR = Path('$CODE_DIR')|g" "$INSTALL_DIR/config.py"
        sed -i "s|LOG_DIR = Path('/home/pi/pyrunner/logs')|LOG_DIR = Path('$LOG_DIR')|g" "$INSTALL_DIR/config.py"
        sed -i "s|AUTOBOOT_FILE = Path('/home/pi/pyrunner/autoboot.txt')|AUTOBOOT_FILE = Path('$INSTALL_DIR/autoboot.txt')|g" "$INSTALL_DIR/config.py"
        stop_spinner "OK"
    fi
    
    start_spinner "Configuring autoboot script"
    sed -i "s|/home/pi/pyrunner|$INSTALL_DIR|g" "$INSTALL_DIR/autoboot-runner.sh"
    sed -i "s|/home/pi/pythoncode|$CODE_DIR|g" "$INSTALL_DIR/autoboot-runner.sh"
    stop_spinner "OK"
    
    log_success "Application files installed"
}

configure_systemd() {
    log_step 7 "Configuring systemd services"
    
    start_spinner "Creating service files"
    cat > "$INSTALL_DIR/systemd/pyrunner.service" << EOF
[Unit]
Description=PyRunner - Python Script Manager
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$VENV_DIR/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=$VENV_DIR/bin/python $INSTALL_DIR/app.py
Restart=always
RestartSec=5
SupplementaryGroups=gpio i2c spi

[Install]
WantedBy=multi-user.target
EOF

    cat > "$INSTALL_DIR/systemd/pyrunner-autoboot.service" << EOF
[Unit]
Description=PyRunner Autoboot Script
After=network.target pyrunner.service
Wants=pyrunner.service

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
WorkingDirectory=$CODE_DIR
Environment="PATH=$VENV_DIR/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="PYTHONUNBUFFERED=1"
ExecStart=$INSTALL_DIR/autoboot-runner.sh
Restart=no
SupplementaryGroups=gpio i2c spi

[Install]
WantedBy=multi-user.target
EOF
    stop_spinner "OK"

    if [ "$WEB_PORT" != "5000" ]; then
        start_spinner "Configuring web port"
        sed -i "s|port=5000|port=$WEB_PORT|g" "$INSTALL_DIR/app.py"
        stop_spinner "OK"
    fi

    if ! run_with_spinner "Installing pyrunner.service" sudo cp "$INSTALL_DIR/systemd/pyrunner.service" /etc/systemd/system/; then
        log_error "Failed to install pyrunner.service"
        return 1
    fi
    
    if ! run_with_spinner "Installing pyrunner-autoboot.service" sudo cp "$INSTALL_DIR/systemd/pyrunner-autoboot.service" /etc/systemd/system/; then
        log_error "Failed to install pyrunner-autoboot.service"
        return 1
    fi
    
    if ! run_with_spinner "Reloading systemd" sudo systemctl daemon-reload; then
        log_error "Failed to reload systemd"
        return 1
    fi
    
    # Set permissions
    start_spinner "Setting ownership of $INSTALL_DIR"
    sudo chown -R "$SERVICE_USER:$SERVICE_GROUP" "$INSTALL_DIR"
    stop_spinner "OK"
    
    start_spinner "Setting ownership of $CODE_DIR"
    sudo chown -R "$SERVICE_USER:$SERVICE_GROUP" "$CODE_DIR"
    stop_spinner "OK"
    
    # Make home directory traversable for nginx (www-data user)
    # This allows nginx to serve static files from /home/pi/pyrunner/static/
    start_spinner "Making home directory traversable for nginx"
    chmod 711 "/home/$SERVICE_USER"
    stop_spinner "OK"
    
    local groups=("gpio" "i2c" "spi")
    for group in "${groups[@]}"; do
        if getent group "$group" >/dev/null 2>&1; then
            start_spinner "Adding $SERVICE_USER to $group group"
            sudo usermod -a -G "$group" "$SERVICE_USER" 2>/dev/null || true
            stop_spinner "OK"
        fi
    done
    
    log_success "Systemd services configured"
}

manage_services() {
    log_step 10 "Managing services"
    
    start_spinner "Stopping existing services"
    sudo systemctl stop pyrunner.service 2>/dev/null || true
    sudo systemctl stop pyrunner-autoboot.service 2>/dev/null || true
    stop_spinner "OK"
    
    if [[ "$ENABLE_BOOT" =~ ^[Yy]$ ]]; then
        if ! run_with_spinner "Enabling pyrunner at boot" sudo systemctl enable pyrunner.service; then
            log_error "Failed to enable pyrunner service"
            return 1
        fi
        if ! run_with_spinner "Enabling autoboot service" sudo systemctl enable pyrunner-autoboot.service; then
            log_error "Failed to enable autoboot service"
            return 1
        fi
        log_success "Services enabled for boot"
    else
        start_spinner "Disabling services at boot"
        sudo systemctl disable pyrunner.service 2>/dev/null || true
        sudo systemctl disable pyrunner-autoboot.service 2>/dev/null || true
        stop_spinner "OK"
        log_info "Services not enabled for boot"
    fi
    
    if [[ "$START_AFTER" =~ ^[Yy]$ ]]; then
        if ! run_with_spinner "Starting pyrunner service" sudo systemctl start pyrunner.service; then
            log_error "Failed to start pyrunner service"
            echo "  Checking service logs..."
            sudo journalctl -u pyrunner.service -n 10 --no-pager | sed 's/^/    /'
            return 1
        fi
        
        start_spinner "Waiting for service to start"
        sleep 3
        
        if service_running pyrunner.service; then
            stop_spinner "OK"
            log_success "PyRunner service started"
        else
            stop_spinner "FAIL"
            log_error "PyRunner service failed to start"
            sudo journalctl -u pyrunner.service -n 10 --no-pager | sed 's/^/    /'
            return 1
        fi
    else
        log_info "Service not started (as requested)"
    fi
}

run_smoke_tests() {
    echo ""
    echo -e "${BLUE}Running smoke tests...${NC}"
    
    local tests_passed=0
    local tests_failed=0
    
    start_spinner "Checking Python imports"
    if "$VENV_DIR/bin/python" -c "import flask; import flask_socketio; import eventlet" 2>/dev/null; then
        stop_spinner "OK"
        tests_passed=$((tests_passed + 1))
    else
        stop_spinner "FAIL"
        tests_failed=$((tests_failed + 1))
        ERRORS+=("Python import test failed")
    fi
    
    start_spinner "Checking validator module"
    if "$VENV_DIR/bin/python" -c "import sys; sys.path.insert(0, '$INSTALL_DIR'); import validator" 2>/dev/null; then
        stop_spinner "OK"
        tests_passed=$((tests_passed + 1))
    else
        stop_spinner "FAIL"
        tests_failed=$((tests_failed + 1))
        ERRORS+=("Validator module test failed")
    fi
    
    start_spinner "Checking config module"
    if "$VENV_DIR/bin/python" -c "import sys; sys.path.insert(0, '$INSTALL_DIR'); import config" 2>/dev/null; then
        stop_spinner "OK"
        tests_passed=$((tests_passed + 1))
    else
        stop_spinner "FAIL"
        tests_failed=$((tests_failed + 1))
        ERRORS+=("Config module test failed")
    fi
    
    start_spinner "Checking directory permissions"
    if touch "$CODE_DIR/.write_test" 2>/dev/null && rm "$CODE_DIR/.write_test" && \
       touch "$LOG_DIR/.write_test" 2>/dev/null && rm "$LOG_DIR/.write_test"; then
        stop_spinner "OK"
        tests_passed=$((tests_passed + 1))
    else
        stop_spinner "FAIL"
        tests_failed=$((tests_failed + 1))
        ERRORS+=("Directory permission test failed")
    fi
    
    start_spinner "Checking SSH/SFTP service"
    if service_running sshd || service_running ssh; then
        stop_spinner "OK"
        tests_passed=$((tests_passed + 1))
    else
        stop_spinner "FAIL"
        tests_failed=$((tests_failed + 1))
        ERRORS+=("SSH/SFTP service not running")
    fi
    
    start_spinner "Checking nginx service"
    if service_running nginx; then
        stop_spinner "OK"
        tests_passed=$((tests_passed + 1))
    else
        stop_spinner "WARN"
        WARNINGS+=("nginx not running - using direct Flask access")
    fi
    
    if [[ "$START_AFTER" =~ ^[Yy]$ ]] && service_running pyrunner.service; then
        start_spinner "Waiting for web server"
        sleep 2
        stop_spinner "OK"
        
        # Test via nginx first
        if service_running nginx; then
            start_spinner "Checking nginx proxy response"
            if command_exists curl; then
                if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$NGINX_PORT/" 2>/dev/null | grep -q "200"; then
                    stop_spinner "OK"
                    tests_passed=$((tests_passed + 1))
                else
                    stop_spinner "FAIL"
                    tests_failed=$((tests_failed + 1))
                    ERRORS+=("nginx not responding on port $NGINX_PORT")
                fi
            else
                stop_spinner "SKIP"
            fi
        fi
        
        start_spinner "Checking Flask backend response"
        if command_exists curl; then
            if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$WEB_PORT/" 2>/dev/null | grep -q "200"; then
                stop_spinner "OK"
                tests_passed=$((tests_passed + 1))
            else
                stop_spinner "FAIL"
                tests_failed=$((tests_failed + 1))
                ERRORS+=("Flask not responding on port $WEB_PORT")
            fi
        elif command_exists wget; then
            if wget -q --spider "http://localhost:$WEB_PORT/" 2>/dev/null; then
                stop_spinner "OK"
                tests_passed=$((tests_passed + 1))
            else
                stop_spinner "FAIL"
                tests_failed=$((tests_failed + 1))
                ERRORS+=("Flask not responding on port $WEB_PORT")
            fi
        else
            stop_spinner "SKIP"
        fi
        
        start_spinner "Checking API endpoint"
        if command_exists curl; then
            local api_response
            api_response=$(curl -s "http://localhost:$NGINX_PORT/api/hostname" 2>/dev/null || curl -s "http://localhost:$WEB_PORT/api/hostname" 2>/dev/null)
            if echo "$api_response" | grep -q "hostname"; then
                stop_spinner "OK"
                tests_passed=$((tests_passed + 1))
            else
                stop_spinner "FAIL"
                tests_failed=$((tests_failed + 1))
                ERRORS+=("API endpoint not responding correctly")
            fi
        else
            stop_spinner "SKIP"
        fi
    fi
    
    echo ""
    echo -e "  Tests passed: ${GREEN}$tests_passed${NC}"
    [ $tests_failed -gt 0 ] && echo -e "  Tests failed: ${RED}$tests_failed${NC}"
    
    return $tests_failed
}

# ============================================================================
# Main
# ============================================================================

main() {
    # Phase 1: Initial setup (optimization + SFTP) - always runs
    initial_setup
    
    # Phase 2: Check for required files
    check_required_files
    
    # Phase 3: Get configuration
    ask_questions
    
    # Phase 4: Install PyRunner
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}           Installing PyRunner${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    
    install_system_deps || true
    verify_python || { log_error "Python verification failed"; exit 1; }
    create_directories || { log_error "Directory creation failed"; exit 1; }
    create_venv || { log_error "Virtual environment creation failed"; exit 1; }
    install_python_packages || { log_error "Python package installation failed"; exit 1; }
    copy_application || { log_error "Application copy failed"; exit 1; }
    configure_systemd || { log_error "Systemd configuration failed"; exit 1; }
    configure_nginx || log_warning "nginx configuration failed - PyRunner will still work on port $WEB_PORT"
    manage_services || true
    
    run_smoke_tests
    local test_result=$?
    
    # ========================================================================
    # Summary
    # ========================================================================
    
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    
    if [ ${#ERRORS[@]} -eq 0 ] && [ $test_result -eq 0 ]; then
        echo -e "${GREEN}Installation completed successfully!${NC}"
    else
        echo -e "${YELLOW}Installation completed with issues${NC}"
    fi
    
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    local mem_available disk_available
    mem_available=$(get_available_memory_mb)
    disk_available=$(get_available_disk_mb)
    
    echo "System status:"
    echo -e "  Available memory: ${CYAN}${mem_available} MB${NC}"
    echo -e "  Available disk:   ${CYAN}${disk_available} MB${NC}"
    echo ""
    
    if [ ${#WARNINGS[@]} -gt 0 ]; then
        echo -e "${YELLOW}Warnings:${NC}"
        for warning in "${WARNINGS[@]}"; do
            echo -e "  ${YELLOW}⚠${NC} $warning"
        done
        echo ""
    fi
    
    if [ ${#ERRORS[@]} -gt 0 ]; then
        echo -e "${RED}Errors:${NC}"
        for error in "${ERRORS[@]}"; do
            echo -e "  ${RED}✗${NC} $error"
        done
        echo ""
    fi
    
    local hostname ip
    hostname=$(hostname)
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    
    if service_running pyrunner.service 2>/dev/null; then
        echo "Access PyRunner at:"
        if service_running nginx 2>/dev/null; then
            if [ "$NGINX_PORT" -eq 80 ]; then
                echo -e "  ${GREEN}http://${hostname}.local${NC}"
                [ -n "$ip" ] && echo -e "  ${GREEN}http://${ip}${NC}"
            else
                echo -e "  ${GREEN}http://${hostname}.local:${NGINX_PORT}${NC}"
                [ -n "$ip" ] && echo -e "  ${GREEN}http://${ip}:${NGINX_PORT}${NC}"
            fi
        else
            echo -e "  ${GREEN}http://${hostname}.local:${WEB_PORT}${NC}"
            [ -n "$ip" ] && echo -e "  ${GREEN}http://${ip}:${WEB_PORT}${NC}"
        fi
        echo ""
    fi
    
    show_sftp_instructions
    
    echo "Useful commands:"
    echo "  sudo systemctl status pyrunner      # Check service status"
    echo "  sudo systemctl restart pyrunner     # Restart service"
    echo "  sudo journalctl -u pyrunner -f      # View live logs"
    echo ""
    
    if [ ${#ERRORS[@]} -gt 0 ] || [ $test_result -gt 0 ]; then
        exit 1
    fi
    exit 0
}

main "$@"
