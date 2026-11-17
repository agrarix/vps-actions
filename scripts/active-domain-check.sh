#!/usr/bin/env bash
# Herstart in Bash indien aangeroepen via /bin/sh (dash op Ubuntu/Debian)
if [ -z "$BASH_VERSION" ]; then
    exec /usr/bin/env bash "$0" "$@"
fi

# ==============================================================================
# active-domain-check.sh - Controleer actieve websites & domeinnamen op host
# ==============================================================================
# Inspecteert Apache VirtualHosts, SSL-certificaten, DocumentRoots en DNS-status.
# Detecteert dynamisch de Xterm/terminalbreedte en past kolommen automatisch aan.
# Logt resultaten automatisch naar $HOME/log/active-domain-check.log
#
# Locatie: /home/maarten/scripts/active-domain-check.sh
# Schakelt automatisch via sudo naar root indien nodig voor /etc/letsencrypt.
#
# Gebruik:
#   active-domain-check.sh                 # Automatische kolombreedte ($TERM_COLS)
#   active-domain-check.sh -c | --compact  # Forceer compact (80 kolommen)
#   active-domain-check.sh -w | --wide     # Forceer breed (>= 110 kolommen)
#   active-domain-check.sh -l | --live     # Alleen domeinen wijzend naar deze host
#   active-domain-check.sh -m | --migrated # Alleen gemigreerd naar Proxmox Home
#   active-domain-check.sh -a | --all      # Inclusief alle mappen in /var/www/vhosts/
#   active-domain-check.sh [domein ...]    # Controleer specifieke domein(en)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Terminalbreedte detectie ($TERM_COLS)
# ------------------------------------------------------------------------------
TERM_COLS=""
if command -v tput &>/dev/null; then
    TERM_COLS=$(tput cols 2>/dev/null)
fi
if [ -z "$TERM_COLS" ]; then
    TERM_COLS=$( (stty size 2>/dev/null || (exec < /dev/tty && stty size) 2>/dev/null) | awk '{print $2}' )
fi
if [ -z "$TERM_COLS" ] && [ -n "$COLUMNS" ]; then
    TERM_COLS="$COLUMNS"
fi
if [ -z "$TERM_COLS" ] || [ "$TERM_COLS" -le 0 ] 2>/dev/null; then
    TERM_COLS=80
fi

# ------------------------------------------------------------------------------
# 2. Zelf-elevatie naar root via sudo (voor toegang tot /etc/letsencrypt)
# Behoudt de oorspronkelijke gebruiker ($CALLER_USER) en terminal instellingen
# ------------------------------------------------------------------------------
CALLER_USER="${SUDO_USER:-$USER}"

if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo &>/dev/null; then
        exec sudo COLUMNS="$TERM_COLS" TERM="${TERM:-xterm}" CALLER_USER="$CALLER_USER" "$0" "$@"
    else
        echo "Fout: Root-rechten vereist voor certificaatcontrole. Configureer sudo." >&2
        exit 1
    fi
fi

# ------------------------------------------------------------------------------
# 3. Logbestand configuratie ($HOME/log/)
# ------------------------------------------------------------------------------
LOG_USER="${CALLER_USER:-maarten}"
LOG_USER_HOME=$(getent passwd "$LOG_USER" 2>/dev/null | cut -d: -f6)
[ -z "$LOG_USER_HOME" ] && LOG_USER_HOME="$HOME"
LOG_DIR="${LOG_USER_HOME}/log"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/active-domain-check.log"

# ANSI Kleuren
BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
CYAN="\033[36m"
RED="\033[31m"
GRAY="\033[90m"
RESET="\033[0m"

# Server IP detectie (skip 127.0.0.1 op venet0)
HOST_IP=$(ip -4 addr show venet0 2>/dev/null | awk '/inet / && !/127\.0\.0\.1/ {print $2}' | cut -d/ -f1 | head -n1)
if [ -z "$HOST_IP" ]; then
    HOST_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
fi
if [ -z "$HOST_IP" ]; then
    HOST_IP="85.214.248.88"
fi

HOME_IP_PREFIX="178.239.16."

FILTER_MODE="configured" # 'configured', 'live', 'migrated', 'all'
LAYOUT_MODE="auto"       # 'auto', 'compact', 'wide'
CUSTOM_DOMAINS=()

