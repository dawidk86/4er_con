#!/bin/bash
# --- COMMENTED LOGO (inserted by logo tool) ---
# [33m
# 
# ____________________ __            
# ______  /_  __ \_  // /____________
# ___ _  /_  / / /  // /_  _ \_  ___/
# / /_/ / / /_/ //__  __/  __/  /    
# \____/  \____/   /_/  \___//_/     
#  ➪  ᴊ04ᴇʀ ᴛᴏᴏʟꜱ ➪⠀
# 
# 
# 
# [0m
# --- END COMMENTED LOGO ---

# --- RUNTIME DISPLAY (runs on start) ---
_logo='[33m
____________________ __            
______  /_  __ \_  // /____________
___ _  /_  / / /  // /_  _ \_  ___/
/ /_/ / / /_/ //__  __/  __/  /    
\____/  \____/   /_/  \___//_/     
 ➪  ᴊ04ᴇʀ ᴛᴏᴏʟꜱ ➪⠀


[0m'
printf "%s\n" "$_logo"
sleep 3
# --- END RUNTIME ---


# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root"
  exit
fi

echo "### Starting Kali Linux Setup Script ###"

# 1. Update and Upgrade
echo "[+] Updating and Upgrading System..."
apt update
# apt upgrade -y kali-linux-default # This upgrades the specific metapackage
apt full-upgrade -y # Generally safer/more complete for Kali updates

# 2. Install Snapd and Telegram
echo "[+] Installing Snapd and Telegram..."
apt install -y snapd
systemctl enable --now snapd apparmor
# Note: Snap sometimes requires a logout/login to update paths. 
# We try to install immediately, but it might warn about paths.
snap install telegram-desktop

# 3. Enable and Start SSH
echo "[+] Enabling and Starting SSH..."
systemctl enable ssh
systemctl start ssh

# 4. Samba Configuration
echo "[+] Installing and Configuring Samba..."
apt install -y samba

# Create the folder
mkdir -p /smb43
chmod 777 /smb43
chown nobody:nogroup /smb43

# Backup original config
cp /etc/samba/smb.conf /etc/samba/smb.conf.bak

# Add share configuration to smb.conf
echo "
[smb43]
   path = /smb43
   browsable = yes
   writable = yes
   guest ok = yes
   read only = no
   create mask = 0777
   directory mask = 0777
" >> /etc/samba/smb.conf

# Interactive Samba User Setup
read -p "Do you want to create a Samba user with a password? (y/n): " create_smb_user
if [[ $create_smb_user =~ ^[Yy]$ ]]; then
    read -p "Enter Samba username: " smb_user
    # Check if user exists in system, if not create system user first (Samba requires it)
    if ! id "$smb_user" &>/dev/null; then
        useradd -m $smb_user
        echo "System user $smb_user created."
    fi
    echo "Set Samba password for $smb_user:"
    smbpasswd -a $smb_user
fi

systemctl enable smbd
systemctl restart smbd

# 5. Apache2 and PHP Configuration
echo "[+] Installing Apache2 and PHP..."
apt install -y apache2 php libapache2-mod-php

# Interactive Port Setup
read -p "Which port should Apache listen on? (Default 80): " apache_port
apache_port=${apache_port:-80}

if [ "$apache_port" != "80" ]; then
    echo "[+] Configuring Apache to listen on port $apache_port..."
    sed -i "s/Listen 80/Listen $apache_port/g" /etc/apache2/ports.conf
    sed -i "s/:80/:$apache_port/g" /etc/apache2/sites-enabled/000-default.conf
fi

# Create directory "j"
mkdir -p /var/www/html/j
chown www-data:www-data /var/www/html/j
chmod 755 /var/www/html/j
echo "<h1>Welcome to J</h1>" > /var/www/html/j/index.html

# Interactive Directory Protection
read -p "Do you want to password protect '/var/www/html/j'? (y/n): " protect_apache
if [[ $protect_apache =~ ^[Yy]$ ]]; then
    read -p "Enter username for Apache Auth: " apache_user
    htpasswd -c /etc/apache2/.htpasswd_j $apache_user
    
    # Inject directory config into the default site conf
    # This is a basic injection; for production, manual config is better.
    # We insert the Directory block before the closing </VirtualHost> tag.
    
    CONFIG_BLOCK="
    <Directory /var/www/html/j>
        AuthType Basic
        AuthName \"Restricted Content\"
        AuthUserFile /etc/apache2/.htpasswd_j
        Require valid-user
        Options Indexes FollowSymLinks
        AllowOverride All
    </Directory>"
    
    # Use sed to insert the block before </VirtualHost>
    sed -i "/<\/VirtualHost>/i $CONFIG_BLOCK" /etc/apache2/sites-enabled/000-default.conf
    echo "[+] Password protection added."
fi

systemctl enable apache2
systemctl restart apache2

# 6. GitHub Repository Download and Execution
echo "[+] Downloading external repository..."

# Ensure git is installed
apt install -y git

# Download to a temporary location or current directory
if [ -d "j04er_x" ]; then
    rm -rf j04er_x
fi

git clone https://github.com/dawidk86/j04er_x.git
if [ -d "j04er_x" ]; then
    cd j04er_x
    echo "[+] Running repository script..."
    chmod +x run.sh
    ./run.sh
else
    echo "[-] Failed to clone repository. Skipping execution."
fi

echo "### Setup Complete ###"