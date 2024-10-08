#!/bin/bash

# Exit script on any error
set -e

# Function to display messages
function echo_msg() {
    echo ">>> $1"
}

# Function to display error messages in red
function echo_error() {
    echo -e "\033[31m>>> ERROR: $1\033[0m"
}

# Function to validate domain
function validate_domain() {
    local domain="$1"
    if [[ ! "$domain" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        echo "Invalid domain name. Please enter a valid domain (e.g., dhruvjoshi.dev)."
        return 1
    fi
    return 0
}

# Function to check if the domain points to the server's IP
function check_dns() {
    local domain="$1"
    local server_ip=$(hostname -I | awk '{print $1}') # Get the server's first IP
    local dns_ip=$(dig +short "$domain" A | head -n 1) # Get the A record for the domain

    if [[ "$dns_ip" != "$server_ip" ]]; then
        echo_error "The domain '$domain' does not point to this server's IP ($server_ip)."
        echo "Please update the DNS A record for '$domain' to point to this server's IP."
        read -p "Do you want to continue with the installation? (y/n): " CONTINUE_INSTALL
        if [[ ! "$CONTINUE_INSTALL" =~ ^[yY]$ ]]; then
            echo_msg "Exiting installation."
            exit 1
        fi
    fi
}

# Prompt for domain name
while true; do
    read -p "Enter your domain name (default: app.dhruvjoshi.dev): " DOMAIN
    DOMAIN=${DOMAIN:-app.dhruvjoshi.dev}

    if validate_domain "$DOMAIN"; then
        break
    fi
done

# Check if the domain points to this server's IP
check_dns "$DOMAIN"

# Check if it's a new server
read -p "Is this a new server setup? (y/n): " NEW_SERVER

if [[ "$NEW_SERVER" =~ ^[yY]$ ]]; then
    # Update and upgrade the package list
    echo_msg "Updating and upgrading packages..."
    sudo apt update -y && sudo apt upgrade -y

    # Install Apache
    echo_msg "Installing Apache..."
    sudo apt install apache2 -y
    sudo systemctl start apache2
    sudo systemctl enable apache2
    sudo ufw allow 'Apache Full'

    # Install PHP and required extensions
    echo_msg "Adding PHP repository..."
    sudo add-apt-repository ppa:ondrej/php -y
    sudo apt update -y

    echo_msg "Installing PHP and extensions..."
    sudo apt install -y php libapache2-mod-php php-mysql php-fpm \
    php-curl php-gd php-mbstring php-xml php-zip php-bcmath php-json

    echo_msg "Enabling PHP module and configuration..."
    sudo a2enmod php8.3
    sudo a2enconf php8.3-fpm

    # Check Apache configuration
    echo_msg "Checking Apache configuration..."
    sudo apache2ctl configtest

    # Restart Apache to apply changes
    echo_msg "Restarting Apache..."
    sudo systemctl restart apache2

    # Install MySQL server
    echo_msg "Installing MySQL server..."
    sudo apt install mysql-server -y
    echo_msg "Please run 'mysql_secure_installation' manually to secure your MySQL installation."

    # Enable Apache rewrite module
    echo_msg "Enabling Apache rewrite module..."
    sudo a2enmod rewrite
    sudo systemctl restart apache2

else
    # Step by step installation
    read -p "Do you want to install Apache? (y/n): " INSTALL_APACHE
    if [[ "$INSTALL_APACHE" =~ ^[yY]$ ]]; then
        echo_msg "Installing Apache..."
        sudo apt install apache2 -y
        sudo systemctl start apache2
        sudo systemctl enable apache2
        sudo ufw allow 'Apache Full'
    fi

    read -p "Do you want to install PHP and its extensions? (y/n): " INSTALL_PHP
    if [[ "$INSTALL_PHP" =~ ^[yY]$ ]]; then
        echo_msg "Adding PHP repository..."
        sudo add-apt-repository ppa:ondrej/php -y
        sudo apt update -y

        echo_msg "Installing PHP and extensions..."
        sudo apt install -y php libapache2-mod-php php-mysql php-fpm \
        php-curl php-gd php-mbstring php-xml php-zip php-bcmath php-json

        echo_msg "Enabling PHP module and configuration..."
        sudo a2enmod php8.3
        sudo a2enconf php8.3-fpm

        echo_msg "Checking Apache configuration..."
        sudo apache2ctl configtest

        echo_msg "Restarting Apache..."
        sudo systemctl restart apache2
    fi

    read -p "Do you want to install MySQL server? (y/n): " INSTALL_MYSQL
    if [[ "$INSTALL_MYSQL" =~ ^[yY]$ ]]; then
        echo_msg "Installing MySQL server..."
        sudo apt install mysql-server -y
        echo_msg "Please run 'mysql_secure_installation' manually to secure your MySQL installation."
    fi

    # Enable Apache rewrite module
    echo_msg "Enabling Apache rewrite module..."
    sudo a2enmod rewrite
    sudo systemctl restart apache2
fi

# Create directories for virtual hosts
echo_msg "Creating directories for virtual hosts..."
sudo mkdir -p /var/www/$DOMAIN

# Create virtual host configuration files
echo_msg "Creating virtual host configuration files..."
cat <<EOF | sudo tee /etc/apache2/sites-available/$DOMAIN.conf
<VirtualHost *:80>
    ServerName $DOMAIN
    ServerAlias *.$DOMAIN
    DocumentRoot /var/www/$DOMAIN
    <Directory /var/www/$DOMAIN>
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

# Enable the new virtual host configurations
echo_msg "Enabling virtual host configurations..."
sudo a2ensite $DOMAIN.conf

# Restart Apache to apply new configurations
echo_msg "Restarting Apache to apply new configurations..."
sudo systemctl restart apache2

# Create index.php files for each site
echo_msg "Creating index.php files..."
echo "<?php echo 'This is the $DOMAIN subdomain.'; ?>" | sudo tee /var/www/$DOMAIN/index.php

# Set ownership for the web directories
echo_msg "Setting ownership for the web directories..."
sudo chown -R www-data:www-data /var/www/$DOMAIN

# Install Composer
read -p "Do you want to install Composer? (y/n, default: y): " INSTALL_COMPOSER
INSTALL_COMPOSER=${INSTALL_COMPOSER:-y}  # Default to 'y' if no input
if [[ "$INSTALL_COMPOSER" =~ ^[yY]$ ]]; then
    echo_msg "Installing Composer..."
    
    # Download Composer installer
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
    
    # Verify installer SHA-384
    expected_hash="$(curl -s https://composer.github.io/installer.sha384sum | awk '{print $1}')"
    actual_hash="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

    if [ "$expected_hash" != "$actual_hash" ]; then
        echo_error "Installer corrupt"
        rm composer-setup.php
        exit 1
    fi

    # Run the installer
    php composer-setup.php
    php -r "unlink('composer-setup.php');"
    sudo mv composer.phar /usr/local/bin/composer
    sudo chmod +x /usr/local/bin/composer
fi


echo_msg "Setup complete! Please remember to run 'mysql_secure_installation' manually."
