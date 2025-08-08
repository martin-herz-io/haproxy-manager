#!/bin/bash
# config_generator.sh - Generiert die HAProxy Konfigurationsdatei aus den Proxies

# Die Pfade werden von start.sh weitergegeben
# SCRIPT_DIR, DATA_DIR, CONFIG_FILE und PROXIES_FILE werden bereits definiert
# Die get_config_value-Funktion wird von config_utils.sh bereitgestellt

# Konfigurationswerte auslesen
HAPROXY_CFG=$(get_config_value "haproxy_cfg_path" "$SCRIPT_DIR/etc/haproxy/haproxy.cfg")
FALLBACK_IP=$(get_config_value "fallback_ip" "192.168.100.99")
PRODUCTION_MODE=$(get_config_value "production_mode" "false")
RESTART_SERVICE=$(get_config_value "restart_service" "true")

# Funktion zum Generieren der HAProxy-Konfiguration
generate_haproxy_config() {
    # Header für die HAProxy-Konfiguration
    cat > "$HAPROXY_CFG" << EOL
global
    log /dev/log local0
    log /dev/log local1 notice
    maxconn 2000
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    option  tcplog
    timeout connect 90s
    timeout client  90s
    timeout server  90s

# ──────────────── HTTPS (Port 443 – TCP, SNI) ────────────────
frontend https_in
    bind *:443
    mode tcp
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }

EOL

    # ACL-Definitionen für HTTPS (ohne Regex, mit direktem Match für Root-Domain, end-Match für Subdomains und spezifischer NPM-Subdomain)
    for proxy in $(jq -r 'keys[]' "$PROXIES_FILE"); do
        # Prüfen, ob der Proxy Domains hat
        domains=$(jq -r ".[\"$proxy\"].domains | length" "$PROXIES_FILE")
        if [ "$domains" -gt 0 ]; then
            for domain in $(jq -r ".[\"$proxy\"].domains[]" "$PROXIES_FILE"); do
                echo "    acl is_${proxy} req.ssl_sni -i ${domain}" >> "$HAPROXY_CFG"                  # Root-Domain
                echo "    acl is_${proxy} req.ssl_sni -m end -i .${domain}" >> "$HAPROXY_CFG"          # Subdomains
                # NPM-Subdomain wird nur für HTTP konfiguriert, nicht für HTTPS
            done
            echo "" >> "$HAPROXY_CFG"
        fi
    done

    # Backend-Zuweisungen für HTTPS mit NPM-Priorität
    for proxy in $(jq -r 'keys[]' "$PROXIES_FILE"); do
        # NPM-Backends werden nur für HTTP konfiguriert, nicht für HTTPS
        echo "    use_backend ${proxy}_https if is_${proxy}" >> "$HAPROXY_CFG"                    # Standard-Backend
    done
    echo "    default_backend fallback_https" >> "$HAPROXY_CFG"
    echo "" >> "$HAPROXY_CFG"

    # Backend-Definitionen für HTTPS
    for proxy in $(jq -r 'keys[]' "$PROXIES_FILE"); do
        ip=$(jq -r ".[\"$proxy\"].ip" "$PROXIES_FILE")
        cat >> "$HAPROXY_CFG" << EOL
backend ${proxy}_https
    mode tcp
    server ${proxy} ${ip}:443

EOL
        # NPM-Backends werden nur für HTTP konfiguriert, nicht für HTTPS
    done

    # Fallback-Backend für HTTPS
    cat >> "$HAPROXY_CFG" << EOL
backend fallback_https
    mode tcp
    server fallback ${FALLBACK_IP}:443

# ──────────────── HTTP (Port 80 – HTTP, Host-Header) ────────────────
frontend http_in
    bind *:80
    mode http
