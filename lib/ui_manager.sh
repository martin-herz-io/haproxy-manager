#!/bin/bash
# ui_manager.sh - Funktionen für das gum-basierte UI und den Hauptmenü-Dialog

# Funktion für das Anzeigen eines bestimmten Proxies
show_view_proxy_menu() {
    proxy_name=$(gum input --placeholder "Name des Proxies" --header="Welchen Proxy möchtest du anzeigen?")
    
    if [[ -n "$proxy_name" ]]; then
        view_proxy "$proxy_name" | gum pager
    fi
    
    gum confirm "Zurück zum Hauptmenü?" && show_main_menu
}
show_main_menu() {
    gum style \
        --foreground 212 --border-foreground 212 --border double \
        --align center --width 50 --margin "1 2" --padding "1 2" \
        "HAProxy Manager" "$(gum style --foreground 240 'v1.0')" \
        "$(gum style --foreground 240 '-----------------------------------')" \
        "$(date '+%d.%m.%Y %H:%M')"

    action=$(gum choose --header="Wähle eine Aktion:" \
        "Liste aller Proxies anzeigen" \
        "Proxy anzeigen" \
        "Neuen Proxy erstellen" \
        "Proxy bearbeiten" \
        "Proxy löschen" \
        "Konfiguration anzeigen/bearbeiten" \
        "HAProxy Konfiguration neu generieren" \
        "HAProxy Konfiguration validieren" \
        "HAProxy Konfiguration anwenden" \
        "Backup erstellen" \
        "Backup wiederherstellen" \
        "Beenden")

    case "$action" in
        "Liste aller Proxies anzeigen")
            list_proxies | gum pager
            show_main_menu
            ;;
        "Proxy anzeigen")
            show_view_proxy_menu
            ;;
        "Neuen Proxy erstellen")
            show_create_proxy_menu
            ;;
        "Proxy bearbeiten")
            show_edit_proxy_menu
            ;;
        "Proxy löschen")
            show_delete_proxy_menu
            ;;
        "Konfiguration anzeigen/bearbeiten")
            show_config_menu
            ;;
        "HAProxy Konfiguration neu generieren")
            generate_haproxy_config
            gum confirm "Zurück zum Hauptmenü?" && show_main_menu
            ;;
        "HAProxy Konfiguration validieren")
            validate_haproxy_config
            gum confirm "Zurück zum Hauptmenü?" && show_main_menu
            ;;
        "HAProxy Konfiguration anwenden")
            apply_config
            gum confirm "Zurück zum Hauptmenü?" && show_main_menu
            ;;
        "Backup erstellen")
            create_haproxy_backup
            gum confirm "Zurück zum Hauptmenü?" && show_main_menu
            ;;
        "Backup wiederherstellen")
            restore_haproxy_backup
            gum confirm "Zurück zum Hauptmenü?" && show_main_menu
            ;;
        "Beenden")
            exit 0
            ;;
    esac
}

# Diese Funktion ist bereits oben implementiert und gum-basiert

# Funktion für das Erstellen eines neuen Proxies
show_create_proxy_menu() {
    gum style --foreground 212 --align center --width 50 "Neuen Proxy erstellen"
    
    proxy_name=$(gum input --placeholder "z.B. kunde3" --header="Name des Proxies:")
    
    if [[ -z "$proxy_name" ]]; then
        gum confirm "Abbrechen und zurück zum Hauptmenü?" && show_main_menu
        return
    fi
    
    # Prüfen, ob der Proxy bereits existiert
    if jq -e ".$proxy_name" "$PROXIES_FILE" > /dev/null 2>&1; then
        gum style --foreground 196 "Proxy '$proxy_name' existiert bereits!"
        gum confirm "Zurück zum Hauptmenü?" && show_main_menu
        return
    fi
    
    domains=$(gum input --placeholder "domain1.de,domain2.com" --header="Domains (durch Komma getrennt):")
    
    if [[ -z "$domains" ]]; then
        gum confirm "Abbrechen und zurück zum Hauptmenü?" && show_main_menu
        return
    fi
    
    ip=$(gum input --placeholder "z.B. 192.168.100.52" --header="IP-Adresse des Zielservers:")
    
    if [[ -z "$ip" ]]; then
        gum confirm "Abbrechen und zurück zum Hauptmenü?" && show_main_menu
        return
    fi

    local send_proxy
    if gum confirm "Soll das Proxy Protocol (send-proxy) für diesen Proxy aktiviert werden?"; then
        send_proxy=true
    else
        send_proxy=false
    fi
    
    # Bestätigung einholen
    gum confirm "Proxy '${proxy_name}' mit Domains '${domains}', IP '${ip}' und send-proxy '${send_proxy}' erstellen?" || {
        gum confirm "Zurück zum Hauptmenü?" && show_main_menu
        return
    }
    
    create_proxy "$proxy_name" "$domains" "$ip" "$send_proxy"
    
    # Fragen, ob HAProxy-Konfiguration neu generiert werden soll
    gum confirm "HAProxy-Konfiguration neu generieren?" && generate_haproxy_config
    
    gum confirm "Zurück zum Hauptmenü?" && show_main_menu
}

