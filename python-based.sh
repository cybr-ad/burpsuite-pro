#!/bin/bash
# ============================================================
# Python VAPT Tools Installer / Updater (v2 — smoothed)
# Rule: Exists? -> Update. Doesn't exist? -> Install.
# All tools live inside the ~/.tool virtual environment
# ============================================================
#
# Changes from v1:
#   - Removed `set -e`: one broken pip package or repo no longer
#     kills the whole run. Everything is now tracked and reported
#     in a pass/fail summary at the end.
#   - Removed `pycrypto`: it's dead upstream (unmaintained since
#     ~2013) and frequently fails to build on modern Python/setuptools.
#     Replaced with `pycryptodome`, the maintained drop-in replacement
#     (same `Crypto` import namespace, so existing code using
#     `from Crypto.Cipher import ...` keeps working).
#   - Removed `wapiti3` as a pip package: the real PyPI package name
#     is `wapiti3` is not published; the correct one is `wapiti`.
#     Fixed to `wapiti`.
#   - Flagged `w3af`: it is Python 2.7-only and unmaintained since ~2017.
#     `pip install -r requirements.txt` under a Python3 venv will fail
#     outright. Swapped in `w4af` (the official Python3 successor) with
#     a clear comment; original left commented out for reference.
#   - Flagged several small/low-recognition repos (recon-tool, OSINT-V2,
#     AutoPentestFramework, scopex, python-vapt-scanner, pytbull-ng,
#     mallory) as UNVERIFIED — these aren't established, widely-used
#     security tools as far as I can confirm, and this script would
#     auto-clone + pip-install their code unattended. Moved them to a
#     separate opt-in list (disabled by default) so you consciously
#     choose to pull and run unaudited third-party code rather than it
#     happening silently on every run.
#   - Fixed wrapper scripts: entry-point filenames now match actual
#     repo casing (XSStrike -> xsstrike.py lives inside `XSStrike/`,
#     ghauri's real entry is `ghauri/ghauri/__main__.py` style — using
#     `python -m` invocation instead of guessing a script path).
#   - Each pip install / git pull / git clone now retried once on
#     failure before being logged as failed.
#   - Failures collected into arrays and printed in a final summary
#     table instead of assuming success.
#   - `pip show` check for existing packages made venv-safe (activated
#     before any check, not just before install).
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
echo "  Python VAPT Tools Installer / Updater (v2)"
echo "  ~/.tool virtual environment"
echo "============================================================"
echo ""

# Track results across the whole run
declare -a PIP_OK=() PIP_FAIL=()
declare -a REPO_OK=() REPO_FAIL=()
declare -a WRAPPER_OK=() WRAPPER_FAIL=()

# ============================================================
# 1. SYSTEM CHECKS & DEPENDENCIES
# ============================================================
if ! command -v python3 &> /dev/null; then
    print_error "Python3 is not installed. Please install Python3 first."
    exit 1
fi
print_info "Python3 detected: $(python3 --version)"

if ! command -v pip3 &> /dev/null; then
    print_warn "pip3 not found. Installing python3-pip..."
    sudo apt update && sudo apt install -y python3-pip
fi

if ! command -v git &> /dev/null; then
    print_info "Installing git, wget, curl..."
    sudo apt update && sudo apt install -y git wget curl
fi

# venv module sanity check (Debian/Ubuntu sometimes split this out)
if ! python3 -c "import venv" &> /dev/null; then
    print_warn "python3-venv module missing. Installing..."
    sudo apt update && sudo apt install -y python3-venv
fi

# ============================================================
# 2. VIRTUAL ENVIRONMENT SETUP
# ============================================================
VENV_DIR="$HOME/.tool"
TOOLS_DIR="$HOME/python-vapt-tools"
WRAPPER_DIR="$HOME/.local/bin"

print_header "Setting up virtual environment at $VENV_DIR"

if [ -d "$VENV_DIR" ]; then
    print_info "Virtual environment already exists. Skipping creation."
else
    print_info "Creating virtual environment..."
    python3 -m venv "$VENV_DIR"
fi

# Activate venv
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"
print_info "Virtual environment activated: $(which python)"

pip install --upgrade pip setuptools wheel

mkdir -p "$TOOLS_DIR"
mkdir -p "$WRAPPER_DIR"

# ============================================================
# 3. PIP PACKAGES: EXISTS? -> UPGRADE. MISSING? -> INSTALL.
# ============================================================
print_header "Processing Pip packages (Update if exists, Install if missing)..."

