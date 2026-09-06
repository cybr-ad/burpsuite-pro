#!/bin/bash

# ╔══════════════════════════════════════════════════════════════╗
# ║          BurpSuite Pro - Full Auto Setup Script              ║
# ║          Follows instructions.txt step by step               ║
# ╚══════════════════════════════════════════════════════════════╝

# ── Colors ───────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────
print_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "  ╔══════════════════════════════════════════════════════╗"
    echo "  ║         BurpSuite Pro ─ Auto Setup Script            ║"
    echo "  ╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_step() {
    echo ""
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${GREEN}  $1${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

info()    { echo -e "${CYAN}[INFO]${NC}    $1"; }
success() { echo -e "${GREEN}[  ✔  ]${NC}  $1"; }
warn()    { echo -e "${YELLOW}[  !  ]${NC}  $1"; }
error()   { echo -e "${RED}[  ✘  ]${NC}  $1"; }
pause()   { echo -e "\n${YELLOW}Press ENTER to continue...${NC}"; read; }


# ════════════════════════════════════════════════════════════════
#  STEP 01 ── Install JDK 25
# ════════════════════════════════════════════════════════════════
print_banner
print_step "STEP 01 ── Downloading & Installing JDK 25"

cd ~
mkdir -p java
cd java

info "Downloading JDK 25 (.deb) from Oracle..."
wget https://download.oracle.com/java/25/latest/jdk-25_linux-x64_bin.deb

info "Installing JDK 25 package..."
sudo dpkg -i *.deb

echo ""
echo -e "${YELLOW}${BOLD}ACTION REQUIRED:${NC}"
echo -e "  The list below shows all Java installations on your system."
echo -e "  Please ${BOLD}select the OpenJDK 25${NC} option (type its number and hit ENTER)."
echo ""
sudo update-alternatives --config java

echo ""
info "Verifying Java version..."
java --version

success "JDK 25 installed and configured!"
pause


# ════════════════════════════════════════════════════════════════
#  STEP 02 ── Download BurpSuite Pro & Keygen
# ════════════════════════════════════════════════════════════════
print_step "STEP 02 ── Setting Up BurpSuite Pro Files"

BURP_DIR="$HOME/Documents/burp"
info "Creating directory: $BURP_DIR"
mkdir -p "$BURP_DIR"
cd "$BURP_DIR"

# ── Download Keygen from Google Drive ───────────────────────────
GDRIVE_FILE_ID="1dr9212KN-PoYPAWI9pNa732JsvfrnDSz"
KEYGEN_FILE="BurpLoaderKeygen.jar"

info "Downloading BurpLoaderKeygen.jar from Google Drive..."

# Step 1: Fetch page and save cookies (handles virus-scan warning for large files)
wget --quiet \
     --save-cookies /tmp/gdrive_cookies.txt \
     --keep-session-cookies \
     --no-check-certificate \
     "https://docs.google.com/uc?export=download&id=${GDRIVE_FILE_ID}" \
     -O /tmp/gdrive_tmp.html

# Step 2: Extract confirmation token if present (for large-file virus warning)
CONFIRM_TOKEN=$(grep -o 'confirm=[^&"]*' /tmp/gdrive_tmp.html | head -1 | cut -d= -f2)

if [ -n "$CONFIRM_TOKEN" ]; then
    info "Virus-scan confirmation token found. Proceeding with confirmed download..."
    wget --load-cookies /tmp/gdrive_cookies.txt \
         --no-check-certificate \
         "https://docs.google.com/uc?export=download&confirm=${CONFIRM_TOKEN}&id=${GDRIVE_FILE_ID}" \
         -O "$KEYGEN_FILE"
else
    info "No confirmation token needed. Downloading directly..."
    wget --load-cookies /tmp/gdrive_cookies.txt \
         --no-check-certificate \
         "https://docs.google.com/uc?export=download&id=${GDRIVE_FILE_ID}" \
         -O "$KEYGEN_FILE"
fi

rm -f /tmp/gdrive_cookies.txt /tmp/gdrive_tmp.html

if [ ! -f "$KEYGEN_FILE" ] || [ ! -s "$KEYGEN_FILE" ]; then
    error "Failed to download $KEYGEN_FILE. Please check your internet connection."
    exit 1
fi
success "BurpLoaderKeygen.jar downloaded!"

# ── Ask User Which BurpSuite Version ────────────────────────────
echo ""
echo -e "${BOLD}${YELLOW}Which BurpSuite Pro version do you want?${NC}"
echo ""
echo -e "  ${CYAN}1)${NC}  BurpSuite Pro  v2023.3.3  ${YELLOW}(stable / older)${NC}"
echo -e "  ${CYAN}2)${NC}  BurpSuite Pro  v2025.12.3 ${YELLOW}(latest)${NC}"
echo ""
read -p "  Enter your choice [1 or 2]: " VERSION_CHOICE

case "$VERSION_CHOICE" in
    1)
        BURP_VERSION="2023.3.3"
        BURP_JAR="burpsuite_pro_v2023.3.3.jar"
        BURP_URL="https://portswigger.net/burp/releases/download?product=pro&version=2023.3.3&type=Jar"
        ;;
    2)
        BURP_VERSION="2025.12.3"
        BURP_JAR="burpsuite_pro_v2025.12.3.jar"
        BURP_URL="https://portswigger.net/burp/releases/download?product=pro&version=2025.12.3&type=Jar"
        ;;
    *)
        warn "Invalid choice. Defaulting to v2023.3.3"
        BURP_VERSION="2023.3.3"
        BURP_JAR="burpsuite_pro_v2023.3.3.jar"
        BURP_URL="https://portswigger.net/burp/releases/download?product=pro&version=2023.3.3&type=Jar"
        ;;
