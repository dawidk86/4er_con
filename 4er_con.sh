#!/bin/bash

# --- CHECK FOR ROOT ACCESS ---
if [ "$EUID" -ne 0 ]; then 
  echo "ERROR: This script must be run as root."
  exit 1
fi

echo "### Starting Ultimate Kali Linux Setup Script ###"

# ==========================================
# 1. Update and Upgrade
# ==========================================
echo "[+] Updating and Upgrading System..."
apt update
# Use full-upgrade for complete system updates
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

# Create the share directory
mkdir -p /smb43
chmod 777 /smb43
chown nobody:nogroup /smb43

# Backup original config if backup doesn't exist
if [ ! -f /etc/samba/smb.conf.bak ]; then
    cp /etc/samba/smb.conf /etc/samba/smb.conf.bak
fi

# Check if share already exists to avoid duplicate entries (Idempotency Check)
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
# 4. Apache2 and PHP Configuration (Modular & Robust)
# ==========================================
echo "[+] Installing Apache2 and PHP..."
apt install -y apache2 php libapache2-mod-php

# Interactive Port Setup
read -p "Which port should Apache listen on? (Default 80): " apache_port
apache_port=${apache_port:-80}

if [ "$apache_port" != "80" ]; then
    echo "[+] Configuring Apache to listen on port $apache_port..."
    # Prevents adding duplicate Listen lines if run again
    sed -i "s/Listen 80/Listen $apache_port/g" /etc/apache2/ports.conf
    sed -i "s/:80/:$apache_port/g" /etc/apache2/sites-enabled/000-default.conf
fi

# Create directory "j" and its index file
mkdir -p /var/www/html/j
chown www-data:www-data /var/www/html/j
chmod 755 /var/www/html/j
echo "<h1>Welcome to J (Secured Area)</h1>" > /var/www/html/j/index.html

# Interactive Directory Protection
read -p "Do you want to password protect '/var/www/html/j'? (y/n): " protect_apache
if [[ $protect_apache =~ ^[Yy]$ ]]; then
    read -p "Enter username for Apache Auth: " apache_user
    
    # 1. Create the password file
    htpasswd -c /etc/apache2/.htpasswd_j "$apache_user"
    
    # 2. Check and configure the security block using a modular approach (most robust)
    if [ ! -f /etc/apache2/conf-available/j-security.conf ]; then
        echo "[+] Creating dedicated security configuration file."
        
        SECURITY_CONF="
<Directory /var/www/html/j>
    AuthType Basic
    AuthName \"Restricted Content\"
    AuthUserFile /etc/apache2/.htpasswd_j
    Require valid-user
    
    # FIX: Ensures index.html is served and directory listing is prevented
    Options FollowSymLinks
    DirectoryIndex index.html
    AllowOverride All
</Directory>
"
        # Write the content using tee
        echo "$SECURITY_CONF" | tee /etc/apache2/conf-available/j-security.conf
        
        # Enable the new configuration using the Apache helper tool
        a2enconf j-security
        echo "[+] Security configuration enabled via a2enconf."
    else
        echo "[!] Security configuration file j-security.conf already exists. Skipping creation."
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
