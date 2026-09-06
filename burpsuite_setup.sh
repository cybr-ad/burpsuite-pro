#!/bin/bash

# ╔══════════════════════════════════════════════════════════════════╗
# ║      BurpSuite Pro ─ Universal Setup Script v5 (Clean)           ║
# ║      Supports: Kali · Debian · Ubuntu · Fedora · Arch            ║
# ╚══════════════════════════════════════════════════════════════════╝

set -o pipefail

RED='\033[0;31m';  GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m';  BOLD='\033[1m'; NC='\033[0m'

step()  { echo -e "\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n${BOLD}${GREEN}  $*${NC}\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ ✔ ]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[ ! ]${NC}  $*"; }
err()   { echo -e "${RED}[ ✘ ]${NC}  $*"; }
die()   { err "$*"; exit 1; }


# ════════════════════════════════════════════════════════════════════
#  Detect real user (for when script is run with sudo)
# ════════════════════════════════════════════════════════════════════
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    REAL_USER="$SUDO_USER"
else
    REAL_USER="$(whoami)"
fi
REAL_HOME=$(eval echo "~$REAL_USER")

# Run GUI commands as the real user
run_as_user() {
    if [ "$(whoami)" = "root" ] && [ "$REAL_USER" != "root" ]; then
        sudo -u "$REAL_USER" \
             HOME="$REAL_HOME" \
             DISPLAY="${DISPLAY:-:0}" \
             XAUTHORITY="${XAUTHORITY:-$REAL_HOME/.Xauthority}" \
             "$@"
    else
        "$@"
    fi
}


# ════════════════════════════════════════════════════════════════════
#  Simple JAR check — ONLY magic bytes, nothing else
#  (Previous scripts had min-size and unzip -t which rejected
#   valid small JARs and JARs with harmless zip warnings)
# ════════════════════════════════════════════════════════════════════
is_jar() {
    local f="$1"
    [ ! -f "$f" ] && return 1
    [ ! -s "$f" ] && return 1
    local magic
    magic=$(head -c 2 "$f" 2>/dev/null || true)
    [ "$magic" = "PK" ]
}

# Show what we actually downloaded (for debugging)
debug_file() {
    local f="$1"
    if [ -f "$f" ]; then
        local sz
        sz=$(stat -c%s "$f" 2>/dev/null || echo "?")
        local first
        first=$(head -c 20 "$f" 2>/dev/null | cat -v || true)
        info "  File: $f  |  Size: ${sz} bytes  |  Starts with: ${first}"
    else
        warn "  File $f does not exist."
    fi
}


# ════════════════════════════════════════════════════════════════════
#  Google Drive download — 3 methods, errors NOT silenced
# ════════════════════════════════════════════════════════════════════
gdrive_download() {
    local fid="$1"
    local out="$2"

    # ── Method 1: gdown CLI ─────────────────────────────────────────
    info "[Method 1] gdown..."
    pip3 install gdown --break-system-packages 2>/dev/null \
        || pip3 install gdown 2>/dev/null \
        || true

    if command -v gdown &>/dev/null; then
        info "  Running: gdown 'https://drive.google.com/uc?id=${fid}' -O '$out'"
        gdown "https://drive.google.com/uc?id=${fid}" -O "$out" && true
        debug_file "$out"
        if is_jar "$out"; then ok "  gdown succeeded!"; return 0; fi
        warn "  gdown output is not a valid JAR."
    else
        warn "  gdown not available."
    fi
    rm -f "$out"

    # ── Method 2: curl (new Google Drive URL) ───────────────────────
    info "[Method 2] curl..."
    local url="https://drive.usercontent.google.com/download?id=${fid}&export=download&authuser=0&confirm=t"
    info "  URL: $url"
    curl -L --progress-bar --max-time 180 --retry 3 \
         "$url" -o "$out" && true
    debug_file "$out"
    if is_jar "$out"; then ok "  curl succeeded!"; return 0; fi
    warn "  curl output is not a valid JAR."
    rm -f "$out"

    # ── Method 3: wget with cookies ─────────────────────────────────
    info "[Method 3] wget..."
    wget --no-check-certificate \
         --save-cookies /tmp/gd_ck.txt \
         --keep-session-cookies \
         "https://docs.google.com/uc?export=download&id=${fid}" \
         -O /tmp/gd_page.html && true

    local token
    token=$(grep -o 'confirm=[^&"]*' /tmp/gd_page.html 2>/dev/null | head -1 | cut -d= -f2)
    [ -z "$token" ] && token="t"
    info "  Token: $token"

    wget --no-check-certificate \
         --load-cookies /tmp/gd_ck.txt \
         "https://docs.google.com/uc?export=download&confirm=${token}&id=${fid}" \
         -O "$out" && true

    rm -f /tmp/gd_ck.txt /tmp/gd_page.html
    debug_file "$out"
    if is_jar "$out"; then ok "  wget succeeded!"; return 0; fi
    warn "  wget output is not a valid JAR."
    rm -f "$out"

    return 1
}


# ════════════════════════════════════════════════════════════════════
#  PRE-FLIGHT
# ════════════════════════════════════════════════════════════════════
clear
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║       BurpSuite Pro ─ Universal Setup Script v5          ║"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

step "PRE-FLIGHT ── System & Dependencies"

info "User  : $(whoami)  →  Real user: $REAL_USER"
info "Home  : $REAL_HOME"

DISTRO=$(grep -oP '(?<=^ID=).+' /etc/os-release 2>/dev/null | tr -d '"' || echo "unknown")
info "Distro: $DISTRO"

if command -v apt-get &>/dev/null; then
    apt-get update -qq
    apt-get install -y wget curl ca-certificates unzip python3-pip 2>/dev/null || true
    update-ca-certificates -f 2>/dev/null || true
elif command -v dnf &>/dev/null; then
    dnf install -y wget curl ca-certificates unzip python3-pip 2>/dev/null || true
elif command -v pacman &>/dev/null; then
    pacman -S --noconfirm wget curl ca-certificates unzip python-pip 2>/dev/null || true
fi

ok "Dependencies ready."


# ════════════════════════════════════════════════════════════════════
#  STEP 01 ── JDK 25
# ════════════════════════════════════════════════════════════════════
step "STEP 01 ── JDK 25"

JAVA_VER=$(java -version 2>&1 | grep -oP '\d+' | head -1 || echo "0")

if [ "${JAVA_VER:-0}" -ge 25 ] 2>/dev/null; then
    ok "Java $JAVA_VER already installed — skipping."
    java --version
else
    info "Downloading JDK 25..."
    mkdir -p "$REAL_HOME/java"
    cd "$REAL_HOME/java"

    wget --no-check-certificate -c \
         "https://download.oracle.com/java/25/latest/jdk-25_linux-x64_bin.deb" \
    || die "JDK download failed."

    dpkg -i *.deb || apt-get install -f -y || true
    cd "$REAL_HOME"
fi

echo ""
echo -e "${YELLOW}${BOLD}Select the Java 25 entry:${NC}"
update-alternatives --config java
echo ""
java --version
ok "JDK 25 done."

echo -e "\n${YELLOW}Press ENTER...${NC}"; read -r


# ════════════════════════════════════════════════════════════════════
#  STEP 02 ── Download keygen + BurpSuite
# ════════════════════════════════════════════════════════════════════
step "STEP 02 ── Download Files"

BURP_DIR="${REAL_HOME}/Documents/burp"
mkdir -p "$BURP_DIR"
chown "$REAL_USER":"$REAL_USER" "$BURP_DIR" 2>/dev/null || true
cd "$BURP_DIR"
info "Directory: $BURP_DIR"

GDRIVE_ID="1dr9212KN-PoYPAWI9pNa732JsvfrnDSz"
KEYGEN="BurpLoaderKeygen.jar"

# ── Download keygen ──────────────────────────────────────────────
if is_jar "${BURP_DIR}/${KEYGEN}"; then
    ok "BurpLoaderKeygen.jar already exists and is a valid JAR."
else
    rm -f "${BURP_DIR}/${KEYGEN}"
    info "Downloading BurpLoaderKeygen.jar..."
    echo ""

    if ! gdrive_download "$GDRIVE_ID" "${BURP_DIR}/${KEYGEN}"; then
        echo ""
        err "Automated download failed."
        echo ""
        echo -e "  ${YELLOW}Please download it manually:${NC}"
        echo -e "  ${CYAN}1.${NC} Open in browser: ${BOLD}https://drive.google.com/file/d/${GDRIVE_ID}/view${NC}"
        echo -e "  ${CYAN}2.${NC} Save to: ${BOLD}${BURP_DIR}/BurpLoaderKeygen.jar${NC}"
        echo -e "  ${CYAN}3.${NC} Come back and press ENTER."
        echo ""
        read -r

        if ! is_jar "${BURP_DIR}/${KEYGEN}"; then
            die "BurpLoaderKeygen.jar still not found or invalid."
        fi
    fi
fi

chown "$REAL_USER":"$REAL_USER" "${BURP_DIR}/${KEYGEN}" 2>/dev/null || true
ok "Keygen ready."
echo ""

# ── Choose BurpSuite version ─────────────────────────────────────
echo -e "${BOLD}${YELLOW}Which BurpSuite Pro version?${NC}"
echo -e "  ${CYAN}1)${NC}  v2023.3.3"
echo -e "  ${CYAN}2)${NC}  v2025.12.3"
read -rp "  Choice [1/2]: " VCHOICE

case "$VCHOICE" in
    2)
        BVER="2025.12.3"
        BJAR="burpsuite_pro_v2025.12.3.jar"
        BURL='https://portswigger.net/burp/releases/download?product=pro&version=2025.12.3&type=Jar'
        ;;
    *)
        BVER="2023.3.3"
        BJAR="burpsuite_pro_v2023.3.3.jar"
        BURL='https://portswigger.net/burp/releases/download?product=pro&version=2023.3.3&type=Jar'
        ;;
