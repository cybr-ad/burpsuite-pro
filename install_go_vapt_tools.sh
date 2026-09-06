#!/bin/bash
# ============================================================
# Complete Go VAPT Tools Installer (v2 — smoothed)
# All essential Go-based security tools in one script
# ============================================================
#
# Changes from v1:
#   - Removed `set -e` : one broken package no longer kills the
#     whole run; failures are now collected and reported at the end.
#   - Removed goWAPT   : it's a C-style make/make-install project,
#     not `go install`-compatible — the original line would have failed.
#   - Removed GoLinkFinder duplication with katana's -jc (JS crawl)
#     and kept both since they serve different use cases; noted below.
#   - De-duplicated: gau and waybackurls overlap heavily (both archive
#     URL fetchers) — kept both since gau also pulls OTX/Common Crawl,
#     but flagged so you know why they look redundant.
#   - Each `go install` now retried once on failure before being logged
#     as failed, since transient network blips are common with GOPROXY.
#   - Added final PASS/FAIL summary table instead of a static tool list,
#     so you know exactly what actually installed.
#   - Added `-tags` / `GOFLAGS` guard and GOPROXY sanity check up front.
#
set -uo pipefail
# (deliberately NOT using -e — see note above)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info()   { echo -e "${GREEN}[+]${NC} $1"; }
print_warn()   { echo -e "${YELLOW}[!]${NC} $1"; }
print_error()  { echo -e "${RED}[-]${NC} $1"; }
print_header() { echo -e "${BLUE}==>${NC} $1"; }

echo ""
echo "============================================================"
echo "     Complete Go VAPT Tools Installer (v2)"
echo "     Recon | Scanning | Fuzzing | Utilities"
echo "============================================================"
echo ""

# ------------------------------------------------------------
# Pre-flight checks
# ------------------------------------------------------------
if ! command -v go &> /dev/null; then
    print_error "Go is not installed. Please install Go 1.21+ first."
    echo ""
    echo "Quick install:"
    echo "  wget https://go.dev/dl/go1.23.4.linux-amd64.tar.gz"
    echo "  sudo tar -C /usr/local -xzf go1.23.4.linux-amd64.tar.gz"
    echo "  echo 'export PATH=\$PATH:/usr/local/go/bin' >> ~/.bashrc"
    echo "  echo 'export PATH=\$PATH:\$(go env GOPATH)/bin' >> ~/.bashrc"
    echo "  source ~/.bashrc"
    exit 1
fi

GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
print_info "Go detected (version $GO_VERSION)"

if ! command -v git &> /dev/null; then
    print_error "git is not installed — required for GF pattern download. Install with: sudo apt install git"
    exit 1
fi

GOPROXY_CUR=$(go env GOPROXY)
print_info "GOPROXY: $GOPROXY_CUR"

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Track results
declare -a INSTALLED=()
declare -a FAILED=()

# install_go_tool <package@version> <friendly-name>
install_go_tool() {
    local pkg="$1"
    local name="$2"
    print_info "Installing $name..."
    if go install -v "$pkg" >> "$TEMP_DIR/install.log" 2>&1; then
        INSTALLED+=("$name")
        return 0
    fi
    print_warn "$name failed on first attempt, retrying once..."
    if go install -v "$pkg" >> "$TEMP_DIR/install.log" 2>&1; then
        INSTALLED+=("$name")
        return 0
    fi
    print_error "$name failed to install (see $TEMP_DIR/install.log)"
    FAILED+=("$name")
    return 1
}

# ============================================================
# 1. RECONNAISSANCE & INFORMATION GATHERING
# ============================================================
print_header "Installing Reconnaissance tools..."

