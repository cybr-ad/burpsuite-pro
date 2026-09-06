#!/bin/bash

# ╔══════════════════════════════════════════════════════════════════╗
# ║        BurpSuite Pro ─ Universal Setup Script                    ║
# ║        Supports: Debian · Ubuntu · Kali · Fedora · Arch          ║
# ║        Fixes: SSL certs · Google Drive · Java detection          ║
# ╚══════════════════════════════════════════════════════════════════╝

# ── Colors ─────────────────────────────────────────────────────────
RED='\033[0;31m';  GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m';  BOLD='\033[1m'; NC='\033[0m'

# ── Print Helpers ───────────────────────────────────────────────────
banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    echo "  ║       BurpSuite Pro ─ Universal Setup Script             ║"
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}
step()    { echo -e "\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n${BOLD}${GREEN}  $*${NC}\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[ ✔ ]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[ ! ]${NC}  $*"; }
err()     { echo -e "${RED}[ ✘ ]${NC}  $*"; }
pause()   { echo -e "\n${YELLOW}▶  Press ENTER to continue...${NC}"; read -r; }
die()     { err "$*"; exit 1; }

# ════════════════════════════════════════════════════════════════════
#  PRE-FLIGHT: detect distro & package manager
# ════════════════════════════════════════════════════════════════════
banner
step "PRE-FLIGHT ── Detecting System"

PKG=""
INSTALL=""
if   command -v apt-get &>/dev/null; then PKG="apt";    INSTALL="sudo apt-get install -y"
elif command -v dnf     &>/dev/null; then PKG="dnf";    INSTALL="sudo dnf install -y"
elif command -v yum     &>/dev/null; then PKG="yum";    INSTALL="sudo yum install -y"
elif command -v pacman  &>/dev/null; then PKG="pacman"; INSTALL="sudo pacman -S --noconfirm"
else die "No supported package manager found (apt/dnf/yum/pacman)."; fi

DISTRO=$(grep -oP '(?<=^ID=).+' /etc/os-release 2>/dev/null | tr -d '"' || echo "unknown")
info "Distro  : $DISTRO"
info "Pkg mgr : $PKG"

# ── Install core dependencies ────────────────────────────────────
info "Installing core dependencies (wget, curl, ca-certificates, unzip, pip3)..."
case "$PKG" in
    apt)
        sudo apt-get update -qq
        sudo apt-get install -y wget curl ca-certificates unzip \
             python3-pip openjdk-21-jdk-headless 2>/dev/null || true
        sudo update-ca-certificates
        ;;
    dnf|yum)
        $INSTALL wget curl ca-certificates unzip python3-pip 2>/dev/null || true
        ;;
    pacman)
        $INSTALL wget curl ca-certificates unzip python-pip 2>/dev/null || true
        ;;
esac
ok "Core dependencies ready."

# ════════════════════════════════════════════════════════════════════
#  STEP 01 ── Install JDK 25
# ════════════════════════════════════════════════════════════════════
step "STEP 01 ── Installing JDK 25"

# ── Check if Java 25 already installed ──────────────────────────
JAVA_VER=$(java -version 2>&1 | grep -oP '\d+' | head -1 || echo "0")
if [ "$JAVA_VER" -ge 25 ] 2>/dev/null; then
    ok "Java $JAVA_VER is already installed — skipping download."
    java --version
else
    info "Java 25 not found. Downloading from Oracle..."

    mkdir -p ~/java && cd ~/java

    # Try with SSL first; fall back to --no-check-certificate
    wget --no-check-certificate \
         --tries=3 \
         --timeout=60 \
         -c \
         "https://download.oracle.com/java/25/latest/jdk-25_linux-x64_bin.deb" \
    || die "Could not download JDK 25. Check your internet connection."

    info "Installing JDK 25 package..."
    sudo dpkg -i *.deb || sudo apt-get install -f -y

    cd ~
fi

# ── Set default Java ─────────────────────────────────────────────
echo ""
echo -e "${YELLOW}${BOLD}Select the Java 25 / OpenJDK 25 entry from the list:${NC}"
sudo update-alternatives --config java

echo ""
info "Confirming Java version..."
java --version
ok "JDK 25 configured!"
pause


# ════════════════════════════════════════════════════════════════════
#  STEP 02 ── Download Keygen + BurpSuite Pro
# ════════════════════════════════════════════════════════════════════
step "STEP 02 ── Downloading BurpSuite Files"

BURP_DIR="$HOME/Documents/burp"
mkdir -p "$BURP_DIR"
cd "$BURP_DIR"

GDRIVE_ID="1dr9212KN-PoYPAWI9pNa732JsvfrnDSz"
KEYGEN="BurpLoaderKeygen.jar"

