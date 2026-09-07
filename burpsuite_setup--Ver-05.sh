#!/bin/bash

# ╔══════════════════════════════════════════════════════════════════════╗
# ║      BurpSuite Pro ─ Universal Setup Script v5                       ║
# ║      Supports: Kali · Debian · Ubuntu · Fedora · Arch               ║
# ║      Fix v5: Forces Manual Activation by blocking PortSwigger net    ║
# ║              Runs keygen/burp as real user (not root)                ║
# ╚══════════════════════════════════════════════════════════════════════╝

# ── Colors ───────────────────────────────────────────────────────────────
RED='\033[0;31m';    GREEN='\033[0;32m';  YELLOW='\033[1;33m'
BLUE='\033[0;34m';   CYAN='\033[0;36m';   BOLD='\033[1m';  NC='\033[0m'
MAGENTA='\033[0;35m'

# ── Helpers ──────────────────────────────────────────────────────────────
banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "  ╔════════════════════════════════════════════════════════════╗"
    echo "  ║       BurpSuite Pro ─ Universal Setup Script v5            ║"
    echo "  ║       Fixes: Manual Activation · Keygen Flow · Stability   ║"
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
if [ -n "$SUDO_USER" ]; then
    REAL_USER="$SUDO_USER"
else
    REAL_USER="$USER"
fi

REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
REAL_DISPLAY="${DISPLAY:-:0}"
REAL_XAUTH="${XAUTHORITY:-${REAL_HOME}/.Xauthority}"

# Run a command as the real user (with display access)
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
info "Running as     : $(whoami) (EUID=$EUID)"
info "Real user      : $REAL_USER"
info "Real home      : $REAL_HOME"
info "Display        : $REAL_DISPLAY"
echo ""


