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
DATA_DIR="$SCRIPT_DIR/data"
CONFIG_FILE="$DATA_DIR/config.json"
PROXIES_FILE="$DATA_DIR/proxies.json"

# Sicherstellen, dass die Dateistruktur existiert und das Setup durchführen, falls notwendig
setup_file_structure() {
    mkdir -p "$DATA_DIR"
    mkdir -p "$SCRIPT_DIR/etc/haproxy"
    mkdir -p "$SCRIPT_DIR/backup"
    
    # Überprüfen, ob das Setup durchgeführt werden muss
    if [[ ! -f "$CONFIG_FILE" ]] || [[ ! -f "$PROXIES_FILE" ]]; then
        clear
        
        gum style \
            --foreground 212 --border-foreground 212 --border double \
            --align center --width 70 --margin "1 2" --padding "1 2" \
            "HAProxy Manager - Ersteinrichtung" \
            "$(gum style --foreground 240 '------------------------------------')"
        
        gum style --align left --margin "1 2" --width 70 \
            "Es wurde erkannt, dass dies der erste Start des HAProxy Managers ist.\n\n"\
            "Die folgenden Aktionen werden ausgeführt:\n"\
            "1. Erstellen des Daten-Verzeichnisses: $DATA_DIR\n"\
            "2. Kopieren der Standardkonfiguration aus: $SCRIPT_DIR/data-setup\n"\
            "3. Einrichten der HAProxy-Konfigurationsstruktur\n\n"\
            "Die Standardkonfiguration beinhaltet folgende Einstellungen:\n"\
            "- HAProxy Config Pfad: $(jq -r .haproxy_cfg_path "$SCRIPT_DIR/data-setup/config.json")\n"\
            "- Fallback IP: $(jq -r .fallback_ip "$SCRIPT_DIR/data-setup/config.json")\n"\
            "- Produktionsmodus: $(jq -r .production_mode "$SCRIPT_DIR/data-setup/config.json")\n"\
            "- HAProxy neustarten: $(jq -r .restart_service "$SCRIPT_DIR/data-setup/config.json")\n"
        
        gum confirm "Möchten Sie mit der Ersteinrichtung fortfahren?" || exit 1
        
        echo ""
        gum spin --spinner dot --title "Ersteinrichtung wird durchgeführt..." -- sleep 1
        
        # Kopieren der Setup-Dateien
        cp "$SCRIPT_DIR/data-setup/config.json" "$CONFIG_FILE"
        cp "$SCRIPT_DIR/data-setup/proxies.json" "$PROXIES_FILE"
        
        gum style --foreground 46 --align center --margin "1 0" "✓ Setup erfolgreich abgeschlossen!"
        gum style --align left --margin "1 2" --width 70 \
            "Die Konfigurationsdateien wurden aus den Vorlagen erstellt.\n"\
            "Sie können die Konfiguration jederzeit unter folgenden Pfaden anpassen:\n"\
            "- Konfiguration: $CONFIG_FILE\n"\
            "- Proxies: $PROXIES_FILE"
        
        gum confirm "Drücken Sie Enter, um fortzufahren..." || true
    fi
}

# Module einbinden
source "$SCRIPT_DIR/lib/config_utils.sh"
source "$SCRIPT_DIR/lib/proxy_handler.sh"
source "$SCRIPT_DIR/lib/config_generator.sh"
source "$SCRIPT_DIR/lib/ui_manager.sh"

# Hauptfunktion
main() {
    # Überprüfen, ob alle Abhängigkeiten installiert sind
    check_dependencies
    
    # Dateistruktur einrichten und ggf. Setup durchführen
    setup_file_structure
    
    # Nach dem Setup oder wenn kein Setup nötig war, das Hauptmenü anzeigen
    clear
    show_main_menu
}

# Programm starten
main
