#!/bin/bash

# Function to prompt for input with validation
get_input() {
    local prompt="$1"
    local var_name="$2"
    local value=""
    
    while [ -z "$value" ]; do
        read -p "$prompt" value
        if [ -z "$value" ]; then
            echo "Error: Input cannot be empty. Please try again."
        fi
    done
    eval "$var_name=\"$value\""
}

# Get required information from user
get_input "Enter the server name: " newServer
get_input "Enter the server admin email: " ServerAdminEmail
get_input "Enter the PHP version (e.g., 7.4): " version

confFile="/etc/apache2/sites-available/$newServer.conf"

# Check if the configuration file already exists

if [ -e "$confFile" ]; then

  echo "Configuration file $confFile already exists. Skipping creation."

else

  # Generate VirtualHost configuration

  sudo bash -c "cat > '$confFile' << 'EOF'
<VirtualHost *:80>
  ServerAdmin $ServerAdminEmail
  ServerName $newServer
  DocumentRoot /var/www/html/$newServer
  DirectoryIndex index.html

  <Directory /var/www/html/$newServer>
    Options Indexes FollowSymLinks MultiViews
    AllowOverride All
    Order allow,deny
    Allow from all
  </Directory>

  <FilesMatch \.php\$>
    SetHandler \"proxy:unix:/run/php/php$version-fpm.sock|fcgi://localhost\"
  </FilesMatch>

  ErrorLog \${APACHE_LOG_DIR}/${newServer}_error.log
  CustomLog \${APACHE_LOG_DIR}/${newServer}_access.log combined
</VirtualHost>
EOF"

  cd /etc/apache2/sites-available

  sudo a2ensite "$newServer.conf"

  sudo service apache2 restart

  sudo certbot --apache -d $newServer --non-interactive --agree-tos --email $ServerAdminEmail

fi
