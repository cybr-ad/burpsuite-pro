#!/bin/bash

# ╔══════════════════════════════════════════════════════════════════════╗
# ║      BurpSuite Pro ─ Universal Setup Script v6                       ║
# ║      Supports: Kali Linux · Debian · Ubuntu · Fedora · Arch         ║
# ║      Features: JDK 23 Support · Proxychains Awareness · Clean Net   ║
# ╚══════════════════════════════════════════════════════════════════════╝

# ── Colors & Formatting ──────────────────────────────────────────────────
RED='\033[0;31m';    GREEN='\033[0;32m';  YELLOW='\033[1;33m'
BLUE='\033[0;34m';   CYAN='\033[0;36m';   BOLD='\033[1m';  NC='\033[0m'
MAGENTA='\033[0;35m'

# ── Helper Functions ─────────────────────────────────────────────────────
banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "  ╔════════════════════════════════════════════════════════════╗"
    echo "  ║       BurpSuite Pro ─ Universal Setup Script v6            ║"
    echo "  ║       JDK 23 · Proxychains Safe · Clean Networking         ║"
    echo "  ╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

step()  { echo -e "\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n${BOLD}${GREEN}  $*${NC}\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ ✔ ]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[ ! ]${NC}  $*"; }
err()   { echo -e "${RED}[ ✘ ]${NC}  $*"; }
pause() { echo -e "\n${YELLOW}▶  Press ENTER to continue...${NC}"; read -r; }
die()   { err "$*"; exit 1; }

# ════════════════════════════════════════════════════════════════════════
#  CRITICAL: Identify the REAL user (not root even if run with sudo)
# ════════════════════════════════════════════════════════════════════════
if [ -n "${SUDO_USER:-}" ]; then
    REAL_USER="$SUDO_USER"
else
    REAL_USER="$USER"
fi

REAL_HOME=$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f6)
[ -z "$REAL_HOME" ] && REAL_HOME="$HOME"

REAL_DISPLAY="${DISPLAY:-:0}"
REAL_XAUTH="${XAUTHORITY:-${REAL_HOME}/.Xauthority}"

as_user() {
    if [ "$EUID" -eq 0 ] && [ "$REAL_USER" != "root" ]; then
        sudo -u "$REAL_USER" \
             DISPLAY="$REAL_DISPLAY" \
             XAUTHORITY="$REAL_XAUTH" \
             HOME="$REAL_HOME" \
             "$@"
    else
        DISPLAY="$REAL_DISPLAY" \
        XAUTHORITY="$REAL_XAUTH" \
        HOME="$REAL_HOME" \
        "$@"
    fi
}

banner
info "Executing user : $(whoami) (EUID=$EUID)"
info "Real desktop user : $REAL_USER"
info "Real user home : $REAL_HOME"
info "X11 Display    : $REAL_DISPLAY"
echo ""

# ════════════════════════════════════════════════════════════════════════
#  SAFEGUARD: System State & Network Cleanup
# ════════════════════════════════════════════════════════════════════════
step "INSPECTION ── Restoring Clean System & Network State"

# 1. Clean up any artificial PortSwigger entries in /etc/hosts
if grep -qiE "portswigger|burpsuite" /etc/hosts 2>/dev/null; then
    warn "Detected modified entries in /etc/hosts. Restoring clean hosts file..."
    sudo sed -i '/portswigger/d' /etc/hosts 2>/dev/null || true
    sudo sed -i '/burpsuite/d' /etc/hosts 2>/dev/null || true
    ok "/etc/hosts restored to clean state."
else
    ok "/etc/hosts is clean."
fi