# ════════════════════════════════════════════════════════════════════════
#  JAR Validation: checks magic bytes + zip integrity + min size
# ════════════════════════════════════════════════════════════════════════
is_valid_jar() {
    local f="$1"
    local min="${2:-100000}"   # minimum 100 KB by default

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
#  Google Drive downloader — 3 fallback methods
# ════════════════════════════════════════════════════════════════════════
gdrive_download() {
    local id="$1"
    local out="$2"

    # ── Method 1: gdown ──────────────────────────────────────────────
    info "  [Method 1] Trying gdown..."
    pip3 install -q gdown --break-system-packages 2>/dev/null \
        || pip3 install -q gdown 2>/dev/null || true

    if command -v gdown &>/dev/null || python3 -m gdown --version &>/dev/null 2>&1; then
        python3 -m gdown "https://drive.google.com/uc?id=${id}" -O "$out" 2>/dev/null
        if is_valid_jar "$out"; then ok "  gdown: success"; return 0; fi
    fi
    rm -f "$out"

    # ── Method 2: curl drive.usercontent ────────────────────────────
    info "  [Method 2] Trying curl via drive.usercontent.google.com..."
    curl -L \
         --silent --show-error \
         --max-time 180 --retry 3 \
         "https://drive.usercontent.google.com/download?id=${id}&export=download&authuser=0&confirm=t" \
         -o "$out" 2>/dev/null
    if is_valid_jar "$out"; then ok "  curl: success"; return 0; fi
    rm -f "$out"

    # ── Method 3: wget with cookie/token ─────────────────────────────
    info "  [Method 3] Trying wget cookie/token method..."
    wget --quiet --no-check-certificate \
         --save-cookies /tmp/gd_ck.txt \
         --keep-session-cookies \
         "https://docs.google.com/uc?export=download&id=${id}" \
         -O /tmp/gd_page.html 2>/dev/null

    local token
    token=$(grep -oP 'confirm=\K[^&"]+' /tmp/gd_page.html 2>/dev/null | head -1)
    [ -z "$token" ] && token="t"

    wget --no-check-certificate \
         --load-cookies /tmp/gd_ck.txt \
         "https://docs.google.com/uc?export=download&confirm=${token}&id=${id}" \
         -O "$out" 2>/dev/null

    rm -f /tmp/gd_ck.txt /tmp/gd_page.html

    if is_valid_jar "$out"; then ok "  wget: success"; return 0; fi
    rm -f "$out"
    return 1
}


# ════════════════════════════════════════════════════════════════════════
#  Network block/unblock helpers
#
#  PURPOSE: Force BurpSuite to show "Manual Activation" immediately.
#  Without this, BurpSuite's online activation attempt hangs for 60-90s
#  and the "Manual Activation" link is hidden until it times out.
#  By blocking PortSwigger servers, online activation fails instantly
#  and Manual Activation appears right away.
# ════════════════════════════════════════════════════════════════════════

# Domains used by BurpSuite for license activation
BLOCK_DOMAINS=(
    "portswigger.net"
    "burpsuite.net"
    "api.portswigger.net"
    "license.portswigger.net"
    "updates.portswigger.net"
)

_IPTABLES_RULES_ADDED=0

block_activation_network() {
    if ! command -v iptables &>/dev/null; then
        warn "iptables not found — skipping network block."
        warn "If Manual Activation does not appear, temporarily disable your internet."
        return
    fi

    info "Blocking PortSwigger activation servers (forces Manual Activation instantly)..."
    for domain in "${BLOCK_DOMAINS[@]}"; do
        # Resolve IPs and block outbound connections to them
        mapfile -t ips < <(getent ahosts "$domain" 2>/dev/null | awk '{print $1}' | sort -u)
        for ip in "${ips[@]}"; do
            iptables -I OUTPUT -d "$ip" -j DROP 2>/dev/null && \
                info "  Blocked: $ip ($domain)"
        done
        # Also block by hostname via /etc/hosts
        if ! grep -q "^0\.0\.0\.0[[:space:]]*${domain}" /etc/hosts 2>/dev/null; then
            echo "0.0.0.0 ${domain}" >> /etc/hosts
        fi
    done

    _IPTABLES_RULES_ADDED=1
    ok "Network block applied — Manual Activation will appear immediately in BurpSuite."
}

unblock_activation_network() {
    if [ "$_IPTABLES_RULES_ADDED" -ne 1 ]; then return; fi

    info "Removing PortSwigger network block..."
    for domain in "${BLOCK_DOMAINS[@]}"; do
        mapfile -t ips < <(getent ahosts "$domain" 2>/dev/null | awk '{print $1}' | sort -u)
        for ip in "${ips[@]}"; do
            iptables -D OUTPUT -d "$ip" -j DROP 2>/dev/null || true
        done
        # Remove from /etc/hosts
        sed -i "/^0\.0\.0\.0[[:space:]]*${domain}/d" /etc/hosts 2>/dev/null || true
    done

    _IPTABLES_RULES_ADDED=0
    ok "Network block removed — internet access restored."
}

# Ensure cleanup always runs on exit
trap 'unblock_activation_network' EXIT INT TERM


# ════════════════════════════════════════════════════════════════════════
#  PRE-FLIGHT ── Distro detection & dependencies
# ════════════════════════════════════════════════════════════════════════
step "PRE-FLIGHT ── Detecting System & Installing Dependencies"

DISTRO=$(grep -oP '(?<=^ID=).+' /etc/os-release 2>/dev/null | tr -d '"' || echo "unknown")
info "Distro: $DISTRO"

if command -v apt-get &>/dev/null; then
    info "Package manager: apt"
    sudo apt-get update -qq
    sudo apt-get install -y wget curl ca-certificates unzip python3-pip \
        imagemagick iptables iproute2 2>/dev/null
    sudo update-ca-certificates -f 2>/dev/null || true
elif command -v dnf &>/dev/null; then
    sudo dnf install -y wget curl ca-certificates unzip python3-pip \
        ImageMagick iptables iproute 2>/dev/null
elif command -v yum &>/dev/null; then
    sudo yum install -y wget curl ca-certificates unzip python3-pip \
        ImageMagick iptables iproute 2>/dev/null
elif command -v pacman &>/dev/null; then
    sudo pacman -S --noconfirm wget curl ca-certificates unzip python-pip \
        imagemagick iptables iproute2 2>/dev/null
fi

ok "Dependencies ready."


# ════════════════════════════════════════════════════════════════════════
#  STEP 01 ── Install JDK 25
# ════════════════════════════════════════════════════════════════════════
step "STEP 01 ── Downloading & Installing JDK 25"

CURRENT_JAVA=$(java -version 2>&1 | grep -oP '\d+' | head -1 || echo "0")

if [ "$CURRENT_JAVA" -ge 25 ] 2>/dev/null; then
    ok "Java $CURRENT_JAVA already installed — skipping."
    java --version
else
    info "Java 25 not found. Downloading from Oracle..."
    mkdir -p "$REAL_HOME/java"
    cd "$REAL_HOME/java" || die "Cannot cd to $REAL_HOME/java"

    wget --no-check-certificate \
         --tries=5 --timeout=120 -c \
         "https://download.oracle.com/java/25/latest/jdk-25_linux-x64_bin.deb" \
    || die "JDK 25 download failed."

    info "Installing JDK 25..."
    sudo dpkg -i *.deb
    sudo apt-get install -f -y 2>/dev/null || true

    cd "$REAL_HOME" || true
fi

echo ""
echo -e "${YELLOW}${BOLD}ACTION REQUIRED: Select the OpenJDK 25 / Java 25 entry below."
echo -e "Type its number and press ENTER.${NC}"
sudo update-alternatives --config java

echo ""
info "Java version in use:"
java --version
ok "JDK 25 configured!"
pause


# ════════════════════════════════════════════════════════════════════════
#  STEP 02 ── Create ~/Documents/burp & download files
# ════════════════════════════════════════════════════════════════════════
step "STEP 02 ── Downloading BurpSuite Pro Files"

BURP_DIR="${REAL_HOME}/Documents/burp"
as_user mkdir -p "$BURP_DIR"
cd "$BURP_DIR" || die "Cannot cd to $BURP_DIR"
info "Working directory: $BURP_DIR"

GDRIVE_ID="1dr9212KN-PoYPAWI9pNa732JsvfrnDSz"
KEYGEN="BurpLoaderKeygen.jar"

# ── Download keygen ───────────────────────────────────────────────────
if is_valid_jar "${BURP_DIR}/${KEYGEN}"; then
    warn "BurpLoaderKeygen.jar already exists and is valid — skipping download."
else
    rm -f "${BURP_DIR}/${KEYGEN}"
    info "Downloading BurpLoaderKeygen.jar from Google Drive..."
    gdrive_download "$GDRIVE_ID" "${BURP_DIR}/${KEYGEN}"

    if ! is_valid_jar "${BURP_DIR}/${KEYGEN}"; then
        rm -f "${BURP_DIR}/${KEYGEN}"
        echo ""
        err "Automated download failed. Please download it manually:"
        echo -e "  ${YELLOW}1. Open this URL in your browser:${NC}"
        echo -e "     ${CYAN}https://drive.google.com/file/d/${GDRIVE_ID}/view${NC}"
        echo -e "  ${YELLOW}2. Download and save it as:${NC}"
        echo -e "     ${CYAN}${BURP_DIR}/BurpLoaderKeygen.jar${NC}"
        echo -e "  ${YELLOW}3. Then come back here and press ENTER.${NC}"
        pause
        is_valid_jar "${BURP_DIR}/${KEYGEN}" \
            || die "BurpLoaderKeygen.jar still invalid after manual download."
    fi
fi

ok "BurpLoaderKeygen.jar is valid ✔"
sudo chown "$REAL_USER":"$REAL_USER" "${BURP_DIR}/${KEYGEN}" 2>/dev/null || true

# ── Choose BurpSuite version ──────────────────────────────────────────
echo ""
echo -e "${BOLD}${YELLOW}Which BurpSuite Pro version do you need?${NC}"
echo ""
echo -e "  ${CYAN}1)${NC}  v2023.3.3   ${YELLOW}(recommended — most compatible with the keygen)${NC}"
echo -e "  ${CYAN}2)${NC}  v2025.12.3  ${YELLOW}(latest)${NC}"
echo ""
read -rp "  Enter choice [1 or 2, default=1]: " VER_CHOICE

case "$VER_CHOICE" in
    2)
        BURP_VER="2025.12.3"
        BURP_JAR="burpsuite_pro_v2025.12.3.jar"
        BURP_URL='https://portswigger.net/burp/releases/download?product=pro&version=2025.12.3&type=Jar'
        ;;
    *)
        warn "Using v2023.3.3 (default)."
        BURP_VER="2023.3.3"
        BURP_JAR="burpsuite_pro_v2023.3.3.jar"
        BURP_URL='https://portswigger.net/burp/releases/download?product=pro&version=2023.3.3&type=Jar'
        ;;