esac

info "Downloading BurpSuite Pro v${BURP_VERSION}..."
wget "$BURP_URL" -O "$BURP_JAR"

if [ ! -f "$BURP_JAR" ] || [ ! -s "$BURP_JAR" ]; then
    error "BurpSuite Pro download failed."
    exit 1
fi
success "BurpSuite Pro v${BURP_VERSION} downloaded to $BURP_DIR/"
pause


# ════════════════════════════════════════════════════════════════
#  STEP 03 ── Run Keygen & Activate BurpSuite Manually
# ════════════════════════════════════════════════════════════════
print_step "STEP 03 ── Running Keygen & Activating BurpSuite Pro"

echo -e "${BOLD}${YELLOW}Follow these steps carefully after the Keygen window opens:${NC}"
echo ""
echo -e "  ${CYAN} 1.${NC}  The ${BOLD}BurpLoader Keygen${NC} GUI window will appear."
echo -e "  ${CYAN} 2.${NC}  ${BOLD}Copy${NC} the License Key shown in the keygen."
echo -e "  ${CYAN} 3.${NC}  Click the ${BOLD}[ Run ]${NC} button in the keygen  ─→  BurpSuite launches."
echo -e "  ${CYAN} 4.${NC}  In BurpSuite: click ${BOLD}Next / OK${NC} through the welcome dialogs."
echo -e "  ${CYAN} 5.${NC}  Paste the ${BOLD}License Key${NC} and click ${BOLD}Next${NC}."
echo -e "  ${CYAN} 6.${NC}  If ${BOLD}Manual Activation${NC} is not shown:"
echo -e "            → Go ${BOLD}Back${NC}, click ${BOLD}Next${NC} again, paste the License Key."
echo -e "  ${CYAN} 7.${NC}  You will see an ${BOLD}Activation Request${NC} text — ${BOLD}copy it${NC}."
echo -e "  ${CYAN} 8.${NC}  Paste it into the ${BOLD}Activation Request${NC} field in the Keygen window."
echo -e "  ${CYAN} 9.${NC}  The keygen gives you an ${BOLD}Activation Response${NC} — ${BOLD}copy it${NC}."
echo -e "  ${CYAN}10.${NC}  Back in BurpSuite: click ${BOLD}[ Paste Response ]${NC}, paste it, click ${BOLD}Next / OK${NC}."
echo -e "  ${CYAN}11.${NC}  ${GREEN}${BOLD}BurpSuite Pro is now activated!${NC}"
echo ""
echo -e "${YELLOW}The keygen will launch now. Complete all steps above, then return here.${NC}"
pause

cd "$BURP_DIR"
java -jar "$KEYGEN_FILE"

