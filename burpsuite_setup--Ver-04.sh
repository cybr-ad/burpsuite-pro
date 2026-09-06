#!/bin/bash

# ╔══════════════════════════════════════════════════════════════════╗
# ║      BurpSuite Pro ─ Universal Setup Script v4                   ║
# ║      Supports: Kali · Debian · Ubuntu · Fedora · Arch            ║
# ║      Fix: runs keygen/burp as real user, NOT root                ║
# ╚══════════════════════════════════════════════════════════════════╝

# ── Colors ──────────────────────────────────────────────────────────
RED='\033[0;31m';  GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m';  BOLD='\033[1m'; NC='\033[0m'

# ── Helpers ─────────────────────────────────────────────────────────
banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    echo "  ║       BurpSuite Pro ─ Universal Setup Script v4          ║"
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}
step()  { echo -e "\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n${BOLD}${GREEN}  $*${NC}\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ ✔ ]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[ ! ]${NC}  $*"; }
err()   { echo -e "${RED}[ ✘ ]${NC}  $*"; }
pause() { echo -e "\n${YELLOW}▶  Press ENTER to continue...${NC}"; read -r; }
die()   { err "$*"; exit 1; }


# ════════════════════════════════════════════════════════════════════
#  CRITICAL: Identify the REAL user (not root even if run with sudo)
#  This is the ROOT CAUSE fix — keygen/BurpSuite must run as the
#  real user so GUI display, home directory, and Java config are
#  all correct.
# ════════════════════════════════════════════════════════════════════

# Detect real user
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
        "$@"
    fi
}

banner
info "Running as     : $(whoami) (EUID=$EUID)"
info "Real user      : $REAL_USER"
info "Real home      : $REAL_HOME"
info "Display        : $REAL_DISPLAY"
echo ""


# ════════════════════════════════════════════════════════════════════
#  JAR Validation: checks magic bytes + zip integrity + min size
# ════════════════════════════════════════════════════════════════════
is_valid_jar() {
    local f="$1"
    local min="${2:-100000}"   # minimum 100 KB

    [ ! -f "$f" ] && return 1

    # Size check
    local sz
    sz=$(stat -c%s "$f" 2>/dev/null || echo 0)
    [ "$sz" -lt "$min" ] && return 1

    # Magic bytes: every JAR/ZIP starts with PK (0x504B)
    local magic
    magic=$(head -c 2 "$f" 2>/dev/null)
    [ "$magic" != "PK" ] && return 1

    # Full zip integrity check
    unzip -t "$f" &>/dev/null && return 0

    return 1
}


