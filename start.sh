#!/bin/bash
# HAProxy Manager - Ein Tool zum Verwalten von HAProxy-Konfigurationen
# Autor: GitHub Copilot
# Datum: 12. Juli 2025

# Prüfen, ob alle erforderlichen Tools installiert sind
check_dependencies() {
    local missing=()
    
    if ! command -v gum > /dev/null 2>&1; then
        missing+=("gum")
    fi
    
    if ! command -v jq > /dev/null 2>&1; then
        missing+=("jq")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Fehlende Abhängigkeiten: ${missing[*]}"
        echo "Bitte installieren mit:"
        
        if [[ " ${missing[*]} " =~ " gum " ]]; then
            echo "  - gum: go install github.com/charmbracelet/gum@latest"
            echo "    oder: brew install gum"
        fi
        
        if [[ " ${missing[*]} " =~ " jq " ]]; then
            echo "  - jq: apt install jq (Ubuntu/Debian)"
            echo "    oder: brew install jq (macOS)"
        fi
        
        exit 1
    fi
}

# Pfade definieren
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROXIES_FILE="$SCRIPT_DIR/data/proxies.json"
HAPROXY_CFG="$SCRIPT_DIR/etc/haproxy/haproxy.cfg"

# Sicherstellen, dass die Dateistruktur existiert
setup_file_structure() {
    mkdir -p "$SCRIPT_DIR/data"
    mkdir -p "$SCRIPT_DIR/etc/haproxy"
    
    # Erstellen einer leeren proxies.json, falls sie nicht existiert
    if [[ ! -f "$PROXIES_FILE" ]]; then
        echo '{}' > "$PROXIES_FILE"
    fi
}

# Module einbinden
source "$SCRIPT_DIR/lib/proxy_handler.sh"
source "$SCRIPT_DIR/lib/config_generator.sh"
source "$SCRIPT_DIR/lib/ui_manager.sh"

# Hauptfunktion
main() {
    # Überprüfen, ob alle Abhängigkeiten installiert sind
    check_dependencies
    
    # Dateistruktur einrichten
    setup_file_structure
    
    # Hauptmenü anzeigen
    clear
    show_main_menu
}

# Programm starten
main
