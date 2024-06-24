#!/bin/bash

# Function to prompt for input
prompt_for_input() {
    local prompt="$1"
    local input_variable_name="$2"
    local input_value=""

    while [ -z "$input_value" ]; do
        read -rp "$prompt: " input_value
        if [ -n "$input_value" ]; then
            eval "$input_variable_name=\"$input_value\""
        else
            echo "Input cannot be empty. Please try again."
        fi
    done
}

# Function to update php.ini settings
update_php_ini() {
    local setting="$1"
    local value="$2"
    local php_ini="$3"

    # Check if the setting exists as commented and uncomment it
    if grep -q "^\s*;$setting" "$php_ini"; then
        sudo sed -i "s/^\s*;$setting\s*=.*/$setting = $value/" "$php_ini"
    # Check if the setting exists uncommented and update it
    elif grep -q "^\s*$setting" "$php_ini"; then
        sudo sed -i "s/^\s*$setting\s*=.*/$setting = $value/" "$php_ini"
    else
        # If the setting does not exist, add it
        echo "$setting = $value" | sudo tee -a "$php_ini" > /dev/null
    fi
}

# Function to add a PHP extension to php.ini if it doesn't exist
add_php_extension() {
    local extension_line="extension=$1"
    local php_ini_file="$2"

    # Check if the extension line exists as a commented line
    if grep -q "^\s*;${extension_line}" "$php_ini_file"; then
        # Uncomment the extension line
        sudo sed -i "s/^\s*;${extension_line}/${extension_line}/" "$php_ini_file"
        echo "Uncommented extension line in php.ini: $extension_line"
    elif ! grep -Fxq "$extension_line" "$php_ini_file"; then
        # If the line doesn't exist, add it to the end of the file
        echo "$extension_line" | sudo tee -a "$php_ini_file" > /dev/null
        echo "Extension line added to php.ini: $extension_line"
    else
        echo "Extension line already exists in php.ini: $extension_line"
    fi
}

# Prompt for new superuser details
prompt_for_input "Enter MySQL superuser username" new_username
prompt_for_input "Enter MySQL superuser password" new_password

# Prompt for php version
prompt_for_input "Enter php version to be install" php_version

# Update the package list
echo "Updating package list..."
sudo apt update

# Install Apache
echo "Installing Apache..."
sudo NEEDRESTART_MODE=a apt install apache2 -y

# Set up firewall
echo "Setting up firewall..."
sudo NEEDRESTART_MODE=a apt install ufw -y
sudo ufw allow 'Apache'
sudo ufw allow ssh
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 587/tcp
sudo ufw allow 465/tcp
sudo ufw allow 25/tcp
yes | sudo ufw enable

# Install MySQL
echo "Installing MySQL..."
sudo NEEDRESTART_MODE=a apt install mysql-server -y
sudo mysql -e "SET GLOBAL binlog_expire_logs_seconds = 86400;"

sudo mysql -e "CREATE USER '$new_username'@'localhost' IDENTIFIED BY '$new_password';"
sudo mysql -e "GRANT ALL PRIVILEGES ON *.* TO '$new_username'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

# Install PHP and required modules
echo "Installing PHP and required modules..."
yes | add-apt-repository ppa:ondrej/php
sudo apt update
sudo NEEDRESTART_MODE=a apt install php$php_version -y
sudo NEEDRESTART_MODE=a apt install php$php_version-common php$php_version-mysql php$php_version-xml php$php_version-xmlrpc php$php_version-curl php$php_version-gd php$php_version-imagick php$php_version-cli php$php_version-dev php$php_version-imap php$php_version-mbstring php$php_version-opcache php$php_version-soap php$php_version-zip php$php_version-intl php$php_version-bcmath libapache2-mod-php$php_version php-pear -y
sudo NEEDRESTART_MODE=a apt install autoconf g++ make openssl libssl3 libssl-dev libcurl4-openssl-dev pkg-config libsasl2-dev libpcre3-dev -y

# Enabling required modules
echo "Enabling required modules..."
sudo phpenmod mbstring
a2enmod proxy
a2enmod proxy_http
a2enmod proxy_ajp
a2enmod rewrite
a2enmod deflate
a2enmod headers
a2enmod proxy_balancer
a2enmod proxy_connect
a2enmod proxy_html
a2enmod ssl

# Restart Apache to apply changes
echo "Restarting Apache..."
sudo systemctl restart apache2

# Enabling http/2
echo "Enabling http/2..."
sudo a2enmod http2
sudo a2dismod php$php_version
sudo a2dismod mpm_prefork
sudo a2enmod mpm_event proxy_fcgi setenvif
sudo NEEDRESTART_MODE=a apt install php$php_version-fpm -y
sudo systemctl start php$php_version-fpm
sudo a2enconf php$php_version-fpm

php_ini_file="/etc/php/$php_version/fpm/php.ini"

# Change php.ini settings
echo "Change php.ini settings..."
update_php_ini "upload_max_filesize" "64M" "$php_ini_file"
update_php_ini "post_max_size" "64M" "$php_ini_file"
update_php_ini "memory_limit" "256M" "$php_ini_file"
update_php_ini "max_execution_time" "600" "$php_ini_file"
update_php_ini "max_input_time" "600" "$php_ini_file"
update_php_ini "max_input_vars" "10000" "$php_ini_file"

# Restart Apache to apply changes
echo "Restarting Apache..."
sudo systemctl restart apache2

# Restart PHP to apply changes
echo "Restarting PHP..."
sudo systemctl restart php$php_version-fpm

# Install additional tools
echo "Installing additional tools..."
sudo NEEDRESTART_MODE=a apt install gnupg curl git zip unzip -y
sudo NEEDRESTART_MODE=a apt install certbot python3-certbot-apache -y
sudo certbot plugins
cron_job="0 0,12 * * * certbot renew --quiet --no-self-upgrade"
(sudo crontab -l 2>/dev/null; echo "$cron_job") | sudo crontab -


# Install mongodb
echo "Installing mongodb..."
curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | sudo gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list
sudo apt update
sudo NEEDRESTART_MODE=a apt install mongodb-org -y
sudo systemctl start mongod.service
sudo systemctl enable mongod

# Restart PHP to apply changes
echo "Restarting PHP..."
sudo systemctl restart php$php_version-fpm

add_php_extension "mongodb.so" "$php_ini_file"

# Install mongodb driver
sudo NEEDRESTART_MODE=a printf "\n" | pecl install -f mongodb-1.19.3

# Install nvm
echo "Installing nvm..."
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash

# Source nvm script to add it to the current shell session
export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm

# Install Node.js version 18.20.3
echo "Installing Node.js v18.20.3..."
nvm install 18.20.3

# Install pm2
echo "Installing pm2..."
npm install pm2@latest -g -y

# Restart Apache to apply changes
echo "Restarting Apache..."
sudo systemctl restart apache2

# Restart PHP to apply changes
echo "Restarting PHP..."
sudo systemctl restart php$php_version-fpm

# Clean up
echo "Cleaning up..."
sudo apt-get autoremove -y
sudo apt-get clean

echo "Setup completed successfully!"