EOL

    # ACL-Definitionen für HTTP (ohne Regex, mit direktem Match für Root-Domain, end-Match für Subdomains und spezifischer NPM-Subdomain)
    for proxy in $(jq -r 'keys[]' "$PROXIES_FILE"); do
        # Prüfen, ob der Proxy Domains hat
        domains=$(jq -r ".[\"$proxy\"].domains | length" "$PROXIES_FILE")
        if [ "$domains" -gt 0 ]; then
            for domain in $(jq -r ".[\"$proxy\"].domains[]" "$PROXIES_FILE"); do
                echo "    acl is_${proxy} hdr(host) -i ${domain}" >> "$HAPROXY_CFG"                  # Root-Domain
                echo "    acl is_${proxy} hdr(host) -m end -i .${domain}" >> "$HAPROXY_CFG"          # Subdomains
                # NPM-Subdomain-Logik entfernt
            done
            echo "" >> "$HAPROXY_CFG"
        fi
    done

    # Backend-Zuweisungen für HTTP
    for proxy in $(jq -r 'keys[]' "$PROXIES_FILE"); do
        echo "    use_backend ${proxy}_http if is_${proxy}" >> "$HAPROXY_CFG"                    # Standard-Backend
    done
    echo "    default_backend fallback_http" >> "$HAPROXY_CFG"
    echo "" >> "$HAPROXY_CFG"

    # Backend-Definitionen für HTTP
    for proxy in $(jq -r 'keys[]' "$PROXIES_FILE"); do
        ip=$(jq -r ".[\"$proxy\"].ip" "$PROXIES_FILE")
        cat >> "$HAPROXY_CFG" << EOL
backend ${proxy}_http
    mode http
    server ${proxy} ${ip}:80

EOL
        # NPM-Backend-Logik entfernt
    done

    # Fallback-Backend für HTTP
    cat >> "$HAPROXY_CFG" << EOL
backend fallback_http
    mode http
    server fallback ${FALLBACK_IP}:80
EOL

    echo "HAProxy-Konfiguration erfolgreich generiert unter $HAPROXY_CFG"
}

# Funktion zum Validieren der HAProxy-Konfiguration
validate_haproxy_config() {
    if command -v haproxy > /dev/null 2>&1; then
        echo "Überprüfe HAProxy-Konfiguration..."
        if haproxy -c -f "$HAPROXY_CFG"; then
            echo "Konfiguration ist gültig."
            return 0
        else
            echo "Fehler in der HAProxy-Konfiguration!"
            return 1
        fi
    else
        echo "HAProxy ist nicht installiert. Kann Konfiguration nicht validieren."
        return 0
    fi
}

# Funktion zum Neustart des HAProxy-Dienstes
restart_haproxy() {
    # Prüfen, ob der Service überhaupt neu gestartet werden soll
    if [[ "$RESTART_SERVICE" != "true" ]]; then
        echo "Neustart des HAProxy-Services deaktiviert in der Konfiguration."
        return 0
    fi
    
    echo "Starte HAProxy neu..."
    
    # Unterschiedliches Verhalten je nach Produktionsmodus
    if [[ "$PRODUCTION_MODE" == "true" ]]; then
        # Im Produktionsmodus den korrekten Reload-Befehl ausführen
        if sudo haproxy -c -f "$HAPROXY_CFG" && sudo systemctl reload haproxy; then
            echo "HAProxy wurde erfolgreich neu geladen."
            return 0
        else
            echo "Fehler beim Neuladen von HAProxy!"
            return 1
        fi
    else
        # Im Entwicklungsmodus nur eine Meldung ausgeben
        echo "Im Entwicklungsmodus: HAProxy würde mit folgendem Befehl neu geladen:"
        echo "haproxy -c -f $HAPROXY_CFG && systemctl reload haproxy"
        return 0
    fi
}

# Funktion zum Anwenden der Konfiguration
apply_config() {
    generate_haproxy_config
    if validate_haproxy_config; then
        restart_haproxy
    else
        echo "Konfiguration wurde nicht angewendet, da die Validierung fehlgeschlagen ist."
        return 1
    fi
}