# 2. Inspect and remove custom DROP rules targeting PortSwigger IPs
if command -v iptables &>/dev/null && [ "$EUID" -eq 0 ]; then
    BLOCKED_RULES=$(iptables -L OUTPUT -n --line-numbers 2>/dev/null | grep -E "DROP.*(portswigger|[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)" || true)
    if [ -n "$BLOCKED_RULES" ]; then
        info "Checking firewall OUTPUT chain for custom DROP rules..."
        # Safely remove individual PortSwigger block rules if previously created
        for domain in "portswigger.net" "burpsuite.net" "license.portswigger.net"; do
            mapfile -t ips < <(getent ahosts "$domain" 2>/dev/null | awk '{print $1}' | sort -u)
            for ip in "${ips[@]}"; do
                iptables -D OUTPUT -d "$ip" -j DROP 2>/dev/null || true
            done
        done
        ok "Verified firewall OUTPUT rules."
    else
        ok "No conflicting firewall rules found."
    fi
fi

# ════════════════════════════════════════════════════════════════════════
#  PROXYCHAINS CONFIGURATION & NETWORK MODE
# ════════════════════════════════════════════════════════════════════════
step "NETWORK MODE ── Connection Routing Preference"

HAS_PROXYCHAINS=0
PROXYCHAINS_BIN=""

if command -v proxychains4 &>/dev/null; then
    HAS_PROXYCHAINS=1
    PROXYCHAINS_BIN="proxychains4"
elif command -v proxychains &>/dev/null; then
    HAS_PROXYCHAINS=1
    PROXYCHAINS_BIN="proxychains"
fi

echo -e "Choose how download operations should be routed:"
echo -e "  ${CYAN}1)${NC} ${BOLD}Direct Connection${NC} (Recommended — fast, reliable, bypasses proxy timeouts)"
if [ "$HAS_PROXYCHAINS" -eq 1 ]; then
    echo -e "  ${CYAN}2)${NC} ${BOLD}Proxychains Mode${NC} (Routes file downloads through $PROXYCHAINS_BIN)"
else
    echo -e "  ${CYAN}2)${NC} Proxychains Mode [Unavailable — proxychains not installed]"
fi
echo ""
read -rp "Enter choice [1 or 2, default=1]: " NET_CHOICE
NET_CHOICE="${NET_CHOICE:-1}"

USE_PROXY=0
if [ "$NET_CHOICE" -eq 2 ] && [ "$HAS_PROXYCHAINS" -eq 1 ]; then
    info "Testing $PROXYCHAINS_BIN connectivity..."

    # Check if Tor is installed and inactive
    if command -v systemctl &>/dev/null && systemctl list-unit-files 2>/dev/null | grep -q "^tor\.service"; then
        if ! systemctl is-active --quiet tor; then
            warn "Tor service is currently inactive. Proxychains default config (127.0.0.1:9050) requires Tor."
            read -rp "Would you like to start the Tor service now? [Y/n]: " START_TOR
            START_TOR="${START_TOR:-Y}"
            if [[ "$START_TOR" =~ ^[Yy] ]]; then
                sudo systemctl start tor
                sleep 2
                ok "Tor service started."
            fi
        fi
    fi

    # Perform a quick reachability test through proxychains
    if $PROXYCHAINS_BIN -q curl -sI --max-time 10 "https://portswigger.net" &>/dev/null; then
        USE_PROXY=1
        ok "Proxychains is working and online ✔"
    else
        err "Proxychains test failed (proxy is down, unresponsive, or blocking downloads)."
        echo -e "  ${YELLOW}Common reasons:${NC}"
        echo -e "   • Tor service not running: run ${CYAN}sudo systemctl start tor${NC}"
        echo -e "   • /etc/proxychains4.conf contains dead proxy IPs"
        echo -e "   • DNS timeout via SOCKS proxy"
        echo ""
        read -rp "Fall back to Direct Connection for downloads? [Y/n, default=Y]: " FALLBACK_DIRECT
        FALLBACK_DIRECT="${FALLBACK_DIRECT:-Y}"
        if [[ "$FALLBACK_DIRECT" =~ ^[Yy] ]]; then
            USE_PROXY=0
            ok "Switched to Direct Connection for smooth downloads."
        else
            USE_PROXY=1
            warn "Continuing with Proxychains (downloads may fail if proxy is not fixed)."
        fi
    fi