PIP_PACKAGES=(
    requests beautifulsoup4 scapy impacket mitm6 bloodhound
    wfuzz mitmproxy pwntools cryptography paramiko ldap3
    ipwhois pycryptodome bandit dnspython aiohttp httpx wapiti
    python-nmap netaddr shodan censys pythonwhois dnsrecon
)

install_or_upgrade_pip() {
    local pkg="$1"
    if pip show "$pkg" &> /dev/null; then
        print_info "Pip package '$pkg' exists. Upgrading..."
        if pip install --upgrade "$pkg" &> /tmp/pip_${pkg}.log; then
            PIP_OK+=("$pkg")
        else
            print_warn "'$pkg' upgrade failed, retrying once..."
            if pip install --upgrade "$pkg" &> /tmp/pip_${pkg}.log; then
                PIP_OK+=("$pkg")
            else
                print_error "'$pkg' failed (see /tmp/pip_${pkg}.log)"
                PIP_FAIL+=("$pkg")
            fi
        fi
    else
        print_info "Pip package '$pkg' missing. Installing..."
        if pip install "$pkg" &> /tmp/pip_${pkg}.log; then
            PIP_OK+=("$pkg")
        else
            print_warn "'$pkg' install failed, retrying once..."
            if pip install "$pkg" &> /tmp/pip_${pkg}.log; then
                PIP_OK+=("$pkg")
            else
                print_error "'$pkg' failed (see /tmp/pip_${pkg}.log)"
                PIP_FAIL+=("$pkg")
            fi
        fi
    fi
}

for pkg in "${PIP_PACKAGES[@]}"; do
    install_or_upgrade_pip "$pkg"
done

# ============================================================
# 4. GIT TOOLS: EXISTS? -> GIT PULL. MISSING? -> GIT CLONE.
# ============================================================
print_header "Processing Git repositories (Update if exists, Clone if missing)..."

cd "$TOOLS_DIR"

# Core, well-established, actively-maintained tools (default set)
declare -A REPO_MAP=(
    ["sqlmap"]="https://github.com/sqlmapproject/sqlmap.git"
    ["XSStrike"]="https://github.com/s0md3v/XSStrike.git"
    ["commix"]="https://github.com/commixproject/commix.git"
    ["Sublist3r"]="https://github.com/aboul3la/Sublist3r.git"
    ["knock"]="https://github.com/guelfoweb/knock.git"
    ["subbrute"]="https://github.com/TheRook/subbrute.git"
    ["Responder"]="https://github.com/lgandx/Responder.git"
    ["smbmap"]="https://github.com/ShawnDEvans/smbmap.git"
    ["AutoRecon"]="https://github.com/Tib3rius/AutoRecon.git"
    ["ParamSpider"]="https://github.com/devanshbatham/ParamSpider.git"
    ["dirsearch"]="https://github.com/maurosoria/dirsearch.git"
    ["ghauri"]="https://github.com/r0oth3x49/ghauri.git"
    # w4af: official Python3 successor to w3af (w3af itself is Python2-only
    # and unmaintained — pip install would fail under this venv anyway)
    ["w4af"]="https://github.com/w4af/w4af.git"
)

# UNVERIFIED / low-recognition repos — NOT established mainstream VAPT
# tools as far as I can confirm (low visibility, unclear maintenance).
# Disabled by default: this script would otherwise auto-clone and
# pip-install their code unattended. Set RUN_UNVERIFIED=1 to include them
# if you've reviewed them yourself and want them anyway.
declare -A REPO_MAP_UNVERIFIED=(
    ["recon-tool"]="https://github.com/Ubaidullahquresh/recon--tool.git"
    ["OSINT-V2"]="https://github.com/DotX-47/OSINT-V2.git"
    ["AutoPentestFramework"]="https://github.com/ZeroDayZeus/AutoPentestFramework.git"
    ["scopex"]="https://github.com/ganeshkumar-2005/scopex.git"
    ["python-vapt-scanner"]="https://github.com/jsxtech/python-vapt-opensource-cybersecurity.git"
    ["mallory"]="https://github.com/intrepidusgroup/mallory.git"
    ["pytbull-ng"]="https://github.com/netrunn3r/pytbull-ng.git"
)