# Funktion für das Bearbeiten eines bestehenden Proxies
show_edit_proxy_menu() {
    gum style --foreground 212 --align center --width 50 "Proxy bearbeiten"
    
    proxy_name=$(gum input --placeholder "Name des zu bearbeitenden Proxies" --header="Welchen Proxy möchtest du bearbeiten?")
    
    if [[ -z "$proxy_name" ]]; then
        gum confirm "Abbrechen und zurück zum Hauptmenü?" && show_main_menu
        return
    fi
    
    # Prüfen, ob der Proxy existiert
    if ! jq -e ".$proxy_name" "$PROXIES_FILE" > /dev/null 2>&1; then
        gum style --foreground 196 "Proxy '$proxy_name' existiert nicht!"
        gum confirm "Zurück zum Hauptmenü?" && show_main_menu
        return
    fi
    
    # Aktuelle Werte holen
    current_domains=$(jq -r ".[\"$proxy_name\"].domains | join(\",\")" "$PROXIES_FILE")
    current_ip=$(jq -r ".[\"$proxy_name\"].ip" "$PROXIES_FILE")
    current_send_proxy=$(jq -r ".[\"$proxy_name\"].send_proxy // \"false\"" "$PROXIES_FILE")
    
    gum style "Aktuelle Werte:" "\nDomains: $current_domains" "\nIP: $current_ip" "\nSend Proxy: $current_send_proxy"
    
    # Neue Werte erfassen
    domains=$(gum input --value="$current_domains" --header="Neue Domains (durch Komma getrennt):")
    
    if [[ -z "$domains" ]]; then
        domains="$current_domains"
    fi
    
    ip=$(gum input --value="$current_ip" --header="Neue IP-Adresse:")
    
    if [[ -z "$ip" ]]; then
        ip="$current_ip"
    fi
    
    local send_proxy
    if gum confirm "Proxy Protocol (send-proxy) aktivieren?" --affirmative "Ja" --negative "Nein" --default="$([[ $current_send_proxy == true ]] && echo true || echo false)"; then
        send_proxy=true
    else
        send_proxy=false
    fi

    # Bestätigung einholen
    gum confirm "Proxy '${proxy_name}' mit Domains '${domains}', IP '${ip}' und send-proxy '${send_proxy}' aktualisieren?" || {
        gum confirm "Zurück zum Hauptmenü?" && show_main_menu
        return
    }
    
    update_proxy "$proxy_name" "$domains" "$ip" "$send_proxy"
    
    # Fragen, ob HAProxy-Konfiguration neu generiert werden soll
    gum confirm "HAProxy-Konfiguration neu generieren?" && generate_haproxy_config
    
    gum confirm "Zurück zum Hauptmenü?" && show_main_menu
}