# Argument parsing
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--compact)
            LAYOUT_MODE="compact"
            shift
            ;;
        -w|--wide)
            LAYOUT_MODE="wide"
            shift
            ;;
        -l|--live)
            FILTER_MODE="live"
            shift
            ;;
        -m|--migrated)
            FILTER_MODE="migrated"
            shift
            ;;
        -a|--all)
            FILTER_MODE="all"
            shift
            ;;
        -h|--help)
            echo "Gebruik: $0 [-c|-w] [-l|-m|-a] [domein ...]"
            echo "  -c, --compact    Forceer compacte tabel (past in 80 kolommen Xterm)"
            echo "  -w, --wide       Forceer brede tabel (>= 110 kolommen)"
            echo "  -l, --live       Alleen domeinen die naar deze server ($HOST_IP) wijzen"
            echo "  -m, --migrated   Alleen domeinen gemigreerd naar Proxmox Home ($HOME_IP_PREFIX*)"
            echo "  -a, --all        Scan ook ongeconfigureerde mappen in /var/www/vhosts/"
            echo "  [domein ...]     Controleer één of meerdere specifieke domeinen"
            exit 0
            ;;
        *)
            CUSTOM_DOMAINS+=("$1")
            shift
            ;;
    esac
done

# Bepaal actieve layout
IS_COMPACT=0
if [ "$LAYOUT_MODE" = "compact" ]; then
    IS_COMPACT=1
elif [ "$LAYOUT_MODE" = "wide" ]; then
    IS_COMPACT=0
elif [ "$TERM_COLS" -lt 110 ]; then
    IS_COMPACT=1
fi

# Dynamische scheidingslijnen op maat van het scherm
HR_WIDTH="$TERM_COLS"
[ "$HR_WIDTH" -lt 60 ] && HR_WIDTH=80
HR=$(printf "%*s" "$HR_WIDTH" "" | tr ' ' '-')
BANNER_HR=$(printf "%*s" "$HR_WIDTH" "" | tr ' ' '=')

