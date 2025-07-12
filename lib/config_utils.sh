#!/bin/bash
# config_utils.sh - Gemeinsame Hilfsfunktionen für die Konfiguration

# Funktion zum Lesen von Konfigurationswerten aus der config.json
get_config_value() {
    local key="$1"
    local default_value="$2"
    local value
    
    if [[ -f "$CONFIG_FILE" ]]; then
        value=$(jq -r ".$key // \"$default_value\"" "$CONFIG_FILE")
        echo "$value"
    else
        echo "$default_value"
    fi
}

# Funktion zum Schreiben von Konfigurationswerten in die config.json
set_config_value() {
    local key="$1"
    local value="$2"
    
    if [[ -f "$CONFIG_FILE" ]]; then
        jq --arg key "$key" --arg value "$value" '.[$key] = $value' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
        mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        echo "Konfigurationswert '$key' wurde auf '$value' gesetzt."
    else
        echo "Fehler: Konfigurationsdatei nicht gefunden."
        return 1
    fi
}