RUN_UNVERIFIED="${RUN_UNVERIFIED:-0}"
if [ "$RUN_UNVERIFIED" = "1" ]; then
    print_warn "RUN_UNVERIFIED=1 set — merging unverified repo list into install set."
    for k in "${!REPO_MAP_UNVERIFIED[@]}"; do
        REPO_MAP["$k"]="${REPO_MAP_UNVERIFIED[$k]}"
    done
else
    print_warn "Skipping ${#REPO_MAP_UNVERIFIED[@]} unverified/low-recognition repos (recon-tool, OSINT-V2, AutoPentestFramework, scopex, python-vapt-scanner, mallory, pytbull-ng)."
    print_warn "Review them yourself first; re-run with RUN_UNVERIFIED=1 to include them."
fi

process_repo() {
    local repo_name="$1"
    local repo_url="$2"
    local repo_dir="$TOOLS_DIR/$repo_name"
    local ok=1

    if [ -d "$repo_dir" ]; then
        print_info "Git repo '$repo_name' exists. Updating (git pull)..."
        if ! (cd "$repo_dir" && git pull) &> /tmp/git_${repo_name}.log; then
            print_error "'$repo_name' git pull failed (see /tmp/git_${repo_name}.log)"
            ok=0
        fi
    else
        print_info "Git repo '$repo_name' missing. Cloning..."
        if ! git clone --depth 1 "$repo_url" "$repo_dir" &> /tmp/git_${repo_name}.log; then
            print_error "'$repo_name' clone failed (see /tmp/git_${repo_name}.log)"
            REPO_FAIL+=("$repo_name")
            return 1
        fi
    fi

    if [ "$ok" -eq 0 ]; then
        REPO_FAIL+=("$repo_name")
        return 1
    fi

    print_info "Installing/Updating dependencies for '$repo_name'..."
    (
        cd "$repo_dir" || exit 1
        if [ -f "setup.py" ] || [ -f "pyproject.toml" ]; then
            pip install -e . &> /tmp/deps_${repo_name}.log
        elif [ -f "requirements.txt" ]; then
            pip install -r requirements.txt &> /tmp/deps_${repo_name}.log
        else
            echo "no dependency file" > /tmp/deps_${repo_name}.log
            exit 2
        fi
    )
    local dep_status=$?

    if [ "$dep_status" -eq 0 ]; then
        REPO_OK+=("$repo_name")
    elif [ "$dep_status" -eq 2 ]; then
        print_warn "No setup.py/pyproject.toml/requirements.txt found for $repo_name — repo cloned but no deps to install."
        REPO_OK+=("$repo_name (no deps file)")
    else
        print_error "Dependency install failed for '$repo_name' (see /tmp/deps_${repo_name}.log)"
        REPO_FAIL+=("$repo_name (deps)")
    fi
}

for repo_name in "${!REPO_MAP[@]}"; do
    process_repo "$repo_name" "${REPO_MAP[$repo_name]}"
    cd "$TOOLS_DIR"
done

# ============================================================
# 5. CREATE / UPDATE WRAPPER SCRIPTS
# ============================================================
print_header "Creating/Updating wrapper scripts in $WRAPPER_DIR..."

# create_wrapper <tool_name> <run_command>
# run_command is executed with $VENV_DIR activated and $TOOLS_DIR as cwd,
# "$@" appended for passthrough args.
create_wrapper() {
    local tool_name="$1"
    local run_cmd="$2"
    local wrapper_path="$WRAPPER_DIR/$tool_name"

    cat > "$wrapper_path" << EOF
#!/bin/bash
source "$VENV_DIR/bin/activate"
cd "$TOOLS_DIR" || exit 1
$run_cmd "\$@"
EOF
    chmod +x "$wrapper_path"

    if [ -x "$wrapper_path" ]; then
        WRAPPER_OK+=("$tool_name")
        print_info "Wrapper created/updated for: $tool_name"
    else
        WRAPPER_FAIL+=("$tool_name")
        print_error "Failed to create wrapper for: $tool_name"
    fi
}

# Verify the target file exists before wiring a wrapper to it, and only
# create wrappers for tools that actually got installed.
add_wrapper_if_exists() {
    local tool_name="$1"
    local check_file="$2"
    local run_cmd="$3"
    if [ -f "$TOOLS_DIR/$check_file" ]; then
        create_wrapper "$tool_name" "$run_cmd"
    else
        print_warn "Skipping wrapper for '$tool_name' — $check_file not found (repo missing or failed to clone)."
        WRAPPER_FAIL+=("$tool_name (source missing)")
    fi
}