# ════════════════════════════════════════════════════════════════════
#  Google Drive downloader — 3 fallback methods
# ════════════════════════════════════════════════════════════════════
gdrive_download() {
    local id="$1"
    local out="$2"

    # ── Method 1: gdown ─────────────────────────────────────────────
    info "  [Method 1] Installing & using gdown..."
    pip3 install -q gdown --break-system-packages 2>/dev/null \
        || pip3 install -q gdown 2>/dev/null || true

    if command -v gdown &>/dev/null || python3 -m gdown --version &>/dev/null 2>&1; then
        python3 -m gdown "https://drive.google.com/uc?id=${id}" -O "$out" 2>/dev/null
        if is_valid_jar "$out"; then ok "  gdown: success"; return 0; fi
    fi
    rm -f "$out"

    # ── Method 2: curl drive.usercontent ────────────────────────────
    info "  [Method 2] curl drive.usercontent.google.com..."
    curl -L \
         --silent --show-error \
         --max-time 180 --retry 3 \
         "https://drive.usercontent.google.com/download?id=${id}&export=download&authuser=0&confirm=t" \
         -o "$out" 2>/dev/null
    if is_valid_jar "$out"; then ok "  curl: success"; return 0; fi
    rm -f "$out"

    # ── Method 3: wget with cookie/token ────────────────────────────
    info "  [Method 3] wget cookie/token method..."
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


# ════════════════════════════════════════════════════════════════════
#  PRE-FLIGHT ── Distro detection & dependencies (needs sudo)
# ════════════════════════════════════════════════════════════════════
step "PRE-FLIGHT ── Detecting System & Installing Dependencies"

DISTRO=$(grep -oP '(?<=^ID=).+' /etc/os-release 2>/dev/null | tr -d '"' || echo "unknown")
info "Distro: $DISTRO"

if command -v apt-get &>/dev/null; then
    info "Package manager: apt"
    sudo apt-get update -qq
    sudo apt-get install -y wget curl ca-certificates unzip python3-pip imagemagick 2>/dev/null
    sudo update-ca-certificates -f 2>/dev/null || true
elif command -v dnf &>/dev/null; then
    sudo dnf install -y wget curl ca-certificates unzip python3-pip ImageMagick 2>/dev/null
elif command -v yum &>/dev/null; then
    sudo yum install -y wget curl ca-certificates unzip python3-pip ImageMagick 2>/dev/null
elif command -v pacman &>/dev/null; then
    sudo pacman -S --noconfirm wget curl ca-certificates unzip python-pip imagemagick 2>/dev/null
fi

ok "Dependencies ready."


# ════════════════════════════════════════════════════════════════════
#  STEP 01 ── Install JDK 25
# ════════════════════════════════════════════════════════════════════
step "STEP 01 ── Downloading & Installing JDK 25"

CURRENT_JAVA=$(java -version 2>&1 | grep -oP '\d+' | head -1 || echo "0")

if [ "$CURRENT_JAVA" -ge 25 ] 2>/dev/null; then
    ok "Java $CURRENT_JAVA already installed — skipping."
    java --version
else
    info "Java 25 not found. Downloading from Oracle..."
    mkdir -p "$REAL_HOME/java"
    cd "$REAL_HOME/java"

    wget --no-check-certificate \
         --tries=5 --timeout=120 -c \
         "https://download.oracle.com/java/25/latest/jdk-25_linux-x64_bin.deb" \
    || die "JDK 25 download failed."

    info "Installing JDK 25..."
    sudo dpkg -i *.deb
    sudo apt-get install -f -y 2>/dev/null || true

    cd "$REAL_HOME"
fi

echo ""
echo -e "${YELLOW}${BOLD}ACTION: Select the OpenJDK 25 / Java 25 entry. Type its number + ENTER.${NC}"
sudo update-alternatives --config java

echo ""
info "Java version:"
java --version
ok "JDK 25 configured!"
pause


# ════════════════════════════════════════════════════════════════════
#  STEP 02 ── Create ~/Documents/burp & download files
# ════════════════════════════════════════════════════════════════════
step "STEP 02 ── Downloading BurpSuite Pro Files"

BURP_DIR="${REAL_HOME}/Documents/burp"
as_user mkdir -p "$BURP_DIR"
cd "$BURP_DIR"
info "Working directory: $BURP_DIR"

GDRIVE_ID="1dr9212KN-PoYPAWI9pNa732JsvfrnDSz"
KEYGEN="BurpLoaderKeygen.jar"

# ── Download keygen ──────────────────────────────────────────────────
if is_valid_jar "${BURP_DIR}/${KEYGEN}"; then
    warn "BurpLoaderKeygen.jar already valid — skipping."
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
        echo -e "  ${YELLOW}3. Come back here and press ENTER.${NC}"
        pause
        is_valid_jar "${BURP_DIR}/${KEYGEN}" || die "BurpLoaderKeygen.jar still invalid after manual download."
    fi
fi

ok "BurpLoaderKeygen.jar is valid ✔"

# Fix ownership so real user owns the file
sudo chown "$REAL_USER":"$REAL_USER" "${BURP_DIR}/${KEYGEN}" 2>/dev/null || true

# ── Choose BurpSuite version ─────────────────────────────────────────
echo ""
echo -e "${BOLD}${YELLOW}Which BurpSuite Pro version do you need?${NC}"
echo ""
echo -e "  ${CYAN}1)${NC}  v2023.3.3   ${YELLOW}(recommended — more compatible with keygen)${NC}"
echo -e "  ${CYAN}2)${NC}  v2025.12.3  ${YELLOW}(latest)${NC}"
echo ""
read -rp "  Enter choice [1 or 2]: " VER_CHOICE

case "$VER_CHOICE" in
    2)
        BURP_VER="2025.12.3"
        BURP_JAR="burpsuite_pro_v2025.12.3.jar"
        BURP_URL='https://portswigger.net/burp/releases/download?product=pro&version=2025.12.3&type=Jar'
        ;;
    *)
        warn "Using v2023.3.3 (default)"
        BURP_VER="2023.3.3"
        BURP_JAR="burpsuite_pro_v2023.3.3.jar"
        BURP_URL='https://portswigger.net/burp/releases/download?product=pro&version=2023.3.3&type=Jar'
        ;;
