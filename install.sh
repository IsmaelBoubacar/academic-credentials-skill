#!/bin/bash

# academic-credentials-skill — Installer
# Installs the skill to ~/.claude/skills/academic-credentials/
# Usage: ./install.sh [-y|--yes] [-h|--help]

set -e

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/skill"
SKILLS_DIR="$HOME/.claude/skills"
INSTALL_PATH="$SKILLS_DIR/academic-credentials"

# ── Banner ────────────────────────────────────────────────────────────────────
print_banner() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}                                                                ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   ${WHITE}academic-credentials-skill${NC}                                  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   ${BLUE}Solana SBT diploma issuance & verification${NC}                  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                                ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   ${GREEN}Built on UDHCertification — 7,000+ students, Niger${NC}          ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   ${YELLOW}CONCIT 2025 — 1st Prize${NC}                                    ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                                ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_help() {
    echo "academic-credentials-skill installer"
    echo ""
    echo "Usage: ./install.sh [OPTIONS]"
    echo ""
    echo "Installs to: ~/.claude/skills/academic-credentials/"
    echo ""
    echo "Options:"
    echo "  -y, --yes     Skip confirmation prompt"
    echo "  -p, --project Install to ./.claude/skills/ (project-local)"
    echo "  -h, --help    Show this help"
    echo ""
}

# ── Parse args ────────────────────────────────────────────────────────────────
SKIP_CONFIRM=false
PROJECT_LOCAL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--yes)   SKIP_CONFIRM=true; shift ;;
        -p|--project)
            PROJECT_LOCAL=true
            INSTALL_PATH="$(pwd)/.claude/skills/academic-credentials"
            shift
            ;;
        -h|--help)  print_help; exit 0 ;;
        *)
            echo "Unknown option: $1 (use --help)"
            exit 1
            ;;
    esac
done

# ── Preflight ─────────────────────────────────────────────────────────────────
print_banner

if [ ! -d "$SOURCE_DIR" ]; then
    echo -e "${RED}Error:${NC} skill/ directory not found at $SOURCE_DIR"
    echo "Run this script from the repository root."
    exit 1
fi

echo -e "Installing ${WHITE}academic-credentials-skill${NC}"
echo -e "  Destination: ${CYAN}$INSTALL_PATH${NC}"
echo ""

if [ "$SKIP_CONFIRM" = false ]; then
    read -p "Proceed? [Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo -e "${YELLOW}Installation cancelled.${NC}"
        exit 0
    fi
fi

echo ""

# ── Install ───────────────────────────────────────────────────────────────────
echo -e "${CYAN}[1/2]${NC} Creating skill directory..."
mkdir -p "$INSTALL_PATH"

if [ -d "$INSTALL_PATH" ] && [ "$(ls -A "$INSTALL_PATH")" ]; then
    echo -e "  ${YELLOW}→${NC} Removing existing installation"
    rm -rf "${INSTALL_PATH:?}"/*
fi

echo -e "${CYAN}[2/2]${NC} Copying skill files..."
cp -r "$SOURCE_DIR"/* "$INSTALL_PATH/"
echo -e "  ${GREEN}✓${NC} Copied $(ls "$SOURCE_DIR" | wc -l | tr -d ' ') files"

# ── Verify ────────────────────────────────────────────────────────────────────
REQUIRED_FILES=("SKILL.md" "issuance.md" "verification.md" "compliance.md" "evm-to-solana.md")
MISSING=0
for f in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$INSTALL_PATH/$f" ]; then
        echo -e "  ${RED}✗${NC} Missing: $f"
        MISSING=$((MISSING + 1))
    fi
done

if [ "$MISSING" -gt 0 ]; then
    echo -e "${RED}Installation incomplete — $MISSING files missing.${NC}"
    exit 1
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC}  ${WHITE}Installation complete!${NC}                                        ${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}✓${NC} Installed to ${CYAN}$INSTALL_PATH${NC}"
echo ""
echo -e "${WHITE}Try asking Claude:${NC}"
echo -e "  ${BLUE}•${NC} \"Issue a diploma SBT for our 2025 Computer Science graduates\""
echo -e "  ${BLUE}•${NC} \"Verify this credential by QR code\""
echo -e "  ${BLUE}•${NC} \"How do I comply with GDPR for our credential system?\""
echo -e "  ${BLUE}•${NC} \"Migrate our 3,000 Polygon SBTs to Solana\""
echo ""
echo -e "${CYAN}─────────────────────────────────────────────────────────────────────${NC}"
echo -e "${YELLOW}  Powered by UDHCertification · Superteam Brazil Bounty 2025${NC}"
echo -e "${CYAN}─────────────────────────────────────────────────────────────────────${NC}"
echo ""
