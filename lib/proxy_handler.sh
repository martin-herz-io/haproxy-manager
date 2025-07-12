#!/bin/bash
# proxy_handler.sh - Funktionen zum Verwalten der Proxies

# Die Pfade werden von start.sh weitergegeben
# SCRIPT_DIR, DATA_DIR, CONFIG_FILE und PROXIES_FILE werden bereits definiert
# Die get_config_value-Funktion wird von config_utils.sh bereitgestellt

# HAPROXY_CFG aus der Konfiguration auslesen
HAPROXY_CFG=$(get_config_value "haproxy_cfg_path" "$SCRIPT_DIR/etc/haproxy/haproxy.cfg")

# Funktion zum Auslesen aller Proxies
list_proxies() {
    echo "Vorhandene Proxies:"
    jq -r 'keys[]' "$PROXIES_FILE"
}

# Funktion zum Anzeigen eines einzelnen Proxies
view_proxy() {
    local proxy_name="$1"
    if jq -e ".$proxy_name" "$PROXIES_FILE" > /dev/null 2>&1; then
        echo "Details für Proxy '$proxy_name':"
        jq ".$proxy_name" "$PROXIES_FILE"
    else
        echo "Proxy '$proxy_name' existiert nicht."
        return 1
    fi
}

# Funktion zum Erstellen eines neuen Proxies
create_proxy() {
    local proxy_name="$1"
    local domains="$2"
    local ip="$3"
    
    # Prüfen, ob der Proxy bereits existiert
    if jq -e ".$proxy_name" "$PROXIES_FILE" > /dev/null 2>&1; then
        echo "Proxy '$proxy_name' existiert bereits. Bitte verwende 'update'."
        return 1
    fi
    
    # Proxy erstellen
    domain_array=$(echo "$domains" | jq -R 'split(",") | map(. | gsub("^\\s+|\\s+$"; ""))')
    
    # JSON aktualisieren
    jq --arg name "$proxy_name" --argjson domains "$domain_array" --arg ip "$ip" \
        '.[$name] = {"domains": $domains, "ip": $ip}' "$PROXIES_FILE" > "${PROXIES_FILE}.tmp"
    
    mv "${PROXIES_FILE}.tmp" "$PROXIES_FILE"
    echo "Proxy '$proxy_name' erfolgreich erstellt."
}

# Funktion zum Aktualisieren eines bestehenden Proxies
update_proxy() {
    local proxy_name="$1"
    local domains="$2"
    local ip="$3"
    
    # Prüfen, ob der Proxy existiert
    if ! jq -e ".$proxy_name" "$PROXIES_FILE" > /dev/null 2>&1; then
        echo "Proxy '$proxy_name' existiert nicht. Bitte verwende 'create'."
        return 1
    fi
    
    # Proxy aktualisieren
    domain_array=$(echo "$domains" | jq -R 'split(",") | map(. | gsub("^\\s+|\\s+$"; ""))')
    
    # JSON aktualisieren
    jq --arg name "$proxy_name" --argjson domains "$domain_array" --arg ip "$ip" \
        '.[$name] = {"domains": $domains, "ip": $ip}' "$PROXIES_FILE" > "${PROXIES_FILE}.tmp"
    
    mv "${PROXIES_FILE}.tmp" "$PROXIES_FILE"
    echo "Proxy '$proxy_name' erfolgreich aktualisiert."
}

# Funktion zum Löschen eines Proxies
delete_proxy() {
    local proxy_name="$1"
    
    # Prüfen, ob der Proxy existiert
    if ! jq -e ".$proxy_name" "$PROXIES_FILE" > /dev/null 2>&1; then
        echo "Proxy '$proxy_name' existiert nicht."
        return 1
    fi
    
    # Proxy löschen
    jq --arg name "$proxy_name" 'del(.[$name])' "$PROXIES_FILE" > "${PROXIES_FILE}.tmp"
    
    mv "${PROXIES_FILE}.tmp" "$PROXIES_FILE"
    echo "Proxy '$proxy_name' erfolgreich gelöscht."
}