esac

# ── Download BurpSuite jar ────────────────────────────────────────────
if is_valid_jar "${BURP_DIR}/${BURP_JAR}"; then
    warn "$BURP_JAR already exists and is valid — skipping download."
else
    rm -f "${BURP_DIR}/${BURP_JAR}"
    info "Downloading BurpSuite Pro v${BURP_VER} (large file — please wait)..."
    wget --no-check-certificate --tries=5 --timeout=300 -c \
         "$BURP_URL" -O "${BURP_DIR}/${BURP_JAR}" \
    || die "BurpSuite Pro download failed."
    is_valid_jar "${BURP_DIR}/${BURP_JAR}" \
        || die "BurpSuite jar is invalid after download. Try re-running."
    ok "BurpSuite Pro v${BURP_VER} ready!"
fi

sudo chown "$REAL_USER":"$REAL_USER" "${BURP_DIR}/${BURP_JAR}" 2>/dev/null || true
sudo chown "$REAL_USER":"$REAL_USER" "$BURP_DIR" 2>/dev/null || true

echo ""
ok "Files in $BURP_DIR:"
ls -lh "$BURP_DIR"
pause


# ════════════════════════════════════════════════════════════════════════
#  STEP 03 ── Run Keygen & Activate BurpSuite
#
#  KEY FIX v5: We block PortSwigger's activation servers BEFORE launching
#  BurpSuite via iptables + /etc/hosts. This causes online activation to
#  fail IMMEDIATELY, making the "Manual Activation" button appear at once.
#  The block is removed automatically after activation is confirmed.
# ════════════════════════════════════════════════════════════════════════
step "STEP 03 ── Activation (running as: $REAL_USER)"

