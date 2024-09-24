#!/bin/bash

# Función para mostrar un mensaje de error y salir del script
display_error() {
    echo "Error: $1"
    exit 1
}

# Preguntar si se desea configurar una IP fija
read -p "¿Deseas configurar una IP fija para este host (S/n)? " RESPUESTA

if [ "$RESPUESTA" = "S" ]; then
    # Configurar IP fija
    sudo sed -i "s/iface ens33 inet dhcp/#&\\n/" "/etc/network/interfaces"
    read -p "Introduce la nueva IP: " STATICIP
    read -p "Introduce la máscara de red: " NETMASK
    read -p "Introduce la puerta de enlace: " GATEWAY

    echo -e "iface ens33 inet static\n\taddress $STATICIP\n\tnetmask $NETMASK\n\tgateway $GATEWAY" | sudo tee -a "/etc/network/interfaces"
    sudo ifdown ens33 && sudo ifup ens33
fi

# Comprobar si hay conexión a Internet
ping -c 2 8.8.8.8
if [ $? -ne 0 ]; then
    display_error "No hay conexión a Internet"
else
    echo "Conexión a Internet disponible"
    sudo apt update
    sudo apt install -y bind9
fi

# Copiar archivo de configuración como backup
if [ ! -f "/etc/bind/namedcopia.conf.local" ]; then
    sudo cp "/etc/bind/named.conf.local" "/etc/bind/namedcopia.conf.local"
else
    echo "El archivo de copia de seguridad ya existe."
fi

# Configuración del DNS: maestro o esclavo
DNSTYPE=""
while [[ "$DNSTYPE" != "m" && "$DNSTYPE" != "e" ]]; do
    read -p "¿Deseas configurar este servidor como DNS maestro o esclavo (m/e)? " DNSTYPE
done

if [ "$DNSTYPE" = "m" ]; then
    SALIR="n"
    while [ "$SALIR" = "n" ]; do
        echo "Menú:"
        echo "1. Crear zona directa"
        echo "2. Crear zona inversa"
        echo "3. Salir"
        read -p "Seleccione una opción (1-3): " OPTION

        if [ "$OPTION" -eq 1 ]; then
            read -p "Ingrese el nombre de la zona directa: " ZONE
            ZONE_FILE="/etc/bind/db.$ZONE"

            if [ -f "$ZONE_FILE" ]; then
                sudo rm "$ZONE_FILE"
            fi

            echo -e "zone \"$ZONE\" {\n    type master;\n    file \"$ZONE_FILE\";\n};" | sudo tee -a "/etc/bind/named.conf.local"
            sudo cp "/etc/bind/db.empty" "$ZONE_FILE"

            # Configurar el servidor
            sudo sed -i "s/localhost./ns1.$ZONE./" "$ZONE_FILE"

            # Obtener la IP del host
            IP_ENS33=$(ip addr show ens33 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
            echo -e "ns1    IN    A    $IP_ENS33\n" | sudo tee -a "$ZONE_FILE"

            # Añadir registros adicionales
            CONTINUE="S"
            while [ "$CONTINUE" = "S" ]; do
                read -p "¿Qué tipo de registro quiere añadir (A, MX, CNAME, NS)? " REGISTER
                case "$REGISTER" in
                    A)
                        read -p "Introduce el nombre del registro: " NAME
                        read -p "Introduce la IP para el registro: " IP
                        echo "$NAME    IN    A    $IP" | sudo tee -a "$ZONE_FILE"
                        ;;
                    MX)
                        read -p "Introduce el nombre del registro de correos: " NAME
                        echo "@    IN    MX    10    $NAME.$ZONE." | sudo tee -a "$ZONE_FILE"
                        read -p "Introduce la IP del registro MX: " IP
                        echo "$NAME    IN    A    $IP" | sudo tee -a "$ZONE_FILE"
                        ;;
                    CNAME)
                        read -p "Introduce el alias del nombre de dominio: " ALIAS
                        read -p "Introduce el nombre canónico: " CANONIC
                        echo "$ALIAS    IN    CNAME    $CANONIC.$ZONE" | sudo tee -a "$ZONE_FILE"
                        ;;
                    NS)
                        echo "@    IN    NS    ns2.$ZONE." | sudo tee -a "$ZONE_FILE"
                        echo "ns2    IN    A    $IP_ENS33" | sudo tee -a "$ZONE_FILE"
                        ;;
                    *)
                        echo "Tipo de registro no válido"
                        ;;
                esac
                read -p "¿Desea añadir más registros (S/n)? " CONTINUE
            done
        elif [ "$OPTION" -eq 2 ]; then
            read -p "Ingrese el nombre de la zona inversa: " ZONE_INVERSA
            ZONE_INVERSA_FILE="/etc/bind/db.$ZONE_INVERSA"
            sudo cp "/etc/bind/db.empty" "$ZONE_INVERSA_FILE"
            echo "zone \"$ZONE_INVERSA\" {\n    type master;\n    file \"$ZONE_INVERSA_FILE\";\n};" | sudo tee -a "/etc/bind/named.conf.local"
            echo "Configuración de zona inversa completada."
        elif [ "$OPTION" -eq 3 ]; then
            SALIR="S"
        else
            echo "Opción no válida. Intente nuevamente."
        fi
    done
elif [ "$DNSTYPE" = "e" ]; then
    read -p "Ingrese el nombre de la zona esclava: " ZONE_ESCLAVO
    read -p "Ingrese la IP del servidor maestro: " MAESTRO_IP
    echo "zone \"$ZONE_ESCLAVO\" { type slave; file \"/var/tmp/db.$ZONE_ESCLAVO\"; masters { $MAESTRO_IP; }; };" | sudo tee -a "/etc/bind/named.conf.local"
fi

# Verificar y recargar BIND9
sudo named-checkzone "$ZONE" "$ZONE_FILE"
sudo systemctl restart bind9
sudo systemctl status bind9
echo "Configuración DNS completada."