run_check() {
    echo -e "${BOLD}${BLUE}${BANNER_HR}${RESET}"
    echo -e "${BOLD}${BLUE}  Websites & Domeinnamen Check - Host: $(hostname -f) (${HOST_IP})${RESET}"
    echo -e "${GRAY}  Schermbreedte: ${TERM_COLS} tekens/regel | Modus: $([ $IS_COMPACT -eq 1 ] && echo 'Compact' || echo 'Breed') | Log: ${LOG_FILE}${RESET}"
    echo -e "${BOLD}${BLUE}${BANNER_HR}${RESET}"

    # 1. Apache VirtualHosts inventariseren
    declare -A VHOST_CONFS
    declare -A VHOST_ROOTS

    if command -v apache2ctl &>/dev/null || command -v apachectl &>/dev/null; then
        APACHE_BIN=$(command -v apache2ctl || command -v apachectl)
        while read -r line; do
            if [[ "$line" =~ port\ (80|443)\ namevhost\ ([^\ ]+)\ \(([^:]+) ]]; then
                port="${BASH_REMATCH[1]}"
                dom="${BASH_REMATCH[2],,}"
                conf=$(basename "${BASH_REMATCH[3]}")
                if [[ ! "$dom" =~ ^\* ]]; then
                    VHOST_CONFS["$dom"]="${VHOST_CONFS["$dom"]:-}${conf}:$port "
                fi
            elif [[ "$line" =~ alias\ ([^\ ]+) ]]; then
                dom="${BASH_REMATCH[1],,}"
                if [[ ! "$dom" =~ ^\* && "$dom" != "alias" ]]; then
                    VHOST_CONFS["$dom"]="${VHOST_CONFS["$dom"]:-}alias "
                fi
            fi
        done < <($APACHE_BIN -S 2>/dev/null)

        if [ -d "/etc/apache2/sites-enabled" ]; then
            for conf_file in /etc/apache2/sites-enabled/*; do
                [ -e "$conf_file" ] || continue
                snames=$(grep -Ei '^\s*(ServerName|ServerAlias)\s+' "$conf_file" 2>/dev/null | awk '{$1=""; print $0}')
                docroot=$(grep -Ei '^\s*DocumentRoot\s+' "$conf_file" 2>/dev/null | head -n1 | awk '{print $2}')
                if [ -n "$docroot" ]; then
                    for s in $snames; do
                        s="${s,,}"
                        if [[ ! "$s" =~ ^\* ]]; then
                            VHOST_ROOTS["$s"]="$docroot"
                        fi
                    done
                fi
            done
        fi
    fi

    # 2. Certbot SSL-certificaten inventariseren
    declare -A CERT_NAMES
    if command -v certbot &>/dev/null; then
        current_cert=""
        while read -r line; do
            if [[ "$line" =~ Certificate\ Name:\ (.+) ]]; then
                current_cert="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ Domains:\ (.+) && -n "$current_cert" ]]; then
                for d in ${BASH_REMATCH[1]}; do
                    CERT_NAMES["${d,,}"]="$current_cert"
                done
            fi
        done < <(certbot certificates 2>/dev/null)
    fi

    # 3. Domeinenlijst opbouwen
    DOMAINS_MAP=()
    declare -A SEEN_DOMAINS

    add_domain() {
        local d="${1,,}"
        d=$(echo "$d" | tr -d ' ' | tr -d '\r')
        if [[ -n "$d" && -z "${SEEN_DOMAINS["$d"]}" && ! "$d" =~ ^\* ]]; then
            SEEN_DOMAINS["$d"]=1
            DOMAINS_MAP+=("$d")
        fi
    }

    if [ ${#CUSTOM_DOMAINS[@]} -gt 0 ]; then
        for cd in "${CUSTOM_DOMAINS[@]}"; do
            add_domain "$cd"
        done
    else
        for vd in "${!VHOST_CONFS[@]}"; do
            add_domain "$vd"
        done
        for cd in "${!CERT_NAMES[@]}"; do
            add_domain "$cd"
        done

        if [ "$FILTER_MODE" = "all" ] && [ -d "/var/www/vhosts" ]; then
            for item in /var/www/vhosts/*; do
                base=$(basename "$item")
                if [[ "$base" != .* && "$base" != _* && ! "$base" =~ \.(tgz|asc|zip)$ && "$base" != dokuwiki* && "$base" == *.* ]]; then
                    add_domain "$base"
                fi
            done
        fi
    fi

    IFS=$'\n' SORTED_DOMAINS=($(sort <<<"${DOMAINS_MAP[*]}"))
    unset IFS

    TOTAL_COUNT=${#SORTED_DOMAINS[@]}
    echo -e "${GRAY}Kandidaat-domeinen: ${TOTAL_COUNT} | Filter: ${FILTER_MODE}${RESET}\n"

    # Header afdrukken met exacte dynamische breedte per kolom
    if [ "$IS_COMPACT" -eq 1 ]; then
        # Vaste breedtes: DOMAIN(24) + " | " + DNS(8) + " | " + HTTP/S(7) + " | " + SSL(12) + " | " = 63 tekens
        DETAIL_MAX=$(( TERM_COLS - 63 ))
        [ "$DETAIL_MAX" -lt 12 ] && DETAIL_MAX=12
        printf "${BOLD}%-24s | %-8s | %-7s | %-12s | %s${RESET}\n" \
            "DOMEINNAAM" "DNS" "HTTP/S" "SSL CERT" "DETAILS / REDIRECT"
    else
        # Vaste breedtes: DOMAIN(28) + DNS(9) + HTTP(4) + HTTPS(5) + SSL(16) + DOCROOT(7) + 6x" | "(18) = 87 tekens
        DETAIL_MAX=$(( TERM_COLS - 87 ))
        [ "$DETAIL_MAX" -lt 15 ] && DETAIL_MAX=15
        printf "${BOLD}%-28s | %-9s | %-4s | %-5s | %-16s | %-7s | %s${RESET}\n" \
            "DOMEINNAAM" "DNS" "HTTP" "HTTPS" "SSL CERTIFICAAT" "DOCROOT" "REDIRECT / DETAILS"
    fi
    echo "$HR"

    COUNT_AGRARIX=0
    COUNT_HOME=0
    COUNT_EXT=0
    COUNT_DEAD=0

    for dom in "${SORTED_DOMAINS[@]}"; do
        # DNS Resolutie
        resolved_ips=($(getent ahosts "$dom" 2>/dev/null | awk '{print $1}' | sort -u))
        
        dns_status="DEAD"
        ip_summary=""

        if [ ${#resolved_ips[@]} -gt 0 ]; then
            ip_summary="${resolved_ips[0]}"
            for ip in "${resolved_ips[@]}"; do
                if [ "$ip" == "$HOST_IP" ]; then
                    dns_status="AGRARIX"
                    break
                elif [[ "$ip" == ${HOME_IP_PREFIX}* ]]; then
                    dns_status="HOME"
                    break
                fi
            done
            if [ "$dns_status" == "DEAD" ]; then
                dns_status="EXTERNAL"
            fi
        fi

        if [ "$FILTER_MODE" = "live" ] && [ "$dns_status" != "AGRARIX" ]; then
            continue
        fi
        if [ "$FILTER_MODE" = "migrated" ] && [ "$dns_status" != "HOME" ]; then
            continue
        fi

        case "$dns_status" in
            AGRARIX)  ((COUNT_AGRARIX++)) ;;
            HOME)     ((COUNT_HOME++)) ;;
            EXTERNAL) ((COUNT_EXT++)) ;;
            DEAD)     ((COUNT_DEAD++)) ;;
        esac

        # Docroot check
        docroot_status="${RED}NEE    ${RESET}"
        if [ -n "${VHOST_ROOTS["$dom"]}" ] && [ -d "${VHOST_ROOTS["$dom"]}" ]; then
            docroot_status="${GREEN}JA     ${RESET}"
        elif [ -d "/var/www/vhosts/$dom" ] || [ -d "/var/www/vhosts/www.$dom" ]; then
            docroot_status="${GREEN}JA     ${RESET}"
        fi

        # HTTP Probe (timeout 2s)
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 -m 3 "http://$dom/" 2>/dev/null)
        [ -z "$http_code" ] || [ "$http_code" == "000" ] && http_code="ERR"

        redir_dest=""
        if [ "$http_code" == "301" ] || [ "$http_code" == "302" ]; then
            redir_dest=$(curl -s -I --connect-timeout 2 -m 3 "http://$dom/" 2>/dev/null | grep -i '^Location:' | head -n1 | cut -d' ' -f2- | tr -d '\r')
        elif [ "$http_code" == "200" ]; then
            meta_target=$(curl -s --connect-timeout 2 -m 3 "http://$dom/" 2>/dev/null | grep -iE 'http-equiv=.*refresh' | head -n1 | sed -r 's/.*url=([^"'\'' >]+).*/\1/I')
            if [ -n "$meta_target" ]; then
                redir_dest="${meta_target} (meta)"
            fi
        fi

        # HTTPS Probe (timeout 2s)
        https_code=$(curl -s -k -o /dev/null -w "%{http_code}" --connect-timeout 2 -m 3 "https://$dom/" 2>/dev/null)
        [ -z "$https_code" ] || [ "$https_code" == "000" ] && https_code="ERR"

        # Details / Redirect
        details=""
        if [ -n "$redir_dest" ]; then
            details="➔ ${redir_dest}"
        elif [ "$dns_status" == "HOME" ]; then
            details="PVE (${ip_summary})"
        elif [ "$dns_status" == "EXTERNAL" ]; then
            details="Ext (${ip_summary})"
        elif [ "$dns_status" == "DEAD" ]; then
            details="Geen DNS"
        elif [ -n "${VHOST_CONFS["$dom"]}" ]; then
            details="${VHOST_CONFS["$dom"]}"
        fi

        # Details netjes afkappen op maat van het scherm (voorkomt regel-wraps)
        if [ ${#details} -gt "$DETAIL_MAX" ]; then
            cut_len=$(( DETAIL_MAX - 1 ))
            details="${details:0:$cut_len}…"
        fi

        # Exact uitgelijnde kolommen per layout (inclusief kleurcodes zonder printf-afwijkingen)
        if [ "$IS_COMPACT" -eq 1 ]; then
            # DNS (8 tekens zichtbaar)
            case "$dns_status" in
                AGRARIX)  dns_col="${GREEN}AGRARIX ${RESET}" ;;
                HOME)     dns_col="${CYAN}PVE-HOME${RESET}" ;;
                EXTERNAL) dns_col="${YELLOW}EXTERN  ${RESET}" ;;
                DEAD)     dns_col="${RED}GEEN DNS${RESET}" ;;
            esac

            # SSL (12 tekens zichtbaar)
            ssl_col="${GRAY}-           ${RESET}"
            if [ -n "${CERT_NAMES["$dom"]}" ]; then
                cert_name="${CERT_NAMES["$dom"]}"
                if [ -f "/etc/letsencrypt/live/$cert_name/cert.pem" ]; then
                    enddate=$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$cert_name/cert.pem" 2>/dev/null | cut -d= -f2)
                    if [ -n "$enddate" ]; then
                        exp_epoch=$(date -d "$enddate" +%s 2>/dev/null || echo 0)
                        now_epoch=$(date +%s)
                        days_left=$(( (exp_epoch - now_epoch) / 86400 ))
                        short_c="${cert_name%%.*}"
                        [ -z "$short_c" ] && short_c="${cert_name:0:6}"
                        tag=$(printf "%2dd:%-8s" "$days_left" "${short_c:0:8}")
                        tag="${tag:0:12}"
                        if [ $days_left -le 15 ]; then
                            ssl_col="${RED}${tag}${RESET}"
                        elif [ $days_left -le 30 ]; then
                            ssl_col="${YELLOW}${tag}${RESET}"
                        else
                            ssl_col="${GREEN}${tag}${RESET}"
                        fi
                    fi
                fi
            fi

            combo_http="${http_code}/${https_code}"
            printf "%-24s | %b | %-7s | %b | %-s\n" \
                "${dom:0:24}" "$dns_col" "$combo_http" "$ssl_col" "$details"
        else
            # DNS (9 tekens zichtbaar)
            case "$dns_status" in
                AGRARIX)  dns_col="${GREEN}AGRARIX  ${RESET}" ;;
                HOME)     dns_col="${CYAN}PVE-HOME ${RESET}" ;;
                EXTERNAL) dns_col="${YELLOW}EXTERN   ${RESET}" ;;
                DEAD)     dns_col="${RED}GEEN DNS ${RESET}" ;;
            esac

            # SSL (16 tekens zichtbaar)
            ssl_col="${GRAY}-               ${RESET}"
            if [ -n "${CERT_NAMES["$dom"]}" ]; then
                cert_name="${CERT_NAMES["$dom"]}"
                if [ -f "/etc/letsencrypt/live/$cert_name/cert.pem" ]; then
                    enddate=$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$cert_name/cert.pem" 2>/dev/null | cut -d= -f2)
                    if [ -n "$enddate" ]; then
                        exp_epoch=$(date -d "$enddate" +%s 2>/dev/null || echo 0)
                        now_epoch=$(date +%s)
                        days_left=$(( (exp_epoch - now_epoch) / 86400 ))
                        tag=$(printf "%2dd: %-11s" "$days_left" "${cert_name:0:11}")
                        tag="${tag:0:16}"
                        if [ $days_left -le 15 ]; then
                            ssl_col="${RED}${tag}${RESET}"
                        elif [ $days_left -le 30 ]; then
                            ssl_col="${YELLOW}${tag}${RESET}"
                        else
                            ssl_col="${GREEN}${tag}${RESET}"
                        fi
                    fi
                fi
            fi

            printf "%-28s | %b | %-4s | %-5s | %b | %b | %-s\n" \
                "${dom:0:28}" "$dns_col" "$http_code" "$https_code" "$ssl_col" "$docroot_status" "$details"
        fi
    done

    echo "$HR"
    echo -e "${BOLD}Samenvatting:${RESET}"
    echo -e "  Actief op ${GREEN}agrarix.it${RESET} (${HOST_IP}):   ${BOLD}${COUNT_AGRARIX}${RESET}"
    echo -e "  Gemigreerd naar ${CYAN}Proxmox Home${RESET} (${HOME_IP_PREFIX}x): ${BOLD}${COUNT_HOME}${RESET}"
    echo -e "  Verwezen naar ${YELLOW}Extern IP${RESET}:           ${BOLD}${COUNT_EXT}${RESET}"
    echo -e "  Niet-bestaand / ${RED}Geen DNS${RESET}:            ${BOLD}${COUNT_DEAD}${RESET}"
    echo ""
}

# ------------------------------------------------------------------------------
# Uitvoering met live weergave op het scherm én automatische logging naar file
# ------------------------------------------------------------------------------
{
    echo -e "\n=== active-domain-check gestart op $(date '+%Y-%m-%d %H:%M:%S') door user ${LOG_USER} ==="
} >> "$LOG_FILE"

run_check | tee >(sed -r "s/\x1B\[[0-9;]*[mK]//g" >> "$LOG_FILE")

# Zorg voor correcte bestandseigenaar op logbestand
chown "${LOG_USER}:" "$LOG_FILE" 2>/dev/null