# ── Collect Loader Command ───────────────────────────────────────
echo ""
echo -e "${BOLD}${YELLOW}ACTION REQUIRED:${NC}"
echo -e "  After activation, the Keygen window shows a ${BOLD}Loader Command${NC}."
echo -e "  It looks like:"
echo -e "  ${CYAN}  java -javaagent:/home/user/Documents/burp/BurpLoaderKeygen.jar=... -jar /path/burpsuite.jar${NC}"
echo ""
read -p "  Paste the Loader Command here: " LOADER_COMMAND

if [ -z "$LOADER_COMMAND" ]; then
    warn "No loader command entered. Using generic fallback."
    LOADER_COMMAND="java -javaagent:${BURP_DIR}/${KEYGEN_FILE} -jar ${BURP_DIR}/${BURP_JAR}"
fi

success "Loader command saved."
pause


# ════════════════════════════════════════════════════════════════
#  STEP 04 ── Create Desktop Launcher (Burp-pro)
# ════════════════════════════════════════════════════════════════
print_step "STEP 04 ── Creating Desktop Launcher: Burp-pro"

ICON_DIR="$HOME/.local/share/icons"
mkdir -p "$ICON_DIR"
ICON_PATH="${ICON_DIR}/burpsuite.png"

# ── Try to extract icon from BurpSuite jar ───────────────────────
info "Extracting BurpSuite icon from jar..."
if command -v unzip &>/dev/null; then
    ICON_INSIDE=$(unzip -l "${BURP_DIR}/${BURP_JAR}" 2>/dev/null \
        | grep -iE '\.png' \
        | grep -iE 'burp|icon|logo|splash' \
        | awk '{print $NF}' \
        | head -1)
    if [ -n "$ICON_INSIDE" ]; then
        unzip -p "${BURP_DIR}/${BURP_JAR}" "$ICON_INSIDE" > "$ICON_PATH" 2>/dev/null \
            && success "Icon extracted: $ICON_INSIDE" \
            || warn "Icon extraction failed."
    fi
fi

# ── Fallback: download a BurpSuite icon ─────────────────────────
if [ ! -s "$ICON_PATH" ]; then
    info "Trying to download icon from web..."
    wget -q "https://portswigger.net/favicon.ico" -O "${ICON_DIR}/burpsuite.ico" 2>/dev/null || true
    # Convert .ico to .png if convert is available
    if command -v convert &>/dev/null && [ -s "${ICON_DIR}/burpsuite.ico" ]; then
        convert "${ICON_DIR}/burpsuite.ico" "$ICON_PATH" 2>/dev/null && success "Icon converted from .ico"
    fi
fi

if [ ! -s "$ICON_PATH" ]; then
    warn "Could not obtain icon. Using system fallback icon."
    ICON_PATH="application-x-java"
else
    success "Icon ready: $ICON_PATH"
fi

# ── Write .desktop launcher ──────────────────────────────────────
DESKTOP_FILE="$HOME/Desktop/Burp-pro.desktop"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Burp-pro
GenericName=BurpSuite Professional
Comment=BurpSuite Pro v${BURP_VERSION} - Web Security Testing
Exec=${LOADER_COMMAND}
Icon=${ICON_PATH}
Terminal=false
Categories=Security;Network;Development;
Keywords=burpsuite;security;web;proxy;pentest;
StartupNotify=true
StartupWMClass=burp-StartBurp
EOF

chmod +x "$DESKTOP_FILE"

# Trust the .desktop file (GNOME)
if command -v gio &>/dev/null; then
    gio set "$DESKTOP_FILE" metadata::trusted true 2>/dev/null || true
fi

success "Desktop launcher created: $DESKTOP_FILE"


# ════════════════════════════════════════════════════════════════
#  ALL DONE
# ════════════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║              ✔   Setup Complete!                     ║"
echo "  ╠══════════════════════════════════════════════════════╣"
printf "  ║  %-52s║\n" "  JDK 25              → Installed & Configured"
printf "  ║  %-52s║\n" "  BurpLoaderKeygen    → Downloaded (Google Drive)"
printf "  ║  %-52s║\n" "  BurpSuite Pro v${BURP_VERSION}   → Downloaded"
printf "  ║  %-52s║\n" "  Activation          → Completed (Manual)"
printf "  ║  %-52s║\n" "  Desktop Launcher    → Burp-pro  (on Desktop)"
echo "  ╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  ${GREEN}You can now launch BurpSuite Pro directly from your Desktop! 🎯${NC}"
echo ""