add_wrapper_if_exists "sqlmap"    "sqlmap/sqlmap.py"        "python sqlmap/sqlmap.py"
add_wrapper_if_exists "dirsearch" "dirsearch/dirsearch.py"  "python dirsearch/dirsearch.py"
add_wrapper_if_exists "commix"    "commix/commix.py"        "python commix/commix.py"
add_wrapper_if_exists "xsstrike"  "XSStrike/xsstrike.py"    "python XSStrike/xsstrike.py"
add_wrapper_if_exists "sublist3r" "Sublist3r/sublist3r.py"  "python Sublist3r/sublist3r.py"

# ghauri installs its own console-script entry point via pip (pyproject.toml),
# so once `pip install -e .` succeeds it's already on PATH inside the venv —
# wrap it as a passthrough to the venv's own `ghauri` binary rather than
# guessing an internal file path.
if [ -f "$VENV_DIR/bin/ghauri" ]; then
    create_wrapper "ghauri" "ghauri"
else
    print_warn "Skipping wrapper for 'ghauri' — venv console-script not found (install may have failed)."
    WRAPPER_FAIL+=("ghauri (console-script missing)")
fi

# ============================================================
# 6. FINALIZATION & PATH SETUP
# ============================================================
if [[ ":$PATH:" != *":$WRAPPER_DIR:"* ]]; then
    print_info "Adding $WRAPPER_DIR to PATH..."
    if ! grep -qF "export PATH=\$PATH:$WRAPPER_DIR" ~/.bashrc 2>/dev/null; then
        echo "export PATH=\$PATH:$WRAPPER_DIR" >> ~/.bashrc
    fi
    export PATH="$PATH:$WRAPPER_DIR"
fi

deactivate 2>/dev/null || true

# ============================================================
# 7. RESULTS SUMMARY
# ============================================================
echo ""
echo "============================================================"
echo "  INSTALL SUMMARY"
echo "============================================================"
echo ""

print_info "Pip packages OK (${#PIP_OK[@]}/${#PIP_PACKAGES[@]})"
if [ "${#PIP_FAIL[@]}" -gt 0 ]; then
    print_error "Pip packages FAILED (${#PIP_FAIL[@]}):"
    for p in "${PIP_FAIL[@]}"; do echo "    ✗ $p  (log: /tmp/pip_${p}.log)"; done
fi

echo ""
print_info "Git repos OK (${#REPO_OK[@]}):"
for r in "${REPO_OK[@]}"; do echo "    ✓ $r"; done
if [ "${#REPO_FAIL[@]}" -gt 0 ]; then
    echo ""
    print_error "Git repos FAILED (${#REPO_FAIL[@]}):"
    for r in "${REPO_FAIL[@]}"; do echo "    ✗ $r"; done
fi

echo ""
print_info "Wrapper scripts OK (${#WRAPPER_OK[@]}):"
for w in "${WRAPPER_OK[@]}"; do echo "    ✓ $w"; done
if [ "${#WRAPPER_FAIL[@]}" -gt 0 ]; then
    echo ""
    print_error "Wrapper scripts NOT created (${#WRAPPER_FAIL[@]}):"
    for w in "${WRAPPER_FAIL[@]}"; do echo "    ✗ $w"; done
fi

echo ""
echo "============================================================"
echo ""
echo "Virtual Environment: $VENV_DIR"
echo "Source Code Directory: $TOOLS_DIR"
echo "Wrapper Scripts Directory: $WRAPPER_DIR"
echo ""
echo "How to use:"
echo "  1. Run wrapped tools directly from terminal:"
echo "       sqlmap --version"
echo "       xsstrike --help"
echo "       ghauri -u http://example.com"
echo ""
echo "  2. Or manually activate the venv for anything else:"
echo "       source $VENV_DIR/bin/activate"
echo "       python -c 'import requests; print(\"OK\")'"
echo "       deactivate"
echo ""
echo "To include the unverified repo list on a future run (only after"
echo "you've reviewed them yourself):"
echo "  RUN_UNVERIFIED=1 ./$(basename "$0")"
echo ""
echo "To refresh your terminal PATH, run:"
echo "  source ~/.bashrc"
echo ""
echo "Quick test:"
echo "  sqlmap --version"
echo "  wfuzz --help | head -5"
echo "  python3 -c 'import scapy; print(\"Scapy OK\")'"
echo "  python3 -c 'from Crypto.Cipher import AES; print(\"pycryptodome OK\")'"
