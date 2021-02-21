#!/bin/bash

## Grabbing information
tokens=$1
username=$2
password=$3
qbport=$4
port=$5
cache=$6
publicip=$(curl https://ipinfo.io/ip)

# Load Functions
curl -s -O https://$tokens@raw.githubusercontent.com/jerry048/Seedbox-Install-Components/main/.seedbox_installation.sh
source .seedbox_installation.sh

# Define qBittorrent Config
function qbittorrent_config {
    mkdir -p $HOME/.config/qBittorrent
    touch $HOME/.config/qBittorrent/qBittorrent.conf
    if [[ "${version}" =~ "4.1." ]]; then
        md5password=$(echo -n $password | md5sum | awk '{print $1}')
        cat << EOF >$HOME/.config/qBittorrent/qBittorrent.conf
[LegalNotice]
Accepted=true

[Network]
Cookies=@Invalid()

[Preferences]
Connection\PortRangeMin=$port
Downloads\DiskWriteCacheSize=$cache
Downloads\SavePath=$HOME/qbittorrent/Downloads/
Queueing\QueueingEnabled=false
WebUI\Password_ha1=@ByteArray($md5password)
WebUI\Port=$qbport
WebUI\Username=$username
EOF
    elif [[ "${version}" =~ "4.2."|"4.3." ]]; then
        curl -s -O https://$tokens@raw.githubusercontent.com/jerry048/Seedbox-Install-Components/main/qb_password_gen && chmod +x $HOME/qb_password_gen
        PBKDF2password=$($HOME/qb_password_gen $password)
        cat << EOF >$HOME/.config/qBittorrent/qBittorrent.conf
[LegalNotice]
Accepted=true

[Network]
Cookies=@Invalid()

[Preferences]
Connection\PortRangeMin=$port
Downloads\DiskWriteCacheSize=$cache
Downloads\SavePath=$HOME/qbittorrent/Downloads/
Queueing\QueueingEnabled=false
WebUI\Password_PBKDF2="@ByteArray($PBKDF2password)"
WebUI\Port=$qbport
WebUI\Username=$username
EOF
        rm $HOME/qb_password_gen
    fi
}

# qBittorrent Download
cd $HOME
qBittorrent_version
mkdir -p $HOME/bin
mv $HOME/qbittorrent-nox $HOME/bin/qbittorrent-nox

# qBittorrent Install
tput setaf 2; echo "How to install qBittorrent:"
options=("Local user service" "Screen" "Daemon")
select opt in "${options[@]}"
do
    case $opt in
        "Local user service")
            e=0; break
            ;;
        "Screen")
            e=1; break
            ;;
        "Daemon")
            e=2; break
            ;;
        *) tput setaf 1; echo "Please choose a valid version";;
    esac
done

# qBittorrent local user service
if [ "${e}" == "0" ]; then
    qbittorrent_config
    mkdir -p $HOME/.config/systemd/user/
    touch $HOME/.config/systemd/user/qbittorrent-nox.service
    cat <<EOF> $HOME/.config/systemd/user/qbittorrent-nox.service
[Unit]
Description=qbittorrent-nox
Wants=network-online.target
After=network-online.target nss-lookup.target

[Service]
Type=exec
ExecStart=%h/bin/qbittorrent-nox
Restart=on-failure
SyslogIdentifier=qbittorrent-nox

[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable qbittorrent-nox.service
    systemctl --user start qbittorrent
# Screen
elif [ "${e}" == "1" ]; then
    qbittorrent_config
    screen -dmS qBittorrent-nox $HOME/bin/qbittorrent-nox
    # Automatic Restart
    touch $HOME/qBittorrent-restart.sh
    cat <<EOF> $HOME/qBittorrent-restart.sh
#!/bin/bash

[[ $(pgrep -f 'qbittorrent-nox') ]] || screen -dmS qBittorrent-nox $HOME/bin/qbittorrent-nox
EOF
    crontab -l | { cat; echo "*/1 * * * * $HOME/.qBittorrent-restart.sh"; } | crontab -

# Daemon
elif [ "${e}" == "2" ]; then
    qbittorrent_config
    $HOME/bin/qbittorrent-nox -d
    # Automatic Restart
    touch $HOME/qBittorrent-restart.sh
    cat <<EOF> $HOME/qBittorrent-restart.sh
#!/bin/bash

[[ $(pgrep -f 'qbittorrent-nox') ]] || $HOME/bin/qbittorrent-nox -d
EOF
    crontab -l | { cat; echo "*/1 * * * * $HOME/.qBittorrent-restart.sh"; } | crontab -
fi

if [ ! $? -eq 0 ]; then
    tput setaf 1; echo "qBittorrent installation failed, try another method"
    rm $HOME/bin/qbittorrent-nox
    rm -r $HOME/.config/qBittorrent
    exit 1
fi

# autoremove-torrents
Decision2 qBittorrent
if [ "${e}" == "0" ]; then
    tput setaf 2
    read -p "Enter desired reserved storage (in GiB): " diskspace
    read -p "Enter desired minimum seedtime (in Second): " seedtime
    tput setaf 2; echo "How to install autoremove-torrents:"
    options=("pip" "python3")
    select opt in "${options[@]}"
    do
        case $opt in
            "pip")
                e=0; break
                ;;
            "python3")
                e=1; break
                ;;
            *) tput setaf 1; echo "Please choose a valid version";;
        esac
    done
    if [ "${e}" == "0" ]; then
        pip install autoremove-torrents
    elif [ "${e}" == "1" ]; then
        git clone https://github.com/jerrymakesjelly/autoremove-torrents.git
        cd autoremove-torrents
        python3 setup.py install --prefix $HOME/.local/
        cd $HOME && rm -r autoremove-torrents
    fi
    if [ ! $? -eq 0 ]; then
        tput setaf 1; echo "autoremove-torrents installation failed"
        rm $HOME/.local/bin/autoremove-torrents
        exit 1
    fi
    touch $HOME/.config.yml
    cat << EOF >>$HOME/.config.yml
General-qb:          
  client: qbittorrent
  host: http://127.0.0.1:$qbport
  username: $username
  password: $password
  strategies:
    Upload:
      status:
        - Uploading
      remove: upload_speed < 1024 and seeding_time > $seedtime
    Leech:
      status:
        - Downloading
      remove: ratio < 1 and progress > 10 and download_speed > 20480
    Disk:
      free_space:
        min: $diskspace
        path: $HOME/
        action: remove-old-seeds
  delete_data: true
M-Team-qb:          
  client: qbittorrent
  host: http://127.0.0.1:$qbport
  username: $username
  password: $password
  strategies:
    Ratio:
      trackers:
        - tracker.m-team.cc
      upload_ratio: 3
  delete_data: true
EOF
    sed -i 's+127.0.0.1: +127.0.0.1:+g' $HOME/.config.yml
    mkdir $HOME/.autoremove-torrents
    touch $HOME/.autoremove.sh
    cat << EOF >$HOME/.autoremove.sh
#!/bin/sh

while true; do
  $HOME/.local/bin/autoremove-torrents --conf=$HOME/.config.yml --log=$HOME/.autoremove-torrents
  sleep 5
done
EOF
    chmod +x $HOME/.autoremove.sh
    screen -dmS autoremove-torrents $HOME/.autoremove.sh
fi


# Cleanup
rm $HOME/.seedbox_installation.sh
clear
echo "qBittorrent $version is successfully installed, visit at $publicip:$qbport"
echo "Username is $username, Password is $password"