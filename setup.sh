#!/bin/bash

function ask_user() {
    read -p "$1 (y/n): " choice
    case "$choice" in
        y|Y ) return 0;;
        * ) return 1;;
    esac
}

sed -i "s|^TZ=.*$|TZ=$(cat /etc/timezone)|" src/.env

 apt update

# Check if MySQL client is installed
if ! command -v mysql &> /dev/null
then
    echo "MySQL client is not installed. Installing mariadb-client now..."
     apt install -y mariadb-client
else
    echo "MySQL client is already installed."
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null
then
    echo "Docker is not installed. Installing Docker now..."
    # Add Docker's official GPG key:
     apt-get install ca-certificates curl
     install -m 0755 -d /etc/apt/keyrings
     curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
     chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to Apt sources:
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
       tee /etc/apt/sources.list.d/docker.list > /dev/null
     apt-get update
     apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
     usermod -aG docker $USER
    echo "::NOTE::"
    echo "Added your user to docker group to manage docker without root."
    echo "Log out and back in and rerun setup.sh."
    exit 1;
else
    echo "Docker is already installed."
fi

# Check if Azeroth Core is installed
if [ -d "azerothcore-wotlk" ]; then
    destination_dir="data/sql/custom"
    
    world=$destination_dir"/db_world/"
    chars=$destination_dir"/db_characters/"
    auth=$destination_dir"/db_auth/"
    
    cd azerothcore-wotlk
    
    rm -rf $world/*.sql
    rm -rf $chars/*.sql
    rm -rf $auth/*.sql
    
    cd ..
    
    cp src/.env azerothcore-wotlk/
    cp src/*.yml azerothcore-wotlk/
    cd azerothcore-wotlk
else
    if ask_user "Download and install AzerothCore Playerbots?"; then
        git clone https://github.com/liyunfan1223/azerothcore-wotlk.git --branch=Playerbot
        cp src/.env azerothcore-wotlk/
        cp src/*.yml azerothcore-wotlk/
        cd azerothcore-wotlk/modules
        git clone https://github.com/liyunfan1223/mod-playerbots.git --branch=master
        cd ..
    else
        echo "Aborting..."
        exit 1
    fi
fi

if ask_user "Install modules?"; then

    cd modules

    function install_mod() {
    local mod_name=$1
    local repo_url=$2

    if [ -d "${mod_name}" ]; then
        echo "${mod_name} exists. Skipping..."
    else
        if ask_user "Install ${mod_name}?"; then
            git clone "${repo_url}"
        fi
    fi
    }

    install_mod "mod-aoe-loot" "https://github.com/azerothcore/mod-aoe-loot.git"
    install_mod "mod-fireworks-on-level" "https://github.com/azerothcore/mod-fireworks-on-level.git"
    install_mod "mod-individual-progression" "https://github.com/ZhengPeiRu21/mod-individual-progression.git"
    install_mod "mod-autobalance" "https://github.com/azerothcore/mod-autobalance.git"
    install_mod "mod-ah-bot" "https://github.com/azerothcore/mod-ah-bot.git"
    install_mod "mod-transmog" "https://github.com/azerothcore/mod-transmog.git"
    install_mod "mod-challenge-modes" "https://github.com/ZhengPeiRu21/mod-challenge-modes.git"
    install_mod "mod-solo-lfg" "https://github.com/azerothcore/mod-solo-lfg.git"
    install_mod "mod-dungeon-respawn" "https://github.com/AnchyDev/DungeonRespawn.git"
    install_mod "mod-random-enchants" "https://github.com/azerothcore/mod-random-enchants.git"
    install_mod "mod-1v1-arena" "https://github.com/azerothcore/mod-1v1-arena.git"
    install_mod "mod-auctionator" "https://github.com/araxiaonline/mod-auctionator.git"
    install_mod "mod-weekend-xp" "https://github.com/azerothcore/mod-weekend-xp.git"
    install_mod "mod-npc-services" "https://github.com/azerothcore/mod-npc-services.git"
    install_mod "mod-npc-spectator" "https://github.com/Gozzim/mod-npc-spectator.git"

    cd ..

fi


docker compose up --build

cd ..

 if [ -d "wotlk" ]; then
    chown -R 1000:1000 wotlk
else
    echo "Error: Directory 'wotlk' does not exist. Creating it now..."
    mkdir wotlk
    chown -R 1000:1000 wotlk
fi

# Directory for custom SQL files
custom_sql_dir="src/sql"
auth="acore_auth"
world="acore_world"
chars="acore_characters"

ip_address=$(hostname -I | awk '{print $1}')

# Temporary SQL file
temp_sql_file="/tmp/temp_custom_sql.sql"

# Function to execute SQL files with IP replacement
function execute_sql() {
    local db_name=$1
    local sql_files=("$custom_sql_dir/$db_name"/*.sql)

    if [ -e "${sql_files[0]}" ]; then
        for custom_sql_file in "${sql_files[@]}"; do
            echo "Executing $custom_sql_file"
            temp_sql_file=$(mktemp)
            if [[ "$(basename "$custom_sql_file")" == "update_realmlist.sql" ]]; then
                sed -e "s/{{IP_ADDRESS}}/$ip_address/g" "$custom_sql_file" > "$temp_sql_file"
            else
                cp "$custom_sql_file" "$temp_sql_file"
            fi
            mysql -h "$ip_address" -uroot -ppassword "$db_name" < "$temp_sql_file"
        done
    else
        echo "No SQL files found in $custom_sql_dir/$db_name, skipping..."
    fi
}

# Run custom SQL files
echo "Running custom SQL files..."
execute_sql "$auth"
execute_sql "$world"
execute_sql "$chars"

# Clean up temporary file
rm "$temp_sql_file"

echo ""
echo "NOTE:"
echo ""
echo "!!! If ac-db-import failed, run ' chown -R 1000:1000 wotlk' and './setup.sh' again !!!"
echo ""
echo "1. Execute 'docker attach ac-worldserver'"
echo "2. 'account create username password' creates an account."
echo "3. 'account set gmlevel username 3 -1' sets the account as gm for all servers."
echo "4. Ctrl+p Ctrl+q will take you out of the world console."
echo "5. Edit your gameclients realmlist.wtf and set it to $ip_address."
echo "6. Now login to wow with 3.3.5a client!"
echo "7. All config files are copied into the wotlk folder created with setup.sh."

