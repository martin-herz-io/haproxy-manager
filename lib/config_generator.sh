#!/bin/bash
# config_generator.sh - Generiert die HAProxy Konfigurationsdatei aus den Proxies

PROXIES_FILE="/home/martin-andree/Schreibtisch/LocalDev/haproxy-manager/data/proxies.json"
HAPROXY_CFG="/home/martin-andree/Schreibtisch/LocalDev/haproxy-manager/etc/haproxy/haproxy.cfg"
FALLBACK_IP="192.168.100.99"

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
    timeout connect 5s
    timeout client  30s
    timeout server  30s

# ──────────────── HTTPS (Port 443 – TCP, SNI) ────────────────
frontend https_in
    bind *:443
    mode tcp
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }

EOL

    # ACL-Definitionen für HTTPS
    for proxy in $(jq -r 'keys[]' "$PROXIES_FILE"); do
        for domain in $(jq -r ".[\"$proxy\"].domains[]" "$PROXIES_FILE"); do
            echo "    acl is_${proxy} req.ssl_sni -m reg -i ^(.+\.)?${domain//./\\.}$" >> "$HAPROXY_CFG"
        done
        echo "" >> "$HAPROXY_CFG"
    done

    # Backend-Zuweisungen für HTTPS
    for proxy in $(jq -r 'keys[]' "$PROXIES_FILE"); do
        echo "    use_backend ${proxy}_https if is_${proxy}" >> "$HAPROXY_CFG"
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

    # ACL-Definitionen für HTTP
    for proxy in $(jq -r 'keys[]' "$PROXIES_FILE"); do
        for domain in $(jq -r ".[\"$proxy\"].domains[]" "$PROXIES_FILE"); do
            echo "    acl is_${proxy} hdr(host) -m reg -i ^(.+\.)?${domain//./\\.}$" >> "$HAPROXY_CFG"
        done
        echo "" >> "$HAPROXY_CFG"
    done

    # Backend-Zuweisungen für HTTP
    for proxy in $(jq -r 'keys[]' "$PROXIES_FILE"); do
        echo "    use_backend ${proxy}_http if is_${proxy}" >> "$HAPROXY_CFG"
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
    echo "Starte HAProxy neu..."
    if command -v systemctl > /dev/null 2>&1; then
        if sudo systemctl restart haproxy; then
            echo "HAProxy wurde erfolgreich neu gestartet."
            return 0
        else
            echo "Fehler beim Neustart von HAProxy!"
            return 1
        fi
    else
        echo "Systemctl ist nicht verfügbar. HAProxy konnte nicht neu gestartet werden."
        return 1
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
