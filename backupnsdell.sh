#!/bin/bash
#
# Dell Switches SSH Backup Script

# Configuración
LOCAL_DIR=$(dirname "$0")
BACKUP_PATH="/FullPath/Dell-backupBackBone-ssh/dell"
CONF="$LOCAL_DIR/backupnsdell.conf"
LOG="$LOCAL_DIR/logs/backupnsdell_$(date +%Y%m%d-%H%M%S).log"
SSH_USER=USER1
SSH_PASS=PASS1

# Variables de Correo
TO_ADDRESS="report@domain.com"
BODY="No se registraron problemas durante el proceso de backup"
SUBJECT="Servidor: $(hostname) - Backup de Switches Dell finalizo correctamente"
SUBJECT2="Servidor: $(hostname) - Backup de Switches Dell finalizo con ERRORES!"
FROM_ADDRESS="report@domain.com"
MESSAGE="From: ${FROM_ADDRESS}\nTo: ${TO_ADDRESS}\nSubject: ${SUBJECT}\n\n${BODY}"

# Variables de Error
SCP_ERROR=no
FAILED_EQUIPMENT=""

echo -e "\033[1mScript de Backup para Switches Dell\033[0m" | tee -a "$LOG"
echo "" | tee -a "$LOG"

if [ ! -f "$CONF" ]; then
    echo -e "\e[31m!!!ERROR\e[0m, Archivo de configuración no encontrado!" | tee -a "$LOG"
    exit 1
fi

if [ ! -d "$BACKUP_PATH" ]; then
    echo -e "\e[31m!!!ERROR\e[0m, Ruta de backup no encontrada!" | tee -a "$LOG"
    exit 1
fi

# Inicialización de variables
INDEX=0
declare -a IP
declare -a NAME

# Leer el archivo de configuración
while IFS=: read -r ip name; do
    line=$(echo "$ip:$name" | grep :)
    if [ -n "$line" ]; then
        if [ "${line:0:1}" != "#" ]; then
            IP[$INDEX]=$(echo "$ip" | tr -d " ")
            NAME[$INDEX]=$(echo "$name" | tr -d " ")
            if [ ! -d "${BACKUP_PATH}/${NAME[$INDEX]}" ]; then
                mkdir -p "${BACKUP_PATH}/${NAME[$INDEX]}"
            fi
            INDEX=$((INDEX + 1))
        fi
    fi
done < "$CONF"

echo "Número de dispositivos a procesar: $INDEX" | tee -a "$LOG"
echo "" | tee -a "$LOG"

# Función para realizar el backup
process_backup() {
    local ip=$1
    local name=$2
    local backup_file="${BACKUP_PATH}/${name}/startup_$(date +%Y%m%d-%H%M%S).xml"

    echo "Procesando switch $name ($ip)..." | tee -a "$LOG"
    echo "Ejecutando comando para $name en $ip" | tee -a "$LOG"

    if timeout 60s ./ssh_enable.exp "$SSH_USER" "$SSH_PASS" "$ip" "$backup_file" > "$backup_file" 2>> "$LOG"; then
        echo "Backup de $name completado y guardado en $backup_file" | tee -a "$LOG"
    else
        echo "Err Ocurrió un error durante el proceso de backup para $name ($ip). Revisa el archivo de log para más detalles." | tee -a "$LOG"
        echo "Error al ejecutar el comando en $ip" >> "$LOG"
        SCP_ERROR=yes
        FAILED_EQUIPMENT+="$name ($ip)\n"
    fi
}

# Procesar todos los dispositivos
for ((i = 0; i < INDEX; i++)); do
    process_backup "${IP[$i]}" "${NAME[$i]}"
done

echo "--------------------------------------------------------------------------------" >> "$LOG"
echo "$(date)" >> "$LOG"
echo "--------------------------------------------------------------------------------" >> "$LOG"

# Enviar notificación por correo
echo -e "\nEnviando notificación por email..."
if [ "$SCP_ERROR" == "yes" ]; then
    BODY2="!!!ERROR - Ocurrió un ERROR durante el proceso de backup.\nRevisa el archivo de log para detalles en: $LOG\n\nEquipos que fallaron:\n$FAILED_EQUIPMENT"
    MESSAGE2="From: ${FROM_ADDRESS}\nTo: ${TO_ADDRESS}\nSubject: ${SUBJECT2}\n\n${BODY2}"
    echo -e "$MESSAGE2" | msmtp -a default -t
    echo -e " \e[31mErr\e[0m Email de error enviado!" | tee -a "$LOG"
else
    echo -e "$MESSAGE" | msmtp -a default -t
    echo -e " \e[32mOK\e[0m Email de éxito enviado!" | tee -a "$LOG"
fi

echo "--------------------------------------------------------------------------------"
echo -e "\033[1mProceso de Backup finalizado!\033[0m"
echo "--------------------------------------------------------------------------------"