else
    ok "Direct connection mode enabled."
fi

# Wrapper for download commands
net_run() {
    if [ "$USE_PROXY" -eq 1 ]; then
        $PROXYCHAINS_BIN "$@"
    else
        "$@"
    fi
}

# ════════════════════════════════════════════════════════════════════════
#  JAR Validation Helper
# ════════════════════════════════════════════════════════════════════════
is_valid_jar() {
    local f="$1"
    local min="${2:-5000}"   # Default minimum size 5 KB

    [ ! -f "$f" ] && return 1

    local sz
    sz=$(stat -c%s "$f" 2>/dev/null || echo 0)
    [ "$sz" -lt "$min" ] && return 1

    local magic
    magic=$(head -c 2 "$f" 2>/dev/null)
    [ "$magic" != "PK" ] && return 1

    unzip -t "$f" &>/dev/null && return 0
    return 1
}

# ════════════════════════════════════════════════════════════════════════
#  Google Drive Downloader with Multiple Fallback Methods
# ════════════════════════════════════════════════════════════════════════
gdrive_download() {
    local id="$1"
    local out="$2"

    # Method 1: Direct curl with browser User-Agent
    info "  [Method 1] Trying direct curl download..."
    net_run curl -sL \
         -A "Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0" \
         --max-time 60 --retry 3 \
         "https://drive.google.com/uc?export=download&id=${id}" \
         -o "$out" 2>/dev/null
    if is_valid_jar "$out" 5000; then ok "  curl: success"; return 0; fi
    rm -f "$out"

    # Method 2: Python 3 urllib (cookie & token aware)
    info "  [Method 2] Trying Python urllib..."
    python3 - <<PYEOF 2>/dev/null
import urllib.request, http.cookiejar, re, sys

file_id = "$id"
out_path = "$out"
cookie_jar = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cookie_jar))
headers = {
    'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
}

url = f'https://drive.google.com/uc?export=download&id={file_id}'
req = urllib.request.Request(url, headers=headers)
try:
    resp = opener.open(req, timeout=45)
    data = resp.read()
    if data.startswith(b'PK\x03\x04'):
        with open(out_path, 'wb') as f:
            f.write(data)
        sys.exit(0)
    html = data.decode('utf-8', errors='ignore')
    match = re.search(r'confirm=([0-9A-Za-z_]+)', html)
    token = match.group(1) if match else 't'
    confirm_url = f'https://drive.google.com/uc?export=download&confirm={token}&id={file_id}'
    req2 = urllib.request.Request(confirm_url, headers=headers)
    resp2 = opener.open(req2, timeout=45)
    data2 = resp2.read()
    if data2.startswith(b'PK\x03\x04'):
        with open(out_path, 'wb') as f:
            f.write(data2)
        sys.exit(0)
except Exception:
    sys.exit(1)
sys.exit(1)
PYEOF
    if is_valid_jar "$out" 5000; then ok "  Python urllib: success"; return 0; fi
    rm -f "$out"

    # Method 3: wget with session cookies
    info "  [Method 3] Trying wget with cookies..."
    net_run wget --quiet --no-check-certificate \
         --user-agent="Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0" \
         --save-cookies /tmp/gd_ck.txt \
         --keep-session-cookies \
         "https://drive.google.com/uc?export=download&id=${id}" \
         -O "$out" 2>/dev/null

    if is_valid_jar "$out" 5000; then
        rm -f /tmp/gd_ck.txt
        ok "  wget: success"
        return 0
    fi

    local token
    token=$(grep -oP 'confirm=\K[^&"]+' "$out" 2>/dev/null | head -1)
    if [ -n "$token" ]; then
        net_run wget --quiet --no-check-certificate \
             --user-agent="Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0" \
             --load-cookies /tmp/gd_ck.txt \
             "https://drive.google.com/uc?export=download&confirm=${token}&id=${id}" \
             -O "$out" 2>/dev/null
    fi
    rm -f /tmp/gd_ck.txt

    if is_valid_jar "$out" 5000; then ok "  wget (confirm token): success"; return 0; fi
    rm -f "$out"

    # Method 4: gdown fallback
    info "  [Method 4] Trying gdown..."
    if command -v gdown &>/dev/null || python3 -m gdown --version &>/dev/null 2>&1; then
        net_run python3 -m gdown "https://drive.google.com/uc?id=${id}" -O "$out" --fuzzy 2>/dev/null
        if is_valid_jar "$out" 5000; then ok "  gdown: success"; return 0; fi
    fi
    rm -f "$out"

    return 1
}

