#!/bin/bash
# Hola

# Colores para mejor visualización
GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
CYAN="\033[1;36m"
RESET="\033[0m"

# Separador reutilizable
SEPARADOR="${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

# Archivos temporales a eliminar
TEMP_FILES=("build-service-ssh.sh" "edit-service-ssh.sh" "remove-service-ssh.sh")

# Eliminar archivos temporales al salir o al interrumpir con Ctrl+C
trap 'rm -f "${TEMP_FILES[@]}"' EXIT

# Función para pausar antes de volver al menú
pausa_menu() {
    echo
    read -n 1 -s -r -p "${GREEN}🔁 Presione cualquier tecla para volver al menú...${RESET}"
    echo
}

# Función para eliminar archivo si existe y descargar uno nuevo
descargar_limpio() {
    local url=$1
    local archivo=$2

    if [[ -f $archivo ]]; then
        rm -f "$archivo"
    fi

    wget -q "$url" -O "$archivo"
    if [[ $? -ne 0 || ! -s $archivo ]]; then
        echo -e "${RED}❌ Error al descargar el archivo '${archivo}'.${RESET}"
        return 1
    fi
    return 0
}

function construir_servicio() {
    echo -e "$SEPARADOR"
    echo -e "${YELLOW}⚙️ Construyendo un nuevo servicio...${RESET}"

    descargar_limpio "https://raw.githubusercontent.com/ChristopherAGT/sshws-gcp-config/main/build-service-ssh.sh" "build-service-ssh.sh"
    if [[ $? -ne 0 ]]; then
        pausa_menu
        return 1
    fi

    bash build-service-ssh.sh
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}❌ Error al ejecutar el script de construcción.${RESET}"
        pausa_menu
        return 1
    fi

    echo -e "$SEPARADOR"
    echo -e "${GREEN}✅ Servicio construido correctamente.${RESET}"
    echo -e "$SEPARADOR"
    pausa_menu
}

function editar_servicio() {
    echo -e "$SEPARADOR"
    echo -e "${CYAN}✏️ Editando un servicio...${RESET}"

    descargar_limpio "https://raw.githubusercontent.com/ChristopherAGT/sshws-gcp-config/main/edit-service-ssh.sh" "edit-service-ssh.sh"
    if [[ $? -ne 0 ]]; then
        pausa_menu
        return 1
    fi

    bash edit-service-ssh.sh
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}❌ Error al ejecutar el script de edición.${RESET}"
        pausa_menu
        return 1
    fi

    echo -e "$SEPARADOR"
    echo -e "${GREEN}✅ Servicio editado correctamente.${RESET}"
    echo -e "$SEPARADOR"
    pausa_menu
}

function remover_servicio() {
    echo -e "$SEPARADOR"
    echo -e "${RED}🧹 Removiendo un servicio...${RESET}"

    descargar_limpio "https://raw.githubusercontent.com/ChristopherAGT/sshws-gcp-config/main/remove-service-ssh.sh" "remove-service-ssh.sh"
    if [[ $? -ne 0 ]]; then
        pausa_menu
        return 1
    fi

    bash remove-service-ssh.sh
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}❌ Error al ejecutar el script de eliminación.${RESET}"
        pausa_menu
        return 1
    fi

    echo -e "$SEPARADOR"
    echo -e "${GREEN}✅ Servicio removido correctamente.${RESET}"
    echo -e "$SEPARADOR"
    pausa_menu
}

function mostrar_menu() {
    while true; do
        clear
        echo -e "$SEPARADOR"
        echo -e "${CYAN}    🚀 PANEL DE CONTROL SSH-WS${RESET}"
        echo -e "$SEPARADOR"
        echo -e "${YELLOW}1️⃣  Construir Servicio${RESET}"
        echo -e "${YELLOW}2️⃣  Editar Servicio${RESET}"
        echo -e "${YELLOW}3️⃣  Remover Servicio${RESET}"
        echo -e "${YELLOW}4️⃣  Salir${RESET}"
        echo -e "$SEPARADOR"
        echo -ne "${YELLOW}👉 Seleccione una opción [1-4]: ${RESET}"

        read -r opcion

        case $opcion in
            [1-4])
                case $opcion in
                    1) construir_servicio ;;
                    2) editar_servicio ;;
                    3) remover_servicio ;;
                    4)
                        echo -e "$SEPARADOR"
                        echo -e "${YELLOW}👋 Saliendo...${RESET}"
                        echo -e "$SEPARADOR"
                        echo -e "${BLUE}👾 Créditos a Leo Duarte${RESET}"
                        sleep 1
                        exit 0
                        ;;
                esac
                ;;
            *)
                echo -e "${RED}⚠️  Opción inválida. Inténtalo de nuevo.${RESET}"
                sleep 2
                ;;
        esac
    done
}

# Iniciar menú
mostrar_menu