# Funktion für das Löschen eines bestehenden Proxies
show_delete_proxy_menu() {
    gum style --foreground 212 --align center --width 50 "Proxy löschen"
    
    proxy_name=$(gum input --placeholder "Name des zu löschenden Proxies" --header="Welchen Proxy möchtest du löschen?")
    
    if [[ -z "$proxy_name" ]]; then
        gum confirm "Abbrechen und zurück zum Hauptmenü?" && show_main_menu
        return
    fi
    
    # Prüfen, ob der Proxy existiert
    if ! jq -e ".$proxy_name" "$PROXIES_FILE" > /dev/null 2>&1; then
        gum style --foreground 196 "Proxy '$proxy_name' existiert nicht!"
        gum confirm "Zurück zum Hauptmenü?" && show_main_menu
        return
    fi
    
    # Details anzeigen
    view_proxy "$proxy_name" | gum pager
    
    # Bestätigung einholen
    gum confirm --default=false "Möchtest du den Proxy '$proxy_name' wirklich löschen?" || {
        gum confirm "Zurück zum Hauptmenü?" && show_main_menu
        return
    }
    
    delete_proxy "$proxy_name"
    
    # Fragen, ob HAProxy-Konfiguration neu generiert werden soll
    gum confirm "HAProxy-Konfiguration neu generieren?" && generate_haproxy_config
    
    gum confirm "Zurück zum Hauptmenü?" && show_main_menu
}

# Funktion zur Anzeige und Bearbeitung der Konfiguration
show_config_menu() {
    gum style --foreground 212 --align center --width 50 "Konfiguration verwalten"
    
    # Aktuelle Konfiguration anzeigen
    gum style --align left --margin "1 2" --width 70 \
        "Aktuelle Konfiguration:\n"\
        "────────────────────────────────────────────\n"\
        "HAProxy Config Pfad: $(get_config_value "haproxy_cfg_path" "$SCRIPT_DIR/etc/haproxy/haproxy.cfg")\n"\
        "Fallback IP: $(get_config_value "fallback_ip" "192.168.100.99")\n"\
        "Produktionsmodus: $(get_config_value "production_mode" "false")\n"\
        "HAProxy neustarten: $(get_config_value "restart_service" "true")\n"\
        "────────────────────────────────────────────\n"
    
    action=$(gum choose --header="Was möchten Sie tun?" \
        "HAProxy Konfigurationspfad ändern" \
        "Fallback IP ändern" \
        "Produktionsmodus umschalten" \
        "HAProxy-Neustart umschalten" \
        "Konfiguration als JSON anzeigen" \
        "Zurück zum Hauptmenü")
    
    case "$action" in
        "HAProxy Konfigurationspfad ändern")
            current_value=$(get_config_value "haproxy_cfg_path" "$SCRIPT_DIR/etc/haproxy/haproxy.cfg")
            
            gum style "Aktueller HAProxy Konfigurationspfad: $current_value"
            new_value=$(gum input --value="$current_value" --header="Neuer HAProxy Konfigurationspfad:")
            
            if [[ -n "$new_value" ]]; then
                set_config_value "haproxy_cfg_path" "$new_value"
                gum style --foreground 46 "HAProxy Konfigurationspfad wurde aktualisiert."
            fi
            ;;
        "Fallback IP ändern")
            current_value=$(get_config_value "fallback_ip" "192.168.100.99")
            
            gum style "Aktuelle Fallback IP: $current_value"
            new_value=$(gum input --value="$current_value" --header="Neue Fallback IP:")
            
            if [[ -n "$new_value" ]]; then
                set_config_value "fallback_ip" "$new_value"
                gum style --foreground 46 "Fallback IP wurde aktualisiert."
            fi
            ;;
        "Produktionsmodus umschalten")
            current_value=$(get_config_value "production_mode" "false")
            
            if [[ "$current_value" == "true" ]]; then
                new_value="false"
                message="Produktionsmodus wurde auf 'false' (Entwicklung) gesetzt."
            else
                new_value="true"
                message="Produktionsmodus wurde auf 'true' (Produktion) gesetzt."
            fi
            
            set_config_value "production_mode" "$new_value"
            gum style --foreground 46 "$message"
            ;;
        "HAProxy-Neustart umschalten")
            current_value=$(get_config_value "restart_service" "true")
            
            if [[ "$current_value" == "true" ]]; then
                new_value="false"
                message="HAProxy-Neustart wurde deaktiviert."
            else
                new_value="true"
                message="HAProxy-Neustart wurde aktiviert."
            fi
            
            set_config_value "restart_service" "$new_value"
            gum style --foreground 46 "$message"
            ;;
        "Konfiguration als JSON anzeigen")
            cat "$CONFIG_FILE" | jq '.' | gum pager --soft-wrap
            ;;
        "Zurück zum Hauptmenü")
            show_main_menu
            return
            ;;
    esac
    
    gum confirm "Zurück zur Konfiguration?" && show_config_menu || show_main_menu
}
