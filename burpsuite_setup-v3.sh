#!/bin/bash

# ╔══════════════════════════════════════════════════════════════════╗
# ║        BurpSuite Pro ─ Universal Setup Script v3                 ║
# ║        Supports: Debian · Ubuntu · Kali · Fedora · Arch          ║
# ╚══════════════════════════════════════════════════════════════════╝

# ── Colors ──────────────────────────────────────────────────────────
RED='\033[0;31m';  GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m';  BOLD='\033[1m'; NC='\033[0m'

# ── Print Helpers ────────────────────────────────────────────────────
banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    echo "  ║       BurpSuite Pro ─ Universal Setup Script             ║"
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

# ── Validate a downloaded file is a real JAR (ZIP magic bytes: PK) ──
is_valid_jar() {
    local f="$1"
    [ ! -f "$f" ] || [ ! -s "$f" ] && return 1
    # First 2 bytes of every ZIP/JAR must be "PK"
    local magic
    magic=$(head -c 2 "$f" 2>/dev/null)
    [ "$magic" = "PK" ] && return 0
    return 1
}

# ── Download from Google Drive (3 methods + validation) ─────────────
gdrive_download() {
    local id="$1"
    local out="$2"

    # Method 1 — gdown via pip3
    info "  [Method 1] gdown (pip3)..."
    if pip3 install -q gdown 2>/dev/null; then
        python3 -m gdown "https://drive.google.com/uc?id=${id}" -O "$out" 2>/dev/null
        if is_valid_jar "$out"; then ok "  gdown succeeded."; return 0; fi
    fi
    rm -f "$out"

    # Method 2 — curl with drive.usercontent.google.com
    info "  [Method 2] curl drive.usercontent.google.com..."
    curl -L \
         --silent --show-error \
         --max-time 180 \
         --retry 3 \
         "https://drive.usercontent.google.com/download?id=${id}&export=download&authuser=0&confirm=t" \
         -o "$out" 2>/dev/null
    if is_valid_jar "$out"; then ok "  curl method succeeded."; return 0; fi
    rm -f "$out"

    # Method 3 — wget classic with cookie/confirm token
    info "  [Method 3] wget cookie/token method..."
    wget --quiet \
         --no-check-certificate \
         --save-cookies /tmp/gd_ck.txt \
         --keep-session-cookies \
         "https://docs.google.com/uc?export=download&id=${id}" \
         -O /tmp/gd_page.html 2>/dev/null

    local token
    token=$(grep -o 'confirm=[^&"]*' /tmp/gd_page.html 2>/dev/null \
            | head -1 | cut -d= -f2)
    [ -z "$token" ] && token="t"

    wget --no-check-certificate \
         --load-cookies /tmp/gd_ck.txt \
         "https://docs.google.com/uc?export=download&confirm=${token}&id=${id}" \
         -O "$out" 2>/dev/null

    rm -f /tmp/gd_ck.txt /tmp/gd_page.html

    if is_valid_jar "$out"; then ok "  wget method succeeded."; return 0; fi
    rm -f "$out"

    return 1   # all methods failed
}


# ════════════════════════════════════════════════════════════════════
#  PRE-FLIGHT ── Detect distro & install dependencies
# ════════════════════════════════════════════════════════════════════
banner
step "PRE-FLIGHT ── Detecting System & Dependencies"

DISTRO=$(grep -oP '(?<=^ID=).+' /etc/os-release 2>/dev/null | tr -d '"' || echo "unknown")
info "Detected distro: $DISTRO"

if   command -v apt-get &>/dev/null; then
    info "Package manager: apt"
    sudo apt-get update -qq
    sudo apt-get install -y wget curl ca-certificates unzip python3-pip 2>/dev/null
    sudo update-ca-certificates -f 2>/dev/null || true
elif command -v dnf &>/dev/null; then
    info "Package manager: dnf"
    sudo dnf install -y wget curl ca-certificates unzip python3-pip 2>/dev/null
elif command -v yum &>/dev/null; then
    info "Package manager: yum"
    sudo yum install -y wget curl ca-certificates unzip python3-pip 2>/dev/null
elif command -v pacman &>/dev/null; then
    info "Package manager: pacman"
    sudo pacman -S --noconfirm wget curl ca-certificates unzip python-pip 2>/dev/null
else
    warn "Unknown package manager. Assuming dependencies are installed."
fi

ok "Dependencies ready."


# ════════════════════════════════════════════════════════════════════
#  STEP 01 ── Install JDK 25
#  Exact commands from instructions.txt:
#    cd && mkdir java && cd java && wget <url>
#    dpkg -i *.deb
#    update-alternatives --config java  → select OpenJDK 25
#    java --version
# ════════════════════════════════════════════════════════════════════
step "STEP 01 ── Downloading & Installing JDK 25"

# ── Check if Java 25 already present ────────────────────────────────
CURRENT_JAVA=$(java -version 2>&1 | grep -oP '\d+' | head -1 2>/dev/null || echo "0")
if [ "$CURRENT_JAVA" -ge 25 ] 2>/dev/null; then
    ok "Java $CURRENT_JAVA is already installed — skipping download."
    java --version
else
    info "Java 25 not found. Starting download..."
    cd ~
    mkdir -p java
    cd java

    info "Downloading JDK 25 from Oracle (this may take a few minutes)..."
    wget --no-check-certificate \
         --tries=5 \
         --timeout=120 \
         -c \
         "https://download.oracle.com/java/25/latest/jdk-25_linux-x64_bin.deb" \
    || die "JDK 25 download failed. Check your internet connection."

    info "Installing JDK 25..."
    sudo dpkg -i *.deb
    # Fix any broken dependencies
    sudo apt-get install -f -y 2>/dev/null || true

    cd ~
fi

# ── Configure alternatives ───────────────────────────────────────────
echo ""
echo -e "${BOLD}${YELLOW}ACTION: Select the OpenJDK 25 entry from the list below.${NC}"
echo -e "${YELLOW}        Type its number and press ENTER.${NC}"
echo ""
sudo update-alternatives --config java

echo ""
info "Confirming Java installation..."
java --version
ok "JDK 25 configured successfully!"
pause


# ════════════════════════════════════════════════════════════════════
#  STEP 02 ── Create ~/Documents/burp & Download Files
#  Exact flow from instructions.txt:
#    mkdir ~/Documents/burp && cd ~/Documents/burp
#    download keygen from Google Drive
#    ask user for version, then download burpsuite jar
# ════════════════════════════════════════════════════════════════════
step "STEP 02 ── Downloading BurpSuite Pro Files"

BURP_DIR="$HOME/Documents/burp"
mkdir -p "$BURP_DIR"
cd "$BURP_DIR"
info "Working directory: $BURP_DIR"

# ── Download BurpLoaderKeygen.jar from Google Drive ─────────────────
GDRIVE_ID="1dr9212KN-PoYPAWI9pNa732JsvfrnDSz"
KEYGEN="BurpLoaderKeygen.jar"

if is_valid_jar "$KEYGEN"; then
    warn "BurpLoaderKeygen.jar already exists and is valid — skipping download."
else
    rm -f "$KEYGEN"   # remove any broken/partial file
    info "Downloading BurpLoaderKeygen.jar from Google Drive..."
    gdrive_download "$GDRIVE_ID" "$KEYGEN" \
        || die "All download methods failed for BurpLoaderKeygen.jar.
       Please download it manually from:
       https://drive.google.com/file/d/${GDRIVE_ID}/view
       Place it in: $BURP_DIR"
    ok "BurpLoaderKeygen.jar is valid and ready!"
fi

# ── Ask user which BurpSuite version ────────────────────────────────
echo ""
echo -e "${BOLD}${YELLOW}Which BurpSuite Pro version do you need?${NC}"
echo ""
echo -e "  ${CYAN}1)${NC}  v2023.3.3   ${YELLOW}(older — more compatible with keygen)${NC}"
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
        warn "Defaulting to v2023.3.3"
        BURP_VER="2023.3.3"
        BURP_JAR="burpsuite_pro_v2023.3.3.jar"
        BURP_URL='https://portswigger.net/burp/releases/download?product=pro&version=2023.3.3&type=Jar'
        ;;
esac

# ── Download BurpSuite Pro jar ───────────────────────────────────────
if is_valid_jar "$BURP_JAR"; then
    warn "$BURP_JAR already exists and is valid — skipping download."
else
    rm -f "$BURP_JAR"
    info "Downloading BurpSuite Pro v${BURP_VER} (this is a large file)..."
    wget --no-check-certificate \
         --tries=5 \
         --timeout=300 \
         -c \
         "$BURP_URL" -O "$BURP_JAR" \
    || die "BurpSuite Pro download failed."

    is_valid_jar "$BURP_JAR" || die "Downloaded file is not a valid JAR. Try again."
    ok "BurpSuite Pro v${BURP_VER} downloaded and validated!"
fi

echo ""
ok "All files ready in: $BURP_DIR"
ls -lh "$BURP_DIR"
pause


# ════════════════════════════════════════════════════════════════════
#  STEP 03 ── Run Keygen & Activate BurpSuite
#  From instructions.txt:
#    1. java -jar BurpLoaderKeygen.jar
#    2. wait for user to finish activation
#    3. java -jar BurpLoaderKeygen.jar  (again) → copy loader command
# ════════════════════════════════════════════════════════════════════
step "STEP 03 ── Activation"

cd "$BURP_DIR"

echo -e "${BOLD}${YELLOW}The Keygen will open now.${NC}"
echo -e "${YELLOW}Complete the BurpSuite activation using the keygen GUI,${NC}"
echo -e "${YELLOW}then come back to this terminal and press ENTER.${NC}"
pause

# ── First run: activation ────────────────────────────────────────────
info "Launching BurpLoaderKeygen (1st run — for activation)..."
java -jar "$KEYGEN"

echo ""
echo -e "${BOLD}${GREEN}When BurpSuite Pro is fully activated, press ENTER to continue.${NC}"
pause

# ── Second run: copy the loader command ─────────────────────────────
echo -e "${BOLD}${YELLOW}Launching BurpLoaderKeygen again (2nd run — to get the Loader Command).${NC}"
echo -e "${YELLOW}Look for the ${BOLD}Loader Command${YELLOW} in the keygen window and copy it.${NC}"
echo -e "${YELLOW}Then close the keygen and come back here.${NC}"
pause

info "Launching BurpLoaderKeygen (2nd run — copy the Loader Command)..."
java -jar "$KEYGEN"

echo ""
echo -e "${BOLD}${YELLOW}Paste the Loader Command you copied from the keygen:${NC}"
echo -e "${CYAN}  (looks like: java -javaagent:${BURP_DIR}/BurpLoaderKeygen.jar=... -jar ${BURP_DIR}/${BURP_JAR})${NC}"
echo ""
read -rp "  Loader Command: " LOADER_CMD

if [ -z "$LOADER_CMD" ]; then
    warn "No command entered. Using auto-generated fallback."
    LOADER_CMD="java -javaagent:${BURP_DIR}/${KEYGEN} -jar ${BURP_DIR}/${BURP_JAR}"
fi

ok "Loader command captured."
pause


# ════════════════════════════════════════════════════════════════════
#  STEP 04 ── Create Desktop Launcher named "Burp-pro"
#  From instructions.txt:
#    create launcher named Burp-pro
#    paste loader command
#    set icon of burpsuite
#    save to desktop
# ════════════════════════════════════════════════════════════════════
step "STEP 04 ── Creating Desktop Launcher: Burp-pro"

ICON_DIR="$HOME/.local/share/icons"
mkdir -p "$ICON_DIR"
ICON_PATH="${ICON_DIR}/burpsuite.png"

# ── Extract icon from BurpSuite jar only (NEVER touch keygen) ───────
if ! is_valid_jar "$ICON_PATH" 2>/dev/null && command -v unzip &>/dev/null; then
    info "Extracting icon from BurpSuite jar..."
    ICON_ENTRY=$(unzip -l "${BURP_DIR}/${BURP_JAR}" 2>/dev/null \
        | grep -iE '\.png' \
        | grep -iE 'burp|icon|logo|media|splash' \
        | awk '{print $NF}' | head -1)
    if [ -n "$ICON_ENTRY" ]; then
        unzip -p "${BURP_DIR}/${BURP_JAR}" "$ICON_ENTRY" > "$ICON_PATH" 2>/dev/null \
            && ok "Icon extracted from jar: $ICON_ENTRY" \
            || rm -f "$ICON_PATH"
    fi
fi

# ── Fallback icon download ───────────────────────────────────────────
if [ ! -s "$ICON_PATH" ]; then
    info "Downloading BurpSuite icon..."
    curl -sL --max-time 15 \
         "https://portswigger.net/favicon.ico" \
         -o "${ICON_DIR}/burpsuite.ico" 2>/dev/null || true

    if command -v convert &>/dev/null && [ -s "${ICON_DIR}/burpsuite.ico" ]; then
        convert "${ICON_DIR}/burpsuite.ico[0]" "$ICON_PATH" 2>/dev/null && ok "Icon ready."
    fi
fi

[ ! -s "$ICON_PATH" ] \
    && { warn "No icon found. Using system default."; ICON_PATH="application-x-java"; } \
    || ok "Icon: $ICON_PATH"

# ── Write .desktop launcher ──────────────────────────────────────────
mkdir -p "$HOME/Desktop"
DESKTOP="$HOME/Desktop/Burp-pro.desktop"

cat > "$DESKTOP" << EOF
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

# GNOME: mark trusted
command -v gio &>/dev/null \
    && gio set "$DESKTOP" metadata::trusted true 2>/dev/null || true

# KDE: also install to applications menu
if [ -d "$HOME/.local/share/applications" ]; then
    cp "$DESKTOP" "$HOME/.local/share/applications/Burp-pro.desktop"
fi

ok "Desktop launcher saved: $DESKTOP"


# ════════════════════════════════════════════════════════════════════
#  DONE
# ════════════════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║              ✔   All Done!                               ║"
echo "  ╠══════════════════════════════════════════════════════════╣"
printf "  ║  %-56s║\n" "  Distro        : $DISTRO"
printf "  ║  %-56s║\n" "  Java          : $(java -version 2>&1 | head -1)"
printf "  ║  %-56s║\n" "  BurpSuite     : v${BURP_VER}"
printf "  ║  %-56s║\n" "  Files in      : $BURP_DIR"
printf "  ║  %-56s║\n" "  Launcher      : $DESKTOP"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  ${GREEN}Double-click ${BOLD}Burp-pro${NC}${GREEN} on your Desktop to launch BurpSuite Pro! 🎯${NC}"
echo ""