# ── Download keygen (3 fallback methods) ────────────────────────
gdrive_download() {
    local file_id="$1"
    local output="$2"

    info "Method 1 ── gdown (pip)..."
    if pip3 install -q gdown 2>/dev/null && \
       python3 -m gdown "https://drive.google.com/uc?id=${file_id}" -O "$output" 2>/dev/null; then
        return 0
    fi

    info "Method 2 ── drive.usercontent.google.com..."
    if curl -L --silent --show-error \
            --max-time 120 \
            "https://drive.usercontent.google.com/download?id=${file_id}&export=download&authuser=0&confirm=t" \
            -o "$output" 2>/dev/null && [ -s "$output" ]; then
        return 0
    fi

    info "Method 3 ── classic docs.google.com with cookie/token..."
    wget --quiet --save-cookies /tmp/gdrive_ck.txt \
         --keep-session-cookies --no-check-certificate \
         "https://docs.google.com/uc?export=download&id=${file_id}" \
         -O /tmp/gdrive_page.html 2>/dev/null

    TOKEN=$(grep -o 'confirm=[^&"]*' /tmp/gdrive_page.html 2>/dev/null | head -1 | cut -d= -f2)
    [ -z "$TOKEN" ] && TOKEN="t"

    wget --load-cookies /tmp/gdrive_ck.txt --no-check-certificate \
         "https://docs.google.com/uc?export=download&confirm=${TOKEN}&id=${file_id}" \
         -O "$output" 2>/dev/null

    rm -f /tmp/gdrive_ck.txt /tmp/gdrive_page.html
    [ -s "$output" ] && return 0

    return 1
}

if [ -f "$KEYGEN" ] && [ -s "$KEYGEN" ]; then
    warn "BurpLoaderKeygen.jar already exists — skipping download."
else
    info "Downloading BurpLoaderKeygen.jar from Google Drive..."
    gdrive_download "$GDRIVE_ID" "$KEYGEN" \
        || die "All 3 download methods failed for keygen. Check your internet."
    ok "BurpLoaderKeygen.jar downloaded!"
fi

# ── Choose BurpSuite version ─────────────────────────────────────
echo ""
echo -e "${BOLD}${YELLOW}Which BurpSuite Pro version do you want?${NC}"
echo ""
echo -e "  ${CYAN}1)${NC}  v2023.3.3   ${YELLOW}(older, more keygen-compatible)${NC}"
echo -e "  ${CYAN}2)${NC}  v2025.12.3  ${YELLOW}(latest)${NC}"
echo ""
read -rp "  Enter choice [1 or 2]: " VER_CHOICE

case "$VER_CHOICE" in
    2)  BURP_VER="2025.12.3"
        BURP_JAR="burpsuite_pro_v2025.12.3.jar"
        BURP_URL="https://portswigger.net/burp/releases/download?product=pro&version=2025.12.3&type=Jar"
        ;;
    *)  BURP_VER="2023.3.3"
        BURP_JAR="burpsuite_pro_v2023.3.3.jar"
        BURP_URL="https://portswigger.net/burp/releases/download?product=pro&version=2023.3.3&type=Jar"
        ;;
esac

if [ -f "$BURP_JAR" ] && [ -s "$BURP_JAR" ]; then
    warn "$BURP_JAR already exists — skipping download."
else
    info "Downloading BurpSuite Pro v${BURP_VER}..."
    wget --no-check-certificate \
         --tries=3 \
         --timeout=120 \
         -c \
         "$BURP_URL" -O "$BURP_JAR" \
    || die "BurpSuite Pro download failed."
    ok "BurpSuite Pro v${BURP_VER} downloaded!"
fi

ok "All files in: $BURP_DIR"
ls -lh "$BURP_DIR"
pause


# ════════════════════════════════════════════════════════════════════
#  STEP 03 ── Run Keygen & Activate
# ════════════════════════════════════════════════════════════════════
step "STEP 03 ── Keygen & Manual Activation"