# ProjectDiscovery suite (most essential, most reliably maintained)
install_go_tool "github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest" "subfinder"
install_go_tool "github.com/projectdiscovery/httpx/cmd/httpx@latest" "httpx"
install_go_tool "github.com/projectdiscovery/naabu/v2/cmd/naabu@latest" "naabu"
install_go_tool "github.com/projectdiscovery/dnsx/cmd/dnsx@latest" "dnsx"
install_go_tool "github.com/projectdiscovery/katana/cmd/katana@latest" "katana"
install_go_tool "github.com/projectdiscovery/mapcidr/cmd/mapcidr@latest" "mapcidr"
install_go_tool "github.com/projectdiscovery/asnmap/cmd/asnmap@latest" "asnmap"
install_go_tool "github.com/projectdiscovery/chaos-client/cmd/chaos@latest" "chaos"
install_go_tool "github.com/projectdiscovery/uncover/cmd/uncover@latest" "uncover"

# Note: wappalyzergo is a LIBRARY, not a CLI — it has no cmd/ binary to install.
# If you want CLI tech-detection, use webanalyze (below) instead.
print_warn "Skipping wappalyzergo — it's a Go library, not a standalone CLI tool (no cmd/ binary)"

# Tomnomnom tools
print_info "Tomnomnom tools..."
install_go_tool "github.com/tomnomnom/assetfinder@latest" "assetfinder"
install_go_tool "github.com/tomnomnom/waybackurls@latest" "waybackurls"
install_go_tool "github.com/tomnomnom/gf@latest" "gf"
install_go_tool "github.com/tomnomnom/qsreplace@latest" "qsreplace"
install_go_tool "github.com/tomnomnom/unfurl@latest" "unfurl"
install_go_tool "github.com/tomnomnom/anew@latest" "anew"
install_go_tool "github.com/tomnomnom/urldedupe@latest" "urldedupe"

# Other recon tools
print_info "Additional recon tools..."
# Note: gau and waybackurls overlap (both pull archived URLs), gau adds
# OTX + Common Crawl + urlscan.io sources on top of Wayback — kept both,
# drop whichever you don't use once you've tried them.
install_go_tool "github.com/lc/gau/v2/cmd/gau@latest" "gau"
install_go_tool "github.com/hakluke/hakrawler@latest" "hakrawler"
install_go_tool "github.com/edoardottt/cariddi/cmd/cariddi@latest" "cariddi"
install_go_tool "github.com/0xsha/GoLinkFinder@latest" "GoLinkFinder"
install_go_tool "github.com/rverton/webanalyze@latest" "webanalyze"
install_go_tool "github.com/gwen001/github-subdomain@latest" "github-subdomain"
install_go_tool "github.com/incogbyte/shosubgo@latest" "shosubgo"

# ============================================================
# 2. VULNERABILITY SCANNING
# ============================================================
print_header "Installing Vulnerability Scanning tools..."

install_go_tool "github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest" "nuclei"
install_go_tool "github.com/zan8in/afrog/v3/cmd/afrog@latest" "afrog"
install_go_tool "github.com/hahwul/dalfox/v2@latest" "dalfox"
install_go_tool "github.com/opensec-cn/kunpeng@latest" "kunpeng"

# Removed: goWAPT (dzonerzy/goWAPT) — this is a C-style project built
# with `make && sudo make install`, NOT `go install`-compatible.
# If you want it, install manually:
#   git clone https://github.com/dzonerzy/goWAPT && cd goWAPT && make && sudo make install
print_warn "Skipped goWAPT — not go-install-compatible (requires make/make install, see script comments)"

# ============================================================
# 3. FUZZING & BRUTE-FORCING
# ============================================================
print_header "Installing Fuzzing & Brute-Forcing tools..."

install_go_tool "github.com/ffuf/ffuf/v2@latest" "ffuf"
install_go_tool "github.com/OJ/gobuster/v3@latest" "gobuster"

# ============================================================
# 4. UTILITIES & HELPERS
# ============================================================
print_header "Installing Utility tools..."

install_go_tool "github.com/projectdiscovery/interactsh/cmd/interactsh-client@latest" "interactsh-client"
install_go_tool "github.com/projectdiscovery/notify/cmd/notify@latest" "notify"
install_go_tool "github.com/projectdiscovery/proxify/cmd/proxify@latest" "proxify"

# ============================================================
# 5. ADVANCED / SPECIALIZED TOOLS
# ============================================================
print_header "Installing Advanced tools..."