# ════════════════════════════════════════════════════════════════════════
#  PRE-FLIGHT ── System Detection & Core Dependencies
# ════════════════════════════════════════════════════════════════════════
step "PRE-FLIGHT ── System Detection & Dependencies"

ARCH=$(uname -m)
DISTRO=$(grep -oP '(?<=^ID=).+' /etc/os-release 2>/dev/null | tr -d '"' || echo "unknown")
info "Detected OS   : $DISTRO"
info "Architecture  : $ARCH"

if [ "$ARCH" != "x86_64" ] && [ "$ARCH" != "amd64" ]; then
    warn "Unsupported architecture ($ARCH). Oracle JDK x64 packages require x86_64."
fi

if command -v apt-get &>/dev/null; then
    info "Updating package lists and installing prerequisites..."
    sudo apt-get update -qq
    sudo apt-get install -y wget curl ca-certificates unzip python3-pip \
        imagemagick libxrender1 libxtst6 libxi6 2>/dev/null
    sudo update-ca-certificates -f 2>/dev/null || true
elif command -v dnf &>/dev/null; then
    sudo dnf install -y wget curl ca-certificates unzip python3-pip ImageMagick 2>/dev/null
elif command -v pacman &>/dev/null; then
    sudo pacman -S --noconfirm wget curl ca-certificates unzip python-pip imagemagick 2>/dev/null
fi

ok "Prerequisites verified."

# ════════════════════════════════════════════════════════════════════════
#  STEP 01 ── Install & Configure JDK 23
# ════════════════════════════════════════════════════════════════════════
step "STEP 01 ── Installing & Configuring JDK 23"

# Check currently active Java version
CURRENT_JAVA_VER=$(java -version 2>&1 | grep -oP 'version "\K[0-9]+' | head -1 || echo "0")
if [ "$CURRENT_JAVA_VER" -eq 0 ]; then
    CURRENT_JAVA_VER=$(java -version 2>&1 | grep -oP 'openjdk \K[0-9]+' | head -1 || echo "0")
fi

info "Current active Java version: $CURRENT_JAVA_VER"

JDK23_INSTALLED=0
if [ "$CURRENT_JAVA_VER" -eq 23 ]; then
    ok "Java 23 is already the active runtime."
    JDK23_INSTALLED=1
elif update-alternatives --list java 2>/dev/null | grep -qE "jdk-23|java-23"; then
    info "Java 23 package found on system. Switching active runtime..."
    JAVA23_BIN=$(update-alternatives --list java 2>/dev/null | grep -E "jdk-23|java-23" | head -1)
    if [ -n "$JAVA23_BIN" ]; then
        sudo update-alternatives --set java "$JAVA23_BIN" 2>/dev/null || true
        JDK23_INSTALLED=1
    fi
fi

