#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

show_header() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║          ${WHITE}DOMAIN DETECTOR - Server Administration${PURPLE}           ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${CYAN}Server:${NC} $(hostname)"
    echo -e "${CYAN}Tanggal:${NC} $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${CYAN}User:${NC} $(whoami)"
    echo ""
}

show_banner() {
    echo -e "${CYAN}"
    echo "    ____  ___                    .__   "
    echo "    \   \/  /___________ __  _  _|  |  "
    echo "     \     /\_  __ \__  \\ \/ \/ /  |  "
    echo "     /     \ |  | \// __ \\     /|  |__"
    echo "    /___/\  \|__|  (____  /\/\_/ |____/"
    echo "          \_/           \/             "
    echo -e "${NC}"
}

detect_from_cpanel() {
    local user=$1
    local domains=()
    
    if [ -f "/var/cpanel/userdata/$user/main" ]; then
        domains+=($(grep "^serveralias" "/var/cpanel/userdata/$user/main" | awk '{print $2}'))
    fi
    
    if [ -d "/var/cpanel/userdata/$user" ]; then
        for file in /var/cpanel/userdata/$user/*; do
            if [ -f "$file" ]; then
                domains+=($(grep -E "^serveralias|ServerName" "$file" 2>/dev/null | awk '{print $2}'))
            fi
        done
    fi
    
    printf '%s\n' "${domains[@]}" | sort -u
}

detect_from_vhost() {
    local user=$1
    local domains=()
    local vhost_paths=(
        "/etc/apache2/sites-enabled/"
        "/etc/httpd/conf.d/"
        "/usr/local/apache/conf/extra/"
        "/etc/apache2/sites-available/"
        "/etc/nginx/sites-enabled/"
        "/etc/nginx/conf.d/"
    )
    
    for vhost_path in "${vhost_paths[@]}"; do
        if [ -d "$vhost_path" ]; then
            for file in "$vhost_path"*.conf; do
                if [ -f "$file" ]; then
                    domains+=($(grep -E "^[[:space:]]*ServerName|^[[:space:]]*ServerAlias" "$file" 2>/dev/null | awk '{print $2}'))
                    domains+=($(grep -E "server_name" "$file" 2>/dev/null | awk '{print $2}' | tr -d ';'))
                fi
            done 2>/dev/null
        fi
    done
    
    printf '%s\n' "${domains[@]}" | sort -u
}

detect_from_dns() {
    local domains=()
    local dns_files=(
        "/etc/hosts"
        "/etc/resolv.conf"
        "/var/named/*.hosts"
        "/etc/bind/*.hosts"
    )
    
    for dns_file in "${dns_files[@]}"; do
        if [ -f "$dns_file" ]; then
            domains+=($(grep -E "^[0-9]" "$dns_file" 2>/dev/null | awk '{print $2}'))
        fi
    done
    
    printf '%s\n' "${domains[@]}" | sort -u
}

detect_from_system() {
    local domains=()
    
    domains+=($(hostname -f 2>/dev/null))
    domains+=($(hostname 2>/dev/null))
    
    if [ -f "/etc/sysconfig/network" ]; then
        domains+=($(grep "^HOSTNAME" "/etc/sysconfig/network" 2>/dev/null | cut -d= -f2))
    fi
    
    if [ -f "/etc/hostname" ]; then
        domains+=($(cat "/etc/hostname" 2>/dev/null))
    fi
    
    printf '%s\n' "${domains[@]}" | sort -u
}

detect_from_logs() {
    local user=$1
    local domains=()
    local log_files=(
        "/usr/local/apache/domlogs/$user/*"
        "/var/log/apache2/domlogs/$user/*"
        "/var/log/httpd/domlogs/$user/*"
    )
    
    for log_pattern in "${log_files[@]}"; do
        for log_file in $log_pattern; do
            if [ -f "$log_file" ]; then
                domain=$(basename "$log_file" | sed 's/\.[^.]*$//')
                domains+=("$domain")
            fi
        done 2>/dev/null
    done
    
    printf '%s\n' "${domains[@]}" | sort -u
}

detect_from_public_html() {
    local user=$1
    local domains=()
    
    if [ -d "/home/$user/public_html" ]; then
        if [ -f "/home/$user/public_html/.htaccess" ]; then
            domains+=($(grep -i "ServerName" "/home/$user/public_html/.htaccess" 2>/dev/null | awk '{print $2}'))
        fi
    fi
    
    printf '%s\n' "${domains[@]}" | sort -u
}

show_domains() {
    local user=$1
    local all_domains=()
    
    echo -e "${GREEN}Mendeteksi domain untuk user: ${WHITE}$user${NC}"
    echo -e "${YELLOW}----------------------------------------${NC}"
    
    echo -e "${BLUE}[*] Memeriksa cPanel...${NC}"
    all_domains+=($(detect_from_cpanel "$user"))
    
    echo -e "${BLUE}[*] Memeriksa Virtual Host...${NC}"
    all_domains+=($(detect_from_vhost "$user"))
    
    echo -e "${BLUE}[*] Memeriksa DNS...${NC}"
    all_domains+=($(detect_from_dns))
    
    echo -e "${BLUE}[*] Memeriksa System...${NC}"
    all_domains+=($(detect_from_system))
    
    echo -e "${BLUE}[*] Memeriksa Logs...${NC}"
    all_domains+=($(detect_from_logs "$user"))
    
    echo -e "${BLUE}[*] Memeriksa Public HTML...${NC}"
    all_domains+=($(detect_from_public_html "$user"))
    
    local unique_domains=($(printf '%s\n' "${all_domains[@]}" | grep -v "^$" | sort -u))
    
    echo -e "\n${GREEN}═══════════════════════════════════════════${NC}"
    echo -e "${WHITE}HASIL DETEKSI DOMAIN${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════${NC}"
    
    if [ ${#unique_domains[@]} -eq 0 ]; then
        echo -e "${RED}Tidak ada domain yang terdeteksi untuk user: $user${NC}"
    else
        local count=1
        for domain in "${unique_domains[@]}"; do
            echo -e "${CYAN}[${count}]${NC} ${WHITE}$domain${NC}"
            ((count++))
        done
        echo -e "\n${GREEN}Total domain ditemukan: ${WHITE}${#unique_domains[@]}${NC}"
    fi
    echo -e "${GREEN}═══════════════════════════════════════════${NC}"
}

show_all_users() {
    echo -e "${BLUE}[*] Mendapatkan daftar user...${NC}"
    local users=()
    
    if [ -d "/home" ]; then
        for user in /home/*; do
            if [ -d "$user" ]; then
                users+=($(basename "$user"))
            fi
        done
    fi
    
    if [ -d "/var/cpanel/users" ]; then
        for user in /var/cpanel/users/*; do
            if [ -f "$user" ]; then
                users+=($(basename "$user"))
            fi
        done
    fi
    
    users=($(printf '%s\n' "${users[@]}" | sort -u))
    
    echo -e "${GREEN}Ditemukan ${#users[@]} user${NC}\n"
    
    local total_domains=0
    for user in "${users[@]}"; do
        show_domains "$user"
        total_domains=$((total_domains + 1))
        echo ""
    done
    
    echo -e "${GREEN}═══════════════════════════════════════════${NC}"
    echo -e "${WHITE}Total user diproses: ${total_domains}${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════${NC}"
}

show_specific_user() {
    local user=$1
    if [ -z "$user" ]; then
        echo -e "${RED}Error: Nama user tidak boleh kosong!${NC}"
        return 1
    fi
    
    if [ ! -d "/home/$user" ] && [ ! -f "/var/cpanel/users/$user" ]; then
        echo -e "${RED}Error: User $user tidak ditemukan!${NC}"
        return 1
    fi
    
    show_domains "$user"
}

search_domains() {
    local pattern=$1
    if [ -z "$pattern" ]; then
        echo -e "${RED}Error: Pola pencarian tidak boleh kosong!${NC}"
        return 1
    fi
    
    echo -e "${BLUE}[*] Mencari domain dengan pola: ${WHITE}$pattern${NC}"
    echo -e "${YELLOW}----------------------------------------${NC}"
    
    local found=0
    local users=()
    
    if [ -d "/home" ]; then
        for user in /home/*; do
            if [ -d "$user" ]; then
                users+=($(basename "$user"))
            fi
        done
    fi
    
    for user in "${users[@]}"; do
        local domains=($(detect_from_cpanel "$user") $(detect_from_vhost "$user"))
        for domain in "${domains[@]}"; do
            if [[ "$domain" == *"$pattern"* ]]; then
                echo -e "${GREEN}User: ${WHITE}$user${NC} -> ${CYAN}$domain${NC}"
                found=1
            fi
        done
    done
    
    if [ $found -eq 0 ]; then
        echo -e "${RED}Tidak ada domain yang cocok dengan pola: $pattern${NC}"
    fi
}

main_menu() {
    while true; do
        show_header
        show_banner
        echo -e "${WHITE}Pilih opsi:${NC}"
        echo -e "  ${GREEN}1${NC}) Deteksi semua user"
        echo -e "  ${GREEN}2${NC}) Deteksi user spesifik"
        echo -e "  ${GREEN}3${NC}) Cari domain berdasarkan pola"
        echo -e "  ${GREEN}4${NC}) Keluar"
        echo ""
        echo -ne "${CYAN}Pilihan: ${NC}"
        read choice
        
        case $choice in
            1)
                show_all_users
                echo ""
                echo -ne "${YELLOW}Tekan Enter untuk kembali...${NC}"
                read
                ;;
            2)
                echo -ne "${CYAN}Masukkan nama user: ${NC}"
                read username
                show_specific_user "$username"
                echo ""
                echo -ne "${YELLOW}Tekan Enter untuk kembali...${NC}"
                read
                ;;
            3)
                echo -ne "${CYAN}Masukkan pola pencarian (contoh: .com, domain): ${NC}"
                read pattern
                search_domains "$pattern"
                echo ""
                echo -ne "${YELLOW}Tekan Enter untuk kembali...${NC}"
                read
                ;;
            4)
                echo -e "${GREEN}Terima kasih!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Pilihan tidak valid!${NC}"
                sleep 1
                ;;
        esac
    done
}

if [ "$1" == "-u" ] && [ -n "$2" ]; then
    show_header
    show_banner
    show_specific_user "$2"
elif [ "$1" == "-s" ] && [ -n "$2" ]; then
    show_header
    show_banner
    search_domains "$2"
elif [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    show_header
    show_banner
    echo -e "${WHITE}Penggunaan:${NC}"
    echo -e "  ./xrawl.sh           - Menu interaktif"
    echo -e "  ./xrawl.sh -u USER   - Deteksi domain untuk user spesifik"
    echo -e "  ./xrawl.sh -s POLA   - Cari domain berdasarkan pola"
    echo -e "  ./xrawl.sh -h        - Tampilkan bantuan"
else
    main_menu
fi
