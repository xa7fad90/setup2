#!/bin/bash

VERSION=2.11

# printing greetings
echo "Hashvault mining setup script v$VERSION."
echo "(please report issues to support@hashvault.pro email with full output of this script with extra \"-x\" \"bash\" option)"
echo

if [ "$(id -u)" == "0" ]; then
  echo "WARNING: Generally it is not advised to run this script under root"
fi

# command line arguments
WALLET=$1
EMAIL=$2 # this one is optional

# checking prerequisites
if [ -z $WALLET ]; then
  echo "Script usage:"
  echo "> setup_hashvault_miner.sh <wallet address> [<your email address>]"
  echo "ERROR: Please specify your wallet address"
  exit 1
fi

WALLET_BASE=`echo $WALLET | cut -f1 -d"."`
if [ ${#WALLET_BASE} != 106 -a ${#WALLET_BASE} != 95 ]; then
  echo "ERROR: Wrong wallet base address length (should be 106 or 95): ${#WALLET_BASE}"
  exit 1
fi

if [ -z $HOME ]; then
  echo "ERROR: Please define HOME environment variable to your home directory"
  exit 1
fi

if [ ! -d $HOME ]; then
  echo "ERROR: Please make sure HOME directory $HOME exists or set it yourself using this command:"
  echo '  export HOME=<dir>'
  exit 1
fi

if ! type curl >/dev/null; then
  echo "ERROR: This script requires \"curl\" utility to work correctly"
  exit 1
fi

if ! type lscpu >/dev/null; then
  echo "WARNING: This script requires \"lscpu\" utility to work correctly"
fi

# printing intentions
echo "I will download, setup and run in background XMRig CPU miner."
echo "If needed, miner in foreground can be started by $HOME/hashvault/miner.sh script."
echo "Mining will happen to $WALLET wallet."
if [ ! -z $EMAIL ]; then
  echo "(and $EMAIL email as password to modify wallet options later at https://hashvault.pro site)"
fi
echo

if ! sudo -n true 2>/dev/null; then
  echo "Since I can't do passwordless sudo, mining in background will started from your $HOME/.profile file first time you login this host after reboot."
else
  echo "Mining in background will be performed using hashvault_miner systemd service."
fi

echo
echo "Sleeping for 15 seconds before continuing (press Ctrl+C to cancel)"
sleep 15
echo
echo

# start doing stuff: preparing miner
echo "[*] Removing previous Hashvault miner (if any)"
if sudo -n true 2>/dev/null; then
  sudo systemctl stop hashvault_miner.service
fi
killall -9 xmrig

echo "[*] Removing $HOME/hashvault directory"
rm -rf $HOME/hashvault

echo "[*] Downloading XMRig to /tmp/xmrig.tar.gz"
if ! curl -L --progress-bar "https://github.com/xmrig/xmrig/releases/download/v6.16.4/xmrig-6.16.4-linux-static-x64.tar.gz" -o /tmp/xmrig.tar.gz; then
  echo "ERROR: Can't download XMRig archive to /tmp/xmrig.tar.gz"
  exit 1
fi

echo "[*] Unpacking /tmp/xmrig.tar.gz to $HOME/hashvault"
[ -d $HOME/hashvault ] || mkdir $HOME/hashvault
if ! tar xf /tmp/xmrig.tar.gz -C $HOME/hashvault --strip=1; then
  echo "ERROR: Can't unpack /tmp/xmrig.tar.gz to $HOME/hashvault directory"
  exit 1
fi
rm /tmp/xmrig.tar.gz

echo "[*] Checking if XMRig works fine (and not removed by antivirus software)"
sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' $HOME/hashvault/config.json
$HOME/hashvault/xmrig --help >/dev/null
if (test $? -ne 0); then
  if [ -f $HOME/hashvault/xmrig ]; then
    echo "ERROR: XMRig is not functional"
  else 
    echo "ERROR: XMRig was removed by antivirus"
  fi
  exit 1
fi

echo "[*] Miner $HOME/hashvault/xmrig is OK"

PASS=`hostname | cut -f1 -d"." | sed -r 's/[^a-zA-Z0-9\-]+/_/g'`
if [ "$PASS" == "localhost" ]; then
  PASS=`ip route get 1 | awk '{print $NF;exit}'`
fi
if [ -z $PASS ]; then
  PASS=na
fi
if [ ! -z $EMAIL ]; then
  PASS="$PASS:$EMAIL"
fi

sed -i 's/"url": *"[^"]*",/"url": "pool.hashvault.pro:443",/' $HOME/hashvault/config.json
sed -i 's/"user": *"[^"]*",/"user": "'$WALLET'",/' $HOME/hashvault/config.json
sed -i 's/"pass": *"[^"]*",/"pass": "'$PASS'",/' $HOME/hashvault/config.json
sed -i 's/"max-cpu-usage": *[^,]*,/"max-cpu-usage": 100,/' $HOME/hashvault/config.json
sed -i 's#"log-file": *null,#"log-file": "'$HOME/hashvault/xmrig.log'",#' $HOME/hashvault/config.json
sed -i 's/"syslog": *[^,]*,/"syslog": true,/' $HOME/hashvault/config.json

cp $HOME/hashvault/config.json $HOME/hashvault/config_background.json
sed -i 's/"background": *false,/"background": true,/' $HOME/hashvault/config_background.json

# preparing script
echo "[*] Creating $HOME/hashvault/miner.sh script"
cat >$HOME/hashvault/miner.sh <<EOL
#!/bin/bash
if ! pidof xmrig >/dev/null; then
  nice $HOME/hashvault/xmrig \$*
else
  echo "Miner is already running in the background. Refusing to run another one."
  echo "Run \"killall xmrig\" or \"sudo killall xmrig\" if you want to remove background miner first."
fi
EOL

chmod +x $HOME/hashvault/miner.sh

# preparing script background work and work under reboot
if ! sudo -n true 2>/dev/null; then
  if ! grep hashvault/miner.sh $HOME/.profile >/dev/null; then
    echo "[*] Adding $HOME/hashvault/miner.sh script to $HOME/.profile"
    echo "$HOME/hashvault/miner.sh --config=$HOME/hashvault/config_background.json >/dev/null 2>&1" >>$HOME/.profile
  else 
    echo "Looks like $HOME/hashvault/miner.sh script is already in the $HOME/.profile"
  fi
  echo "[*] Running miner in the background (see logs in $HOME/hashvault/xmrig.log file)"
  /bin/bash $HOME/hashvault/miner.sh --config=$HOME/hashvault/config_background.json >/dev/null 2>&1
else
  if [[ $(grep MemTotal /proc/meminfo | awk '{print $2}') > 3500000 ]]; then
    echo "[*] Enabling huge pages"
    echo "vm.nr_hugepages=$((1168+$(nproc)))" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -w vm.nr_hugepages=$((1168+$(nproc)))
  fi

  if ! type systemctl >/dev/null; then
    echo "[*] Running miner in the background (see logs in $HOME/hashvault/xmrig.log file)"
    /bin/bash $HOME/hashvault/miner.sh --config=$HOME/hashvault/config_background.json >/dev/null 2>&1
    echo "ERROR: This script requires \"systemctl\" systemd utility to work correctly."
    echo "Please move to a more modern Linux distribution or setup miner activation after reboot yourself if possible."
  else
    echo "[*] Creating hashvault_miner systemd service"
    cat >/tmp/hashvault_miner.service <<EOL
[Unit]
Description=Hashvault miner service

[Service]
ExecStart=$HOME/hashvault/xmrig --config=$HOME/hashvault/config.json
Restart=always
Nice=10
CPUWeight=1

[Install]
WantedBy=multi-user.target
EOL
    sudo mv /tmp/hashvault_miner.service /etc/systemd/system/hashvault_miner.service
    echo "[*] Starting hashvault_miner systemd service"
    sudo killall xmrig 2>/dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable hashvault_miner.service
    sudo systemctl start hashvault_miner.service
    echo "To see miner service logs run \"sudo journalctl -u hashvault_miner -f\" command"
  fi
fi

echo ""
echo "NOTE: If you are using shared VPS it is recommended to avoid 100% CPU usage produced by the miner or you will be banned"
if [ "$CPU_THREADS" -lt "4" ]; then
  echo "HINT: Please execute these or similar commands under root to limit miner to 75% percent CPU usage:"
  echo "sudo apt-get update; sudo apt-get install -y cpulimit"
  echo "sudo cpulimit -e xmrig -l $((75*$CPU_THREADS)) -b"
  if [ "`tail -n1 /etc/rc.local`" != "exit 0" ]; then
    echo "sudo sed -i -e '\$acpulimit -e xmrig -l $((75*$CPU_THREADS)) -b\\n' /etc/rc.local"
  else
    echo "sudo sed -i -e '\$i \\cpulimit -e xmrig -l $((75*$CPU_THREADS)) -b\\n' /etc/rc.local"
  fi
else
  echo "HINT: Please execute these commands and reboot your VPS after that to limit miner to 75% percent CPU usage:"
  echo "sed -i 's/\"max-threads-hint\": *[^,]*,/\"max-threads-hint\": 75,/' \$HOME/hashvault/config.json"
  echo "sed -i 's/\"max-threads-hint\": *[^,]*,/\"max-threads-hint\": 75,/' \$HOME/hashvault/config_background.json"
fi
echo ""

echo "[*] Setup complete"