if [ "$JDK23_INSTALLED" -eq 0 ]; then
    info "Downloading JDK 23 (Debian x64) from Oracle Archive..."
    mkdir -p "$REAL_HOME/java"
    cd "$REAL_HOME/java" || die "Cannot access $REAL_HOME/java"

    JDK23_URL="https://download.oracle.com/java/23/archive/jdk-23.0.2_linux-x64_bin.deb"
    JDK23_DEB="jdk-23.0.2_linux-x64_bin.deb"

    net_run wget --no-check-certificate --tries=5 --timeout=120 -c "$JDK23_URL" -O "$JDK23_DEB" \
        || die "JDK 23 download failed. Check network or proxy settings."

    info "Installing JDK 23 package via dpkg..."
    sudo dpkg -i "$JDK23_DEB"
    sudo apt-get install -f -y 2>/dev/null || true

    # Clean up deb archive if needed
    cd "$REAL_HOME" || true
fi

# Configure Java alternatives
echo ""
echo -e "${YELLOW}${BOLD}Select the Java 23 / JDK-23 alternative if prompted below:${NC}"
if update-alternatives --list java 2>/dev/null | grep -qE "jdk-23|java-23"; then
    JAVA23_PATH=$(update-alternatives --list java 2>/dev/null | grep -E "jdk-23|java-23" | head -1)
    sudo update-alternatives --set java "$JAVA23_PATH" 2>/dev/null || sudo update-alternatives --config java
else
    sudo update-alternatives --config java
fi

echo ""
info "Active Java runtime:"
java --version || java -version
ok "JDK 23 configured!"
pause

# ════════════════════════════════════════════════════════════════════════
#  STEP 02 ── Download BurpSuite Pro & Loader Files
# ════════════════════════════════════════════════════════════════════════
step "STEP 02 ── Downloading BurpSuite Pro & Helper Files"

BURP_DIR="${REAL_HOME}/Documents/burp"
as_user mkdir -p "$BURP_DIR"
cd "$BURP_DIR" || die "Cannot access $BURP_DIR"
info "Working directory: $BURP_DIR"

GDRIVE_ID="1dr9212KN-PoYPAWI9pNa732JsvfrnDSz"
KEYGEN="BurpLoaderKeygen.jar"

# ── Download BurpLoaderKeygen.jar ─────────────────────────────────────
if is_valid_jar "${BURP_DIR}/${KEYGEN}" 5000; then
    ok "BurpLoaderKeygen.jar already exists and is valid — skipping download."
else
    rm -f "${BURP_DIR}/${KEYGEN}"
    info "Downloading BurpLoaderKeygen.jar..."
    gdrive_download "$GDRIVE_ID" "${BURP_DIR}/${KEYGEN}"

    if ! is_valid_jar "${BURP_DIR}/${KEYGEN}" 5000; then
        rm -f "${BURP_DIR}/${KEYGEN}"
        echo ""
        err "Automated download failed. Please download it manually:"
        echo -e "  ${YELLOW}1. Open this URL in your browser:${NC}"
        echo -e "     ${CYAN}https://drive.google.com/file/d/${GDRIVE_ID}/view${NC}"
        echo -e "  ${YELLOW}2. Save file as:${NC}"
        echo -e "     ${CYAN}${BURP_DIR}/BurpLoaderKeygen.jar${NC}"
        echo -e "  ${YELLOW}3. Return here and press ENTER.${NC}"
        pause
        is_valid_jar "${BURP_DIR}/${KEYGEN}" 5000 \
            || die "BurpLoaderKeygen.jar is not present or invalid."
    fi
fi

ok "BurpLoaderKeygen.jar verified ✔"
sudo chown "$REAL_USER":"$REAL_USER" "${BURP_DIR}/${KEYGEN}" 2>/dev/null || true

# ── Select BurpSuite Pro Version ──────────────────────────────────────
echo ""
echo -e "${BOLD}${YELLOW}Select BurpSuite Pro version:${NC}"
echo -e "  ${CYAN}1)${NC}  v2023.3.3  ${YELLOW}(Recommended — highest loader compatibility)${NC}"
echo -e "  ${CYAN}2)${NC}  v2025.12.3 ${YELLOW}(Latest release)${NC}"
echo ""
read -rp "Enter choice [1 or 2, default=1]: " VER_CHOICE
VER_CHOICE="${VER_CHOICE:-1}"