echo -e "${BOLD}${YELLOW}Follow these steps after the Keygen window opens:${NC}"
echo ""
echo -e "  ${CYAN} 1.${NC}  ${BOLD}BurpLoader Keygen${NC} window opens."
echo -e "  ${CYAN} 2.${NC}  ${BOLD}Copy${NC} the License Key from the keygen."
echo -e "  ${CYAN} 3.${NC}  Click ${BOLD}[ Run ]${NC} — BurpSuite Pro will launch."
echo -e "  ${CYAN} 4.${NC}  In BurpSuite: click ${BOLD}Next / OK${NC} through dialogs."
echo -e "  ${CYAN} 5.${NC}  Paste the ${BOLD}License Key${NC}, click ${BOLD}Next${NC}."
echo -e "  ${CYAN} 6.${NC}  ${BOLD}Manual Activation not shown?${NC}"
echo -e "            → Click ${BOLD}Back${NC} → ${BOLD}Next${NC} → paste License Key again."
echo -e "  ${CYAN} 7.${NC}  An ${BOLD}Activation Request${NC} appears — ${BOLD}copy it${NC}."
echo -e "  ${CYAN} 8.${NC}  Paste it into ${BOLD}Activation Request${NC} field in the Keygen."
echo -e "  ${CYAN} 9.${NC}  Keygen gives you an ${BOLD}Activation Response${NC} — ${BOLD}copy it${NC}."
echo -e "  ${CYAN}10.${NC}  In BurpSuite: click ${BOLD}[ Paste Response ]${NC}, paste, click ${BOLD}Next / OK${NC}."
echo -e "  ${CYAN}11.${NC}  ${GREEN}${BOLD}BurpSuite Pro is now activated! ✔${NC}"
echo ""
echo -e "${YELLOW}The Keygen will launch now. Complete all steps, then return here.${NC}"
pause

cd "$BURP_DIR"
java -jar "$KEYGEN"

# ── Capture loader command ───────────────────────────────────────
echo ""
echo -e "${BOLD}${YELLOW}After activation, look for the Loader Command in the keygen.${NC}"
echo -e "${CYAN}It looks like:${NC}"
echo -e "  java -javaagent:${BURP_DIR}/BurpLoaderKeygen.jar=... -jar ${BURP_DIR}/${BURP_JAR}"
echo ""
read -rp "  Paste the Loader Command here: " LOADER_CMD

if [ -z "$LOADER_CMD" ]; then
    warn "No command entered. Using auto-generated fallback."
    LOADER_CMD="java -javaagent:${BURP_DIR}/${KEYGEN} -jar ${BURP_DIR}/${BURP_JAR}"
fi
ok "Loader command saved."
pause


# ════════════════════════════════════════════════════════════════════
#  STEP 04 ── Create Desktop Launcher (Burp-pro)
# ════════════════════════════════════════════════════════════════════
step "STEP 04 ── Creating Desktop Launcher: Burp-pro"

ICON_DIR="$HOME/.local/share/icons"
mkdir -p "$ICON_DIR"
ICON_PATH="${ICON_DIR}/burpsuite.png"

# ── Get icon: extract from jar ───────────────────────────────────
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

# ── Get icon: download from PortSwigger ─────────────────────────
if [ ! -s "$ICON_PATH" ]; then
    info "Downloading icon..."
    curl -sL --max-time 15 \
         "https://portswigger.net/favicon.ico" \
         -o "${ICON_DIR}/burpsuite.ico" 2>/dev/null || true

    if command -v convert &>/dev/null && [ -s "${ICON_DIR}/burpsuite.ico" ]; then
        convert "${ICON_DIR}/burpsuite.ico[0]" "$ICON_PATH" 2>/dev/null \
            && ok "Icon converted from .ico."
    fi
fi

[ ! -s "$ICON_PATH" ] && { warn "No icon found. Using system fallback."; ICON_PATH="application-x-java"; } \
                       || ok "Icon ready: $ICON_PATH"

# ── Write .desktop file ──────────────────────────────────────────
DESKTOP="$HOME/Desktop/Burp-pro.desktop"
mkdir -p "$HOME/Desktop"

cat > "$DESKTOP" <<EOF
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

# Trust the launcher in GNOME
command -v gio &>/dev/null && gio set "$DESKTOP" metadata::trusted true 2>/dev/null || true

# KDE trust
if [ -d "$HOME/.local/share/applications" ]; then
    cp "$DESKTOP" "$HOME/.local/share/applications/Burp-pro.desktop"
fi

ok "Desktop launcher created: $DESKTOP"


# ════════════════════════════════════════════════════════════════════
#  ALL DONE
# ════════════════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║              ✔   Setup Complete!                         ║"
echo "  ╠══════════════════════════════════════════════════════════╣"
printf "  ║  %-56s║\n" "  Distro          : $DISTRO"
printf "  ║  %-56s║\n" "  JDK             : $(java -version 2>&1 | head -1)"
printf "  ║  %-56s║\n" "  BurpSuite Pro   : v${BURP_VER}"
printf "  ║  %-56s║\n" "  Keygen          : $BURP_DIR/$KEYGEN"
printf "  ║  %-56s║\n" "  Launcher        : $DESKTOP"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  ${GREEN}Launch BurpSuite Pro from your Desktop icon: ${BOLD}Burp-pro${NC} 🎯"
echo ""