esac

# ── Download BurpSuite jar ───────────────────────────────────────
if is_jar "${BURP_DIR}/${BJAR}"; then
    ok "$BJAR already exists."
else
    rm -f "${BURP_DIR}/${BJAR}"
    info "Downloading BurpSuite Pro v${BVER}..."
    wget --no-check-certificate -c "$BURL" -O "${BURP_DIR}/${BJAR}" \
        || die "BurpSuite download failed."
    is_jar "${BURP_DIR}/${BJAR}" || die "Downloaded file is not a valid JAR."
    ok "BurpSuite Pro v${BVER} downloaded."
fi

chown "$REAL_USER":"$REAL_USER" "${BURP_DIR}/${BJAR}" 2>/dev/null || true

echo ""
ok "All files:"
ls -lh "$BURP_DIR"
echo -e "\n${YELLOW}Press ENTER...${NC}"; read -r


# ════════════════════════════════════════════════════════════════════
#  STEP 03 ── Run keygen → activate → run keygen again → copy cmd
# ════════════════════════════════════════════════════════════════════
step "STEP 03 ── Activation"

cd "$BURP_DIR"

echo -e "${BOLD}${YELLOW}The keygen will open now.${NC}"
echo -e "Complete the BurpSuite activation using the keygen GUI."
echo -e "When done, ${BOLD}close${NC} the keygen and come back here."
echo -e "\n${YELLOW}Press ENTER to launch keygen...${NC}"; read -r