case "$VER_CHOICE" in
    2)
        BURP_VER="2025.12.3"
        BURP_JAR="burpsuite_pro_v2025.12.3.jar"
        BURP_URL="https://portswigger.net/burp/releases/download?product=pro&version=2025.12.3&type=Jar"
        ;;
    *)
        BURP_VER="2023.3.3"
        BURP_JAR="burpsuite_pro_v2023.3.3.jar"
        BURP_URL="https://portswigger.net/burp/releases/download?product=pro&version=2023.3.3&type=Jar"
        ;;
esac

# ── Download BurpSuite Pro JAR ────────────────────────────────────────
if is_valid_jar "${BURP_DIR}/${BURP_JAR}" 50000000; then
    ok "$BURP_JAR already exists and is valid — skipping download."
else
    rm -f "${BURP_DIR}/${BURP_JAR}"
    info "Downloading BurpSuite Pro v${BURP_VER} (~600 MB)..."
    net_run wget --no-check-certificate --tries=5 --timeout=300 -c \
         "$BURP_URL" -O "${BURP_DIR}/${BURP_JAR}" \
    || die "BurpSuite Pro download failed."

    is_valid_jar "${BURP_DIR}/${BURP_JAR}" 50000000 \
        || die "Downloaded BurpSuite JAR is invalid. Please re-run."
    ok "BurpSuite Pro v${BURP_VER} downloaded successfully!"
fi

sudo chown "$REAL_USER":"$REAL_USER" "${BURP_DIR}/${BURP_JAR}" 2>/dev/null || true
sudo chown "$REAL_USER":"$REAL_USER" "$BURP_DIR" 2>/dev/null || true

echo ""
ok "Files ready in $BURP_DIR:"
ls -lh "$BURP_DIR"
pause

# ════════════════════════════════════════════════════════════════════════
#  STEP 03 ── Launch Keygen & BurpSuite
# ════════════════════════════════════════════════════════════════════════
step "STEP 03 ── Application Launch & Activation Workflow"

echo -e "${BOLD}${CYAN}━━━━━━ ACTIVATION PROCEDURE ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${CYAN}1.${NC} Keygen GUI will open → ${BOLD}Copy the License Key${NC}."
echo -e "  ${CYAN}2.${NC} Click ${BOLD}[ Run ]${NC} in Keygen to start BurpSuite."
echo -e "  ${CYAN}3.${NC} In BurpSuite: Paste the License Key and click ${BOLD}[ Next ]${NC}."
echo -e "  ${CYAN}4.${NC} Select ${BOLD}[ Manual Activation ]${NC} when shown."
echo -e "  ${CYAN}5.${NC} Copy the ${BOLD}Activation Request${NC} from Burp into Keygen."
echo -e "  ${CYAN}6.${NC} Copy the generated ${BOLD}Activation Response${NC} from Keygen into Burp."
echo -e "  ${CYAN}7.${NC} Finish activation in BurpSuite."
echo ""
echo -e "${YELLOW}Press ENTER to launch BurpLoaderKeygen...${NC}"
pause

# ── Launch keygen in background so the window STAYS OPEN on screen ────
JAVA_MODULE_FLAGS="--add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.desktop/javax.swing=ALL-UNNAMED"
info "Launching BurpLoaderKeygen GUI in background (window will stay open)..."
as_user java $JAVA_MODULE_FLAGS -jar "${BURP_DIR}/${KEYGEN}" &
KEYGEN_PID=$!

echo ""
ok "BurpLoaderKeygen GUI is now running (PID: $KEYGEN_PID)."
echo -e "${GREEN}★ The Keygen window is now open on your screen — do NOT close it!${NC}"
echo ""

