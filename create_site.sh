#!/bin/bash

if [ "$#" -ne 3 ]; then

  echo "Usage: $0 <newServer> <ServerAdminEmail> <version>"

  exit 1

fi

newServer="$1"

ServerAdminEmail="$2"

version="$3"

confFile="/etc/apache2/sites-available/$newServer.conf"

# Check if the configuration file already exists

if [ -e "$confFile" ]; then

  echo "Configuration file $confFile already exists. Skipping creation."

else

  # Generate VirtualHost configuration

  cat <<EOF > "$confFile"

<VirtualHost *:80>

  ServerAdmin $ServerAdminEmail

  ServerName $newServer

  DocumentRoot /var/www/html/$newServer

  DirectoryIndex index.html

# if index.html file dne the remove the line above

  <Directory /var/www/html/$newServer>

    Options Indexes FollowSymLinks MultiViews

    AllowOverride All

    Order allow,deny

    Allow from all

  </Directory>

# remove this if server contains 1 php version

  <FilesMatch \.php$>

    # For Apache version 2.4.10 and above, use SetHandler to run PHP as a fastCGI process server

     SetHandler "proxy:unix:/run/php/php$version-fpm.sock|fcgi://localhost"

  </FilesMatch>

  ErrorLog ${APACHE_LOG_DIR}/${newServer}_error.log

  CustomLog ${APACHE_LOG_DIR}/${newServer}_access.log combined

</VirtualHost>

EOF

  cd /etc/apache2/sites-available

  sudo a2ensite "$newServer.conf"

  sudo service apache2 restart

  sudo certbot --apache -d $newServer --non-interactive --agree-tos --email $ServerAdminEmail

fi
