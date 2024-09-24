#!/bin/bash

# Función para mostrar un mensaje de error y salir del script
display_error() {
    echo "Error: $1"
    exit 1
}

# Verificar si todas las variables necesarias están presentes
if [ -z "$nombre_del_sitio" ] || [ -z "$directorio_raiz" ]; then
    display_error "Faltan parámetros necesarios."
fi

# Instalar Nginx si no está instalado
if ! dpkg -l | grep -qw nginx; then
    sudo apt update
    sudo apt install -y nginx
fi

sudo mkdir -p "$directorio_raiz"

# Configurar el archivo de configuración de Nginx
config_file="/etc/nginx/sites-available/$nombre_del_sitio"

echo "Configurando el archivo de configuración de Nginx..."

# Crear la configuración del servidor
sudo tee "$config_file" > /dev/null <<EOL
server {
    listen 80;
    root $directorio_raiz;
    index index.php index.html index.htm;
    server_name $nombre_del_sitio;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOL

# Crear enlace simbólico al archivo de configuración desde sites-enabled
sudo ln -s "$config_file" "/etc/nginx/sites-enabled/"

# Borrar enlace simbólico por defecto
sudo rm "/etc/nginx/sites-enabled/default"

# Cambiar el propietario del directorio raíz a www-data
sudo chown -R www-data:www-data "$directorio_raiz"

# Recargar Nginx para aplicar los cambios
sudo systemctl reload nginx

echo "El sitio $nombre_del_sitio ha sido configurado correctamente en Nginx."