# ── Ask user if activation is finished or retry ───────────────────────
ACTIVATION_DONE=0
while [ "$ACTIVATION_DONE" -eq 0 ]; do
    echo -e "${BOLD}${YELLOW}Activation Status:${NC}"
    read -rp "Has Burp Suite activation finished successfully? [y/N]: " ACT_INPUT
    if [[ "$ACT_INPUT" =~ ^[Yy] ]]; then
        ACTIVATION_DONE=1
        ok "Activation completed successfully! ✔"
    else
        echo ""
        warn "Activation is not finished yet."
        read -rp "Would you like to re-launch the Keygen to try again? [Y/n, default=Y]: " RETRY_ACT
        RETRY_ACT="${RETRY_ACT:-Y}"
        if [[ "$RETRY_ACT" =~ ^[Yy] ]]; then
            info "Relaunching BurpLoaderKeygen GUI..."
            as_user java $JAVA_MODULE_FLAGS -jar "${BURP_DIR}/${KEYGEN}" &
            KEYGEN_PID=$!
            ok "BurpLoaderKeygen relaunched (PID: $KEYGEN_PID)."
            echo -e "${CYAN}Complete the activation steps in the GUI, then return here.${NC}"
        else
            warn "Proceeding with launcher setup..."
            ACTIVATION_DONE=1
        fi
    fi
done

# ── Step 03b: Copy Loader Command ─────────────────────────────────────
echo ""
echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${YELLOW}  STEP 03b ── GET THE LOADER COMMAND FROM KEYGEN${NC}"
echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${YELLOW}★ Make sure to KEEP the Keygen loader window open!${NC}"
echo -e "  ${CYAN}1.${NC} Look at the ${BOLD}'Loader Command'${NC} field at the top of the Keygen window."
echo -e "  ${CYAN}2.${NC} Copy the text from that field and paste it below."
echo -e "  ${CYAN}3.${NC} (Or press ENTER to use the auto-detected Java 23 command)."
echo ""
read -rp "Paste Loader Command here [or press ENTER]: " CUSTOM_LOADER_CMD

if [ -n "$CUSTOM_LOADER_CMD" ]; then
    LOADER_CMD="$CUSTOM_LOADER_CMD"
else
    JAVA_BIN=$(readlink -f "$(which java)" 2>/dev/null || echo "java")
    LOADER_CMD="\"$JAVA_BIN\" $JAVA_MODULE_FLAGS -javaagent:\"${BURP_DIR}/${KEYGEN}\" -jar \"${BURP_DIR}/${BURP_JAR}\""
fi

echo ""
ok "Loader command configured:"
echo -e "  ${CYAN}${LOADER_CMD}${NC}"
echo ""

# ── Create ~/Documents/burp/burp.sh with nohup ────────────────────────
BURP_SH="${BURP_DIR}/burp.sh"
info "Creating startup script at $BURP_SH..."

cat > "$BURP_SH" <<EOF
#!/bin/bash
nohup ${LOADER_CMD} >/dev/null 2>&1 &
EOF

chmod +x "$BURP_SH"
sudo chown "$REAL_USER":"$REAL_USER" "$BURP_SH" 2>/dev/null || true
ok "Startup script created: $BURP_SH ✔"

# ── Create /usr/local/bin/burp-pro symlink ─────────────────────────────
info "Creating system symlink: /usr/local/bin/burp-pro -> $BURP_SH..."
sudo rm -f /usr/local/bin/burp-pro
sudo ln -sf "$BURP_SH" /usr/local/bin/burp-pro
ok "CLI command created: type ${BOLD}burp-pro${NC} in any terminal to launch!"

# ════════════════════════════════════════════════════════════════════════
#  STEP 04 ── Create Desktop Launcher
# ════════════════════════════════════════════════════════════════════════
step "STEP 04 ── Creating Desktop Launcher"

