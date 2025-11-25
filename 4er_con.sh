#!/bin/bash

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root"
  exit
fi

echo "### Starting Kali Linux Setup Script ###"

# ==========================================
# 1. Update and Upgrade
# ==========================================
echo "[+] Updating and Upgrading System..."
apt update
# Using full-upgrade to handle dependencies better
apt full-upgrade -y 

# ==========================================
# 2. Enable and Start SSH
# ==========================================
echo "[+] Enabling and Starting SSH..."
systemctl enable ssh
systemctl start ssh

# ==========================================
# 3. Samba Configuration
# ==========================================
echo "[+] Installing and Configuring Samba..."
apt install -y samba

# Create the folder
mkdir -p /smb43
chmod 777 /smb43
chown nobody:nogroup /smb43

# Backup original config if backup doesn't exist
if [ ! -f /etc/samba/smb.conf.bak ]; then
    cp /etc/samba/smb.conf /etc/samba/smb.conf.bak
fi

# Check if share already exists to avoid duplicate entries
if grep -q "\[smb43\]" /etc/samba/smb.conf; then
    echo "[!] Samba share [smb43] already configured. Skipping append."
else
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
    echo "[+] Samba configuration appended."
fi

# Interactive Samba User Setup
read -p "Do you want to create a Samba user with a password? (y/n): " create_smb_user
if [[ $create_smb_user =~ ^[Yy]$ ]]; then
    read -p "Enter Samba username: " smb_user
    # Check if user exists in system
    if ! id "$smb_user" &>/dev/null; then
        useradd -m $smb_user
        echo "System user $smb_user created."
    fi
    echo "Set Samba password for $smb_user:"
    smbpasswd -a $smb_user
fi

systemctl enable smbd
systemctl restart smbd

# ==========================================
# 4. Apache2 and PHP Configuration
# ==========================================
echo "[+] Installing Apache2 and PHP..."
apt install -y apache2 php libapache2-mod-php

# Interactive Port Setup
read -p "Which port should Apache listen on? (Default 80): " apache_port
apache_port=${apache_port:-80}

if [ "$apache_port" != "80" ]; then
    echo "[+] Configuring Apache to listen on port $apache_port..."
    # Only replace if Listen 80 is found (prevents breaking on re-run)
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
    
    # Check if config is already injected to avoid duplicates
    if ! grep -q "AuthUserFile /etc/apache2/.htpasswd_j" /etc/apache2/sites-enabled/000-default.conf; then
        CONFIG_BLOCK="
    <Directory /var/www/html/j>
        AuthType Basic
        AuthName \"Restricted Content\"
        AuthUserFile /etc/apache2/.htpasswd_j
        Require valid-user
        Options Indexes FollowSymLinks
        AllowOverride All
    </Directory>"
    
        # Insert block before </VirtualHost>
        sed -i "/<\/VirtualHost>/i $CONFIG_BLOCK" /etc/apache2/sites-enabled/000-default.conf
        echo "[+] Password protection config added."
    else
        echo "[!] Password protection config already present."
    fi
fi

systemctl enable apache2
systemctl restart apache2

# ==========================================
# 5. GitHub Repository Download and Execution
# ==========================================
echo "[+] Downloading external repository..."
apt install -y git

# Clean previous install if exists
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