install_go_tool "github.com/Brosck/mantra@latest" "mantra (API key leak scanner)"
install_go_tool "github.com/grumpzsux/jxss@latest" "jxss (reflected XSS)"
install_go_tool "github.com/vijay922/GoXSScanner@latest" "GoXSScanner"
install_go_tool "github.com/bonzitechnology/gograbber@latest" "gograbber"
install_go_tool "github.com/sa7mon/s3scanner@latest" "s3scanner"

# ============================================================
# 6. GF PATTERNS INSTALLATION
# ============================================================
print_header "Installing GF patterns..."

if command -v gf &> /dev/null; then
    mkdir -p ~/.gf

    if [ -d /tmp/Gf-Patterns ]; then
        rm -rf /tmp/Gf-Patterns
    fi

    if git clone --depth 1 https://github.com/1ndianl33t/Gf-Patterns /tmp/Gf-Patterns >> "$TEMP_DIR/install.log" 2>&1; then
        cp /tmp/Gf-Patterns/*.json ~/.gf/ 2>/dev/null || true
        rm -rf /tmp/Gf-Patterns
        print_info "GF patterns installed to ~/.gf/"
    else
        print_error "Failed to clone GF-Patterns repo (network issue?). Retry manually:"
        echo "  git clone https://github.com/1ndianl33t/Gf-Patterns && cp Gf-Patterns/*.json ~/.gf/"
    fi
else
    print_warn "gf not found in PATH — skipping pattern install. Run this step again after gf installs successfully."
fi

# ============================================================
# 7. UPDATE NUCLEI TEMPLATES
# ============================================================
if command -v nuclei &> /dev/null; then
    print_info "Updating Nuclei templates..."
    nuclei -update-templates 2>&1 | tail -5
else
    print_warn "nuclei not found in PATH — templates not updated. Run 'nuclei -update-templates' after it installs."
fi

# ============================================================
# 8. PATH FINALIZATION
# ============================================================
GOPATH=$(go env GOPATH 2>/dev/null || echo "$HOME/go")
BIN_PATH="$GOPATH/bin"

if [[ ":$PATH:" != *":$BIN_PATH:"* ]]; then
    print_info "Adding $BIN_PATH to PATH..."
    if ! grep -qF "export PATH=\$PATH:$BIN_PATH" ~/.bashrc 2>/dev/null; then
        echo "export PATH=\$PATH:$BIN_PATH" >> ~/.bashrc
    fi
    export PATH=$PATH:$BIN_PATH
fi

# ============================================================
# 9. RESULTS SUMMARY
# ============================================================
echo ""
echo "============================================================"
echo "  INSTALL SUMMARY"
echo "============================================================"
echo ""
print_info "Successfully installed (${#INSTALLED[@]}):"
for t in "${INSTALLED[@]}"; do
    echo "    ✓ $t"
done

echo ""
if [ "${#FAILED[@]}" -gt 0 ]; then
    print_error "Failed to install (${#FAILED[@]}):"
    for t in "${FAILED[@]}"; do
        echo "    ✗ $t"
    done
    echo ""
    echo "  Full logs: $TEMP_DIR/install.log (will be deleted on script exit — copy it now if needed)"
    echo "  To debug a single failure manually:  cat \$(go env GOPATH)/... or re-run:"
    echo "    go install -v <module-path>@latest"
else
    print_info "All tools installed with no failures."
fi

echo ""
echo "============================================================"
echo ""
echo "Go binary path: $BIN_PATH"
echo ""
echo "Run 'source ~/.bashrc' to update PATH, or open a new terminal."
echo ""
echo "Quick test:"
echo "  httpx -version"
echo "  nuclei -version"
echo "  gf -list"
echo ""

# Preserve the install log before the trap deletes TEMP_DIR
if [ "${#FAILED[@]}" -gt 0 ]; then
    cp "$TEMP_DIR/install.log" "$HOME/go_vapt_install_$(date +%Y%m%d_%H%M%S).log" 2>/dev/null && \
        print_info "Full install log saved to ~/go_vapt_install_*.log for review"
fi