echo -e "${BOLD}${CYAN}━━━━━━ HOW ACTIVATION WORKS (v5 FIX) ━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${YELLOW}★ This script will BLOCK PortSwigger's servers before opening Burp.${NC}"
echo -e "  ${YELLOW}★ This forces online activation to fail instantly.${NC}"
echo -e "  ${YELLOW}★ The 'Manual Activation' button appears IMMEDIATELY — no waiting.${NC}"
echo -e "  ${YELLOW}★ After activation, the block is removed and internet is restored.${NC}"
echo ""
echo -e "${BOLD}${CYAN}━━━━━━ STEPS TO FOLLOW ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${CYAN} 1.${NC}  Keygen GUI opens → ${BOLD}Copy the License Key${NC} from it."
echo -e "  ${CYAN} 2.${NC}  Click ${BOLD}[ Run ]${NC} in the keygen."
echo -e "        → ${RED}${BOLD}Use only the Run button. Do NOT open BurpSuite separately!${NC}"
echo ""
echo -e "  ${CYAN} 3.${NC}  In BurpSuite: click ${BOLD}[ Next ]${NC} past the welcome screen."
echo -e "  ${CYAN} 4.${NC}  Paste the ${BOLD}License Key${NC} → click ${BOLD}[ Next ]${NC}."
echo -e "  ${CYAN} 5.${NC}  ${GREEN}${BOLD}\"Manual Activation\" appears immediately.${NC}"
echo -e "        → Click ${BOLD}[ Manual Activation ]${NC}."
echo ""
echo -e "  ${CYAN} 6.${NC}  ${BOLD}Copy the Activation Request${NC} text from BurpSuite."
echo -e "  ${CYAN} 7.${NC}  ${BOLD}Paste it${NC} into the ${BOLD}Activation Request${NC} box in the Keygen."
echo -e "  ${CYAN} 8.${NC}  The Keygen shows an ${BOLD}Activation Response${NC} — ${BOLD}copy it${NC}."
echo -e "  ${CYAN} 9.${NC}  In BurpSuite: click ${BOLD}[ Paste Response ]${NC} → paste → click ${BOLD}[ Next ]${NC}."
echo -e "  ${CYAN}10.${NC}  ${GREEN}${BOLD}BurpSuite Pro is activated! ✔${NC}"
echo ""
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Press ENTER to apply network block and launch the keygen.${NC}"
pause

# ── Apply network block BEFORE launching ─────────────────────────────
block_activation_network

# ── Launch keygen as real user ────────────────────────────────────────
cd "$BURP_DIR" || true
info "Starting BurpLoaderKeygen as: $REAL_USER"
info "Command: java -jar ${BURP_DIR}/${KEYGEN}"
echo ""
as_user java -jar "${BURP_DIR}/${KEYGEN}"

echo ""
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${GREEN}  Press ENTER only after BurpSuite Pro is FULLY ACTIVATED. ✔${NC}"
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
pause

# ── Remove network block after activation confirmed ───────────────────
unblock_activation_network
_IPTABLES_RULES_ADDED=0   # prevent double-cleanup on EXIT trap


# ════════════════════════════════════════════════════════════════════════
#  STEP 03b ── Get the Loader Command from keygen (2nd run)
# ════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}${YELLOW}━━━━━━ GET THE LOADER COMMAND ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${CYAN}1.${NC}  We will open the keygen ONE MORE TIME."
echo -e "  ${CYAN}2.${NC}  Find the ${BOLD}'Loader Command'${NC} field in the keygen window."
echo -e "  ${CYAN}3.${NC}  ${BOLD}Copy the entire command${NC} from that field."
echo -e "  ${CYAN}4.${NC}  Close the keygen and come back here to paste it."
echo ""
echo -e "${YELLOW}Press ENTER to open the keygen for the Loader Command.${NC}"
pause