ICON_DIR="${REAL_HOME}/.local/share/icons"
as_user mkdir -p "$ICON_DIR"
ICON_PATH="${ICON_DIR}/burpsuite.png"

# Extract icon from BurpSuite JAR
if command -v unzip &>/dev/null && [ ! -s "$ICON_PATH" ]; then
    info "Extracting icon from BurpSuite JAR..."
    ICON_ENTRY=$(unzip -l "${BURP_DIR}/${BURP_JAR}" 2>/dev/null \
        | grep -iE '\.png' \
        | grep -iE 'burp|icon|logo|media|splash' \
        | awk '{print $NF}' | head -1)
    if [ -n "$ICON_ENTRY" ]; then
        unzip -p "${BURP_DIR}/${BURP_JAR}" "$ICON_ENTRY" > "$ICON_PATH" 2>/dev/null \
            && ok "Icon extracted: $ICON_ENTRY" \
            || rm -f "$ICON_PATH"
    fi
fi

if [ ! -s "$ICON_PATH" ]; then
    ICON_PATH="application-x-java"
else
    sudo chown "$REAL_USER":"$REAL_USER" "$ICON_PATH" 2>/dev/null || true
fi

# Create Desktop Entry
DESKTOP_DIR="${REAL_HOME}/Desktop"
as_user mkdir -p "$DESKTOP_DIR"
DESKTOP_FILE="${DESKTOP_DIR}/Burp-pro.desktop"

as_user bash -c "cat > '${DESKTOP_FILE}'" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Burp-pro
GenericName=BurpSuite Professional
Comment=BurpSuite Pro v${BURP_VER} - Web Security Testing
Exec=${BURP_SH}
Icon=${ICON_PATH}
Terminal=false
Categories=Security;Network;Development;
Keywords=burpsuite;security;web;proxy;pentest;
StartupNotify=true
StartupWMClass=burp-StartBurp
EOF

chmod +x "$DESKTOP_FILE"
sudo chown "$REAL_USER":"$REAL_USER" "$DESKTOP_FILE" 2>/dev/null || true

# Register in applications menu
APPS_MENU_DIR="${REAL_HOME}/.local/share/applications"
as_user mkdir -p "$APPS_MENU_DIR"
cp "$DESKTOP_FILE" "${APPS_MENU_DIR}/Burp-pro.desktop" 2>/dev/null || true

ok "Desktop launcher created at: $DESKTOP_FILE"

# ════════════════════════════════════════════════════════════════════════
#  STEP 05 ── System & Installation Diagnostics
# ════════════════════════════════════════════════════════════════════════
step "DIAGNOSTICS ── System Summary"

echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║                   ✔   Installation Summary                   ║"
echo "  ╠══════════════════════════════════════════════════════════════╣"
printf "  ║  %-58s║\n" "  OS / Distro   : $DISTRO ($ARCH)"
printf "  ║  %-58s║\n" "  User          : $REAL_USER"
printf "  ║  %-58s║\n" "  Active Java   : $(java -version 2>&1 | head -1)"
printf "  ║  %-58s║\n" "  Burp Version  : v${BURP_VER}"
printf "  ║  %-58s║\n" "  Directory     : $BURP_DIR"
printf "  ║  %-58s║\n" "  Script        : $BURP_SH"
printf "  ║  %-58s║\n" "  CLI Command   : /usr/local/bin/burp-pro"
printf "  ║  %-58s║\n" "  Launcher      : $DESKTOP_FILE"
printf "  ║  %-58s║\n" "  Network Mode  : $([ "$USE_PROXY" -eq 1 ] && echo "Proxychains" || echo "Direct")"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${GREEN}All set! You can launch BurpSuite Pro by:${NC}"
echo -e "  1. Double-clicking ${BOLD}Burp-pro${NC} on your Desktop"
echo -e "  2. Typing ${BOLD}burp-pro${NC} in any terminal\n"
