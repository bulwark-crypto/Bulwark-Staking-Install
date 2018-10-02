#!/bin/bash

VPSTARBALLURL=$(curl -s https://api.github.com/repos/bulwark-crypto/bulwark/releases/latest | grep browser_download_url | grep -e "bulwark-node.*linux64" | cut -d '"' -f 4)
VPSTARBALLNAME=$(curl -s https://api.github.com/repos/bulwark-crypto/bulwark/releases/latest | grep browser_download_url | grep -e "bulwark-node.*linux64" | cut -d '"' -f 4 | cut -d "/" -f 9)
SHNTARBALLURL=$(curl -s https://api.github.com/repos/bulwark-crypto/bulwark/releases/latest | grep browser_download_url | grep -e "bulwark-node.*ARM" | cut -d '"' -f 4)
SHNTARBALLNAME=$(curl -s https://api.github.com/repos/bulwark-crypto/bulwark/releases/latest | grep browser_download_url | grep -e "bulwark-node.*ARM" | cut -d '"' -f 4 | cut -d "/" -f 9)
BWKVERSION=$(curl -s https://api.github.com/repos/bulwark-crypto/bulwark/releases/latest | grep browser_download_url | grep -e "bulwark-node.*ARM" | cut -d '"' -f 4 | cut -d "/" -f 8)

clear
echo "This script will update your wallet to version $BWKVERSION"
read -rp "Press Ctrl-C to abort or any other key to continue. " -n1 -s
clear

if [ "$(id -u)" != "0" ]; then
  echo "This script must be run as root."
  exit 1
fi

USER="bulwark"
USERHOME="/home/bulwark"

echo "Shutting down wallet..."
if [ -e /etc/systemd/system/bulwarkd.service ]; then
  systemctl stop bulwarkd
else
  su -c "bulwark-cli stop" "bulwark"
fi

echo "Downloading and installing binaries..."
if grep -q "ARMv7" /proc/cpuinfo; then
  # Install Bulwark daemon for ARMv7 systems
  wget "$SHNTARBALLURL"
  sudo tar -xzvf "$SHNTARBALLNAME" -C /usr/local/bin
  rm "$SHNTARBALLNAME"
else
  # Install Bulwark daemon for x86 systems
  wget "$VPSTARBALLURL"
  sudo tar -xzvf "$VPSTARBALLNAME" -C /usr/local/bin
  rm "$VPSTARBALLNAME"
fi

if [ -e /usr/bin/bulwarkd ];then rm -rf /usr/bin/bulwarkd; fi
if [ -e /usr/bin/bulwark-cli ];then rm -rf /usr/bin/bulwark-cli; fi
if [ -e /usr/bin/bulwark-tx ];then rm -rf /usr/bin/bulwark-tx; fi

# Remove addnodes from bulwark.conf
sed -i '/^addnode/d' "/home/bulwark/.bulwark/bulwark.conf"

# Add Fail2Ban memory hack if needed
if ! grep -q "ulimit -s 256" /etc/default/fail2ban; then
  echo "ulimit -s 256" | sudo tee -a /etc/default/fail2ban
  systemctl restart fail2ban
fi

echo "Restarting Bulwark daemon..."
if [ -e /etc/systemd/system/bulwarkd.service ]; then
  systemctl disable bulwarkd
  rm /etc/systemd/system/bulwarkd.service
fi

cat > /etc/systemd/system/bulwarkd.service << EOL
[Unit]
Description=Bulwarks's distributed currency daemon
After=network.target
[Service]
Type=forking
User=${USER}
WorkingDirectory=${USERHOME}
ExecStart=/usr/local/bin/bulwarkd -conf=${USERHOME}/.bulwark/bulwark.conf -datadir=${USERHOME}/.bulwark
ExecStop=/usr/local/bin/bulwark-cli -conf=${USERHOME}/.bulwark/bulwark.conf -datadir=${USERHOME}/.bulwark stop
Restart=on-failure
RestartSec=1m
StartLimitIntervalSec=5m
StartLimitInterval=5m
StartLimitBurst=3
[Install]
WantedBy=multi-user.target
EOL
sudo systemctl enable bulwarkd
sudo systemctl start bulwarkd

until [ -n "$(bulwark-cli getconnectioncount 2>/dev/null)"  ]; do
  sleep 1
done

clear

echo "Your wallet is syncing. Please wait for this process to finish."

until su -c "bulwark-cli mnsync status 2>/dev/null | grep '\"IsBlockchainSynced\" : true' > /dev/null" "bulwark"; do
  for (( i=0; i<${#CHARS}; i++ )); do
    sleep 2
    echo -en "${CHARS:$i:1}" "\\r"
  done
done

clear

echo "Bulwark is now up to date. Do not forget to unlock your wallet!"