info "Starting BurpLoaderKeygen (2nd time — get the Loader Command)..."
as_user java -jar "${BURP_DIR}/${KEYGEN}"

echo ""
echo -e "${BOLD}${YELLOW}Paste the Loader Command you copied from the keygen:${NC}"
echo -e "${CYAN}  (Looks like: java -javaagent:/path/BurpLoaderKeygen.jar=... -jar /path/burpsuite.jar)${NC}"
echo ""
read -rp "  Loader Command: " LOADER_CMD

if [ -z "$LOADER_CMD" ]; then
    warn "No command entered — using safe fallback."
    LOADER_CMD="java -javaagent:${BURP_DIR}/${KEYGEN} -jar ${BURP_DIR}/${BURP_JAR}"
fi

ok "Loader command saved:"
echo -e "  ${CYAN}${LOADER_CMD}${NC}"
pause


# ════════════════════════════════════════════════════════════════════════
#  STEP 04 ── Create Desktop Launcher "Burp-pro"
# ════════════════════════════════════════════════════════════════════════
step "STEP 04 ── Creating Desktop Launcher: Burp-pro"

ICON_DIR="${REAL_HOME}/.local/share/icons"
as_user mkdir -p "$ICON_DIR"
ICON_PATH="${ICON_DIR}/burpsuite.png"

# ── Extract icon from BurpSuite jar ──────────────────────────────────
if command -v unzip &>/dev/null && [ ! -s "$ICON_PATH" ]; then
    info "Extracting icon from BurpSuite jar..."
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

# ── Fallback: download icon ───────────────────────────────────────────
if [ ! -s "$ICON_PATH" ]; then
    info "Downloading icon from portswigger.net..."
    curl -sL --max-time 15 \
         "https://portswigger.net/favicon.ico" \
         -o "${ICON_DIR}/burpsuite.ico" 2>/dev/null || true

    if command -v convert &>/dev/null && [ -s "${ICON_DIR}/burpsuite.ico" ]; then
        convert "${ICON_DIR}/burpsuite.ico[0]" "$ICON_PATH" 2>/dev/null \
            && ok "Icon converted."
    fi
fi

if [ ! -s "$ICON_PATH" ]; then
    warn "No icon found — using system default."
    ICON_PATH="application-x-java"
else
    ok "Icon: $ICON_PATH"
    sudo chown "$REAL_USER":"$REAL_USER" "$ICON_PATH" 2>/dev/null || true
fi

# ── Write .desktop launcher as real user ─────────────────────────────
DESKTOP_DIR="${REAL_HOME}/Desktop"
as_user mkdir -p "$DESKTOP_DIR"
DESKTOP="${DESKTOP_DIR}/Burp-pro.desktop"

as_user bash -c "cat > '${DESKTOP}'" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Burp-pro
GenericName=BurpSuite Professional
Comment=BurpSuite Pro v${BURP_VER} - Web Security Testing
Exec=${LOADER_CMD}
Icon=${ICON_PATH}
Terminal=false
Categories=Security;Network;Development;
Keywords=burpsuite;security;web;proxy;pentest;
StartupNotify=true
StartupWMClass=burp-StartBurp
EOF

chmod +x "$DESKTOP"
sudo chown "$REAL_USER":"$REAL_USER" "$DESKTOP" 2>/dev/null || true

# GNOME: mark as trusted so it runs without a dialog
as_user gio set "$DESKTOP" metadata::trusted true 2>/dev/null || true

# KDE: also copy to applications menu
KDE_APPS="${REAL_HOME}/.local/share/applications"
as_user mkdir -p "$KDE_APPS"
cp "$DESKTOP" "${KDE_APPS}/Burp-pro.desktop" 2>/dev/null || true

ok "Desktop launcher created: $DESKTOP"


# ════════════════════════════════════════════════════════════════════════
#  ALL DONE ✔
# ════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║                   ✔   Setup Complete!                        ║"
echo "  ╠══════════════════════════════════════════════════════════════╣"
printf "  ║  %-58s║\n" "  Distro       : $DISTRO"
printf "  ║  %-58s║\n" "  Real User    : $REAL_USER"
printf "  ║  %-58s║\n" "  Java         : $(java -version 2>&1 | head -1)"
printf "  ║  %-58s║\n" "  BurpSuite    : v${BURP_VER}"
printf "  ║  %-58s║\n" "  Files        : $BURP_DIR"
printf "  ║  %-58s║\n" "  Launcher     : $DESKTOP"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  ${GREEN}Double-click ${BOLD}Burp-pro${NC}${GREEN} on your Desktop to launch BurpSuite Pro! 🎯${NC}"
echo ""