esac

# ── Download BurpSuite jar ────────────────────────────────────────────
if is_valid_jar "${BURP_DIR}/${BURP_JAR}"; then
    warn "$BURP_JAR already valid — skipping."
else
    rm -f "${BURP_DIR}/${BURP_JAR}"
    info "Downloading BurpSuite Pro v${BURP_VER} (large file, please wait)..."
    wget --no-check-certificate --tries=5 --timeout=300 -c \
         "$BURP_URL" -O "${BURP_DIR}/${BURP_JAR}" \
    || die "BurpSuite Pro download failed."
    is_valid_jar "${BURP_DIR}/${BURP_JAR}" || die "BurpSuite jar is invalid. Try re-running."
    ok "BurpSuite Pro v${BURP_VER} ready!"
fi

sudo chown "$REAL_USER":"$REAL_USER" "${BURP_DIR}/${BURP_JAR}" 2>/dev/null || true
sudo chown "$REAL_USER":"$REAL_USER" "$BURP_DIR" 2>/dev/null || true

echo ""
ok "Files in $BURP_DIR :"
ls -lh "$BURP_DIR"
pause


# ════════════════════════════════════════════════════════════════════
#  STEP 03 ── Run Keygen & Activate BurpSuite
#
#  KEY FIX: keygen is launched as REAL USER (not root)
#  so that:
#    ✔ GUI display works correctly
#    ✔ BurpSuite config/license saved to real user's home
#    ✔ The "Run" button in keygen properly launches BurpSuite
#    ✔ License key is accepted
#    ✔ Manual Activation appears correctly
# ════════════════════════════════════════════════════════════════════
step "STEP 03 ── Activation (running as: $REAL_USER)"

echo -e "${BOLD}${YELLOW}READ CAREFULLY before pressing ENTER:${NC}"
echo ""
echo -e "  ${CYAN} 1.${NC}  The ${BOLD}BurpLoader Keygen${NC} GUI window opens."
echo -e "  ${CYAN} 2.${NC}  ${BOLD}Copy${NC} the License Key shown in the keygen."
echo -e "  ${CYAN} 3.${NC}  Click ${BOLD}[ Run ]${NC} in the keygen"
echo -e "        → This launches BurpSuite with the javaagent patch applied."
echo -e "        → ${RED}${BOLD}Do NOT open BurpSuite manually — use the keygen's Run button only.${NC}"
echo ""
echo -e "  ${CYAN} 4.${NC}  In BurpSuite: click ${BOLD}Next${NC} past the welcome screen."
echo -e "  ${CYAN} 5.${NC}  Paste the ${BOLD}License Key${NC} → click ${BOLD}Next${NC}."
echo -e "  ${CYAN} 6.${NC}  It tries online activation → ${BOLD}wait for it to fail${NC} (or click ${BOLD}Manual Activation${NC})."
echo -e "        ${YELLOW}If Manual Activation is not visible:${NC}"
echo -e "        → Click ${BOLD}Back${NC} → click ${BOLD}Next${NC} again → it will show ${BOLD}Manual Activation${NC}."
echo -e "  ${CYAN} 7.${NC}  Copy the ${BOLD}Activation Request${NC} text from BurpSuite."
echo -e "  ${CYAN} 8.${NC}  Paste it into the ${BOLD}Activation Request${NC} box in the Keygen."
echo -e "  ${CYAN} 9.${NC}  The Keygen shows an ${BOLD}Activation Response${NC} — copy it."
echo -e "  ${CYAN}10.${NC}  Back in BurpSuite: click ${BOLD}[ Paste Response ]${NC} → paste → click ${BOLD}Next / OK${NC}."
echo -e "  ${CYAN}11.${NC}  ${GREEN}${BOLD}BurpSuite Pro is activated! ✔${NC}"
echo ""
echo -e "${YELLOW}Launch the keygen now?${NC}"
pause

# ── FIRST RUN: as real user ──────────────────────────────────────────
cd "$BURP_DIR"
info "Starting BurpLoaderKeygen as user: $REAL_USER"
as_user java -jar "${BURP_DIR}/${KEYGEN}"