# Funktion zum Erstellen eines Backups der HAProxy-Konfiguration
create_haproxy_backup() {
    gum style --foreground 212 --align center --width 50 "Backup erstellen"
    
    # Backup-Ordner erstellen, falls nicht vorhanden
    local backup_dir="$SCRIPT_DIR/backup"
    mkdir -p "$backup_dir"
    
    # Aktuelles Datum und Uhrzeit für den Backup-Namen
    local timestamp=$(date "+%Y%m%d-%H%M%S")
    local backup_file="$backup_dir/haproxy.cfg.$timestamp"
    
    # Backup erstellen
    if [[ -f "$HAPROXY_CFG" ]]; then
        cp "$HAPROXY_CFG" "$backup_file"
        gum style --foreground 46 "Backup erfolgreich erstellt:" 
        gum style "$backup_file" 
        gum style --foreground 240 "Zeitstempel: $(date "+%d.%m.%Y %H:%M:%S")"
        return 0
    else
        gum style --foreground 196 "Fehler: Konfigurationsdatei nicht gefunden unter $HAPROXY_CFG"
        return 1
    fi
}

# Funktion zum Wiederherstellen eines HAProxy-Konfiguration Backups
restore_haproxy_backup() {
    local backup_dir="$SCRIPT_DIR/backup"
    
    # Prüfen, ob Backup-Ordner existiert und Backups enthält
    if [[ ! -d "$backup_dir" ]] || [[ -z "$(ls -A "$backup_dir" 2>/dev/null)" ]]; then
        gum style --foreground 196 "Keine Backups gefunden."
        return 1
    fi
    
    gum style --foreground 212 --align center --width 50 "Backup wiederherstellen"
    
    # Liste der verfügbaren Backups
    local backups=()
    local backup_options=()
    
    while IFS= read -r file; do
        backups+=("$file")
        backup_options+=("$(basename "$file") ($(date -r "$file" "+%d.%m.%Y %H:%M:%S"))")
    done < <(find "$backup_dir" -name "haproxy.cfg.*" -type f | sort -r)
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        gum style --foreground 196 "Keine Backups gefunden."
        return 1
    fi
    
    # Auswahl eines Backups mit gum
    local selected_option
    selected_option=$(gum choose --header="Wähle ein Backup zum Wiederherstellen:" "${backup_options[@]}")
    
    if [[ -z "$selected_option" ]]; then
        gum style --foreground 196 "Keine Auswahl getroffen."
        return 1
    fi
    
    # Extrahiere den Dateinamen aus der ausgewählten Option
    local backup_filename=$(echo "$selected_option" | awk '{print $1}')
    
    # Vollständiger Pfad zum ausgewählten Backup
    local full_backup_path
    for b in "${backups[@]}"; do
        if [[ "$(basename "$b")" == "$backup_filename" ]]; then
            full_backup_path="$b"
            break
        fi
    done
    
    # Backup wiederherstellen
    if [[ -f "$full_backup_path" ]]; then
        # Sicherheitsabfrage
        if gum confirm "Möchtest du das Backup $(basename "$full_backup_path") wirklich wiederherstellen?"; then
            cp "$full_backup_path" "$HAPROXY_CFG"
            gum style --foreground 46 "Backup wurde erfolgreich wiederhergestellt."
            
            # Frage, ob HAProxy neu gestartet werden soll
            if validate_haproxy_config; then
                if gum confirm "Möchtest du HAProxy mit der wiederhergestellten Konfiguration neu starten?"; then
                    restart_haproxy
                fi
            fi
            return 0
        else
            gum style --foreground 196 "Wiederherstellung abgebrochen."
            return 1
        fi
    else
        gum style --foreground 196 "Fehler: Backup-Datei nicht gefunden."
        return 1
    fi
}