info "Launching BurpLoaderKeygen as: $REAL_USER"
run_as_user java -jar "${BURP_DIR}/${KEYGEN}"

echo ""
echo -e "${BOLD}${GREEN}Activation done?${NC}"
echo -e "\n${YELLOW}Press ENTER to continue...${NC}"; read -r

echo -e "${BOLD}${YELLOW}Now we open the keygen AGAIN to get the Loader Command.${NC}"
echo -e "Copy the ${BOLD}Loader Command${NC} from the keygen window."
echo -e "Then close it and come back."
echo -e "\n${YELLOW}Press ENTER to launch keygen again...${NC}"; read -r

info "Launching BurpLoaderKeygen (2nd run)..."
run_as_user java -jar "${BURP_DIR}/${KEYGEN}"

echo ""
echo -e "${BOLD}${YELLOW}Paste the Loader Command:${NC}"
read -rp "  > " LOADER_CMD

if [ -z "$LOADER_CMD" ]; then
    warn "Empty — using fallback."
    LOADER_CMD="java -javaagent:${BURP_DIR}/${KEYGEN} -jar ${BURP_DIR}/${BJAR}"
fi

ok "Saved."
echo -e "\n${YELLOW}Press ENTER...${NC}"; read -r


# ════════════════════════════════════════════════════════════════════
#  STEP 04 ── Desktop Launcher
# ════════════════════════════════════════════════════════════════════
step "STEP 04 ── Desktop Launcher"

ICON_DIR="${REAL_HOME}/.local/share/icons"
mkdir -p "$ICON_DIR"
ICON="${ICON_DIR}/burpsuite.png"

# Try to extract icon from BurpSuite jar (NEVER from keygen)
if [ ! -s "$ICON" ] && command -v unzip &>/dev/null; then
    info "Extracting icon from BurpSuite jar..."
    IENTRY=$(unzip -l "${BURP_DIR}/${BJAR}" 2>/dev/null \
        | grep -iE '\.png' \
        | grep -iE 'icon|logo|burp' \
        | awk '{print $NF}' | head -1)
    if [ -n "$IENTRY" ]; then
        unzip -p "${BURP_DIR}/${BJAR}" "$IENTRY" > "$ICON" 2>/dev/null \
            && ok "Icon: $IENTRY"
    fi
fi

[ -s "$ICON" ] && ICON_PATH="$ICON" || ICON_PATH="application-x-java"

# Write launcher
DESK="${REAL_HOME}/Desktop"
mkdir -p "$DESK"
DFILE="${DESK}/Burp-pro.desktop"

cat > "$DFILE" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Burp-pro
Comment=BurpSuite Pro v${BVER}
Exec=${LOADER_CMD}
Icon=${ICON_PATH}
Terminal=false
Categories=Security;Network;Development;
StartupNotify=true
EOF

chmod +x "$DFILE"
chown "$REAL_USER":"$REAL_USER" "$DFILE" 2>/dev/null || true
# GNOME trust
command -v gio &>/dev/null && run_as_user gio set "$DFILE" metadata::trusted true 2>/dev/null || true

ok "Launcher: $DFILE"


# ════════════════════════════════════════════════════════════════════
#  DONE
# ════════════════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║                 ✔  All Done!                             ║"
echo "  ╠══════════════════════════════════════════════════════════╣"
printf "  ║  %-56s║\n" "Java     : $(java -version 2>&1 | head -1)"
printf "  ║  %-56s║\n" "BurpSuite: v${BVER}"
printf "  ║  %-56s║\n" "Files    : $BURP_DIR"
printf "  ║  %-56s║\n" "Launcher : $DFILE"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  ${GREEN}Double-click ${BOLD}Burp-pro${NC}${GREEN} on your Desktop to launch! 🎯${NC}"
echo ""