echo ""
echo -e "${BOLD}${GREEN}Press ENTER only after BurpSuite Pro is fully activated.${NC}"
pause

# ── SECOND RUN: get the loader command ──────────────────────────────
echo -e "${BOLD}${YELLOW}Now we open the keygen again to get the Loader Command.${NC}"
echo -e "${YELLOW}When it opens — look for the ${BOLD}Loader Command${NC}${YELLOW} field and copy it.${NC}"
echo -e "${YELLOW}Then close the keygen and come back here.${NC}"
pause

info "Starting BurpLoaderKeygen (2nd run — copy Loader Command)..."
as_user java -jar "${BURP_DIR}/${KEYGEN}"

echo ""
echo -e "${BOLD}${YELLOW}Paste the Loader Command you copied:${NC}"
echo -e "${CYAN}  (example: java -javaagent:${BURP_DIR}/BurpLoaderKeygen.jar=... -jar ${BURP_DIR}/${BURP_JAR})${NC}"
echo ""
read -rp "  Loader Command: " LOADER_CMD

if [ -z "$LOADER_CMD" ]; then
    warn "No command entered — using fallback."
    LOADER_CMD="java -javaagent:${BURP_DIR}/${KEYGEN} -jar ${BURP_DIR}/${BURP_JAR}"
fi

ok "Loader command saved."
pause


# ════════════════════════════════════════════════════════════════════
#  STEP 04 ── Create Desktop Launcher "Burp-pro"
# ════════════════════════════════════════════════════════════════════
step "STEP 04 ── Creating Desktop Launcher: Burp-pro"

ICON_DIR="${REAL_HOME}/.local/share/icons"
as_user mkdir -p "$ICON_DIR"
ICON_PATH="${ICON_DIR}/burpsuite.png"

# ── Extract icon from BurpSuite jar (NEVER touch keygen) ────────────
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

# ── Fallback: download icon ──────────────────────────────────────────
if [ ! -s "$ICON_PATH" ]; then
    info "Downloading icon..."
    curl -sL --max-time 15 \
         "https://portswigger.net/favicon.ico" \
         -o "${ICON_DIR}/burpsuite.ico" 2>/dev/null || true

    if command -v convert &>/dev/null && [ -s "${ICON_DIR}/burpsuite.ico" ]; then
        convert "${ICON_DIR}/burpsuite.ico[0]" "$ICON_PATH" 2>/dev/null \
            && ok "Icon converted."
    fi
fi

[ ! -s "$ICON_PATH" ] \
    && { warn "No icon — using system default."; ICON_PATH="application-x-java"; } \
    || { ok "Icon: $ICON_PATH"; sudo chown "$REAL_USER":"$REAL_USER" "$ICON_PATH" 2>/dev/null || true; }

# ── Write .desktop file as real user ────────────────────────────────
DESKTOP_DIR="${REAL_HOME}/Desktop"
as_user mkdir -p "$DESKTOP_DIR"
DESKTOP="${DESKTOP_DIR}/Burp-pro.desktop"

as_user bash -c "cat > '${DESKTOP}'" << EOF
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

# GNOME trust
as_user gio set "$DESKTOP" metadata::trusted true 2>/dev/null || true

# KDE applications menu
KDE_APPS="${REAL_HOME}/.local/share/applications"
as_user mkdir -p "$KDE_APPS"
cp "$DESKTOP" "${KDE_APPS}/Burp-pro.desktop" 2>/dev/null || true

ok "Desktop launcher created: $DESKTOP"


# ════════════════════════════════════════════════════════════════════
#  ALL DONE
# ════════════════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║              ✔   Setup Complete!                         ║"
echo "  ╠══════════════════════════════════════════════════════════╣"
printf "  ║  %-56s║\n" "  Distro       : $DISTRO"
printf "  ║  %-56s║\n" "  Real User    : $REAL_USER"
printf "  ║  %-56s║\n" "  Java         : $(java -version 2>&1 | head -1)"
printf "  ║  %-56s║\n" "  BurpSuite    : v${BURP_VER}"
printf "  ║  %-56s║\n" "  Files        : $BURP_DIR"
printf "  ║  %-56s║\n" "  Launcher     : $DESKTOP"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  ${GREEN}Double-click ${BOLD}Burp-pro${NC}${GREEN} on your Desktop to launch! 🎯${NC}"
echo ""
