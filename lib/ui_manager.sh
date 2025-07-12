#!/bin/bash
# ui_manager.sh - Funktionen für das gum-basierte UI

# Funktion für den Hauptmenü-Dialog
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
        "Konfiguration neu generieren" \
        "Konfiguration validieren" \
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
        "Konfiguration neu generieren")
            generate_haproxy_config
            gum confirm "Zurück zum Hauptmenü?" && show_main_menu
            ;;
        "Konfiguration validieren")
            validate_haproxy_config
            gum confirm "Zurück zum Hauptmenü?" && show_main_menu
            ;;
        "Beenden")
            exit 0
            ;;
    esac
}

# Funktion für das Anzeigen eines bestimmten Proxies
show_view_proxy_menu() {
    proxy_name=$(gum input --placeholder "Name des Proxies" --header="Welchen Proxy möchtest du anzeigen?")
    
    if [[ -n "$proxy_name" ]]; then
        view_proxy "$proxy_name" | gum pager
    fi
    
    gum confirm "Zurück zum Hauptmenü?" && show_main_menu
}

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
    
    # Bestätigung einholen
    gum confirm "Proxy '${proxy_name}' mit Domains '${domains}' und IP '${ip}' erstellen?" || {
        gum confirm "Zurück zum Hauptmenü?" && show_main_menu
        return
    }
    
    create_proxy "$proxy_name" "$domains" "$ip"
    
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
    
    gum style "Aktuelle Werte:" "\nDomains: $current_domains" "\nIP: $current_ip"
    
    # Neue Werte erfassen
    domains=$(gum input --value="$current_domains" --header="Neue Domains (durch Komma getrennt):")
    
    if [[ -z "$domains" ]]; then
        domains="$current_domains"
    fi
    
    ip=$(gum input --value="$current_ip" --header="Neue IP-Adresse:")
    
    if [[ -z "$ip" ]]; then
        ip="$current_ip"
    fi
    
    # Bestätigung einholen
    gum confirm "Proxy '${proxy_name}' mit Domains '${domains}' und IP '${ip}' aktualisieren?" || {
        gum confirm "Zurück zum Hauptmenü?" && show_main_menu
        return
    }
    
    update_proxy "$proxy_name" "$domains" "$ip"
    
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
