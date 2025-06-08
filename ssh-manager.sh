#!/bin/bash
# Hola

# Colores para mejor visualización
GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
CYAN="\033[1;36m"
RESET="\033[0m"

function construir_servicio() {
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${YELLOW}⚙️ Construyendo un nuevo servicio...${RESET}"

    wget -q https://raw.githubusercontent.com/ChristopherAGT/v2ray-vless-ws/main/build-service-v2ray.sh -O build-service-v2ray.sh
    if [[ $? -ne 0 || ! -s build-service-v2ray.sh ]]; then
        echo -e "${RED}❌ Error al descargar el script de construcción.${RESET}"
        read -n 1 -s -r -p "${BLUE}🔁 Presione cualquier tecla para volver al menú...${RESET}"
        return 1  # Termina la función si hubo un error al descargar el archivo
    fi

    bash build-service-v2ray.sh
    if [[ $? -ne 0 ]]; then  # Verifica si el script descargado falló
        echo -e "${RED}❌ Error al ejecutar el script de construcción.${RESET}"
        read -n 1 -s -r -p "${BLUE}🔁 Presione cualquier tecla para volver al menú...${RESET}"
        return 1  # Termina la función si hubo un error al ejecutar el script
    fi

    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${GREEN}✅ Servicio instalado correctamente.${RESET}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

    read -n 1 -s -r -p "${BLUE}🔁 Presione cualquier tecla para volver al menú...${RESET}"
}

function remover_servicio() {
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${RED}🧹 Removiendo un servicio...${RESET}"

    wget -q https://raw.githubusercontent.com/ChristopherAGT/v2ray-vless-ws/main/remove-service-v2ray.sh -O remove-service-v2ray.sh
    if [[ $? -ne 0 || ! -s remove-service-v2ray.sh ]]; then
        echo -e "${RED}❌ Error al descargar el script de eliminación.${RESET}"
        read -n 1 -s -r -p "${BLUE}🔁 Presione cualquier tecla para volver al menú...${RESET}"
        return 1  # Termina la función si hubo un error al descargar el archivo
    fi

    bash remove-service-v2ray.sh
    if [[ $? -ne 0 ]]; then  # Verifica si el script descargado falló
        echo -e "${RED}❌ Error al ejecutar el script de eliminación.${RESET}"
        read -n 1 -s -r -p "${BLUE}🔁 Presione cualquier tecla para volver al menú...${RESET}"
        return 1  # Termina la función si hubo un error al ejecutar el script
    fi

    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${GREEN}✅ Servicio eliminado correctamente.${RESET}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

    read -n 1 -s -r -p "${BLUE}🔁 Presione cualquier tecla para volver al menú...${RESET}"
}

function editar_servicio() {
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${CYAN}✏️ Editando un servicio...${RESET}"

    # Aquí puedes agregar lo que desees hacer para editar el servicio
    # Este es solo un ejemplo
    echo -e "${YELLOW}Por favor, edite el servicio según tus necesidades.${RESET}"

    read -n 1 -s -r -p "${BLUE}🔁 Presione cualquier tecla para volver al menú...${RESET}"
}

function mostrar_menu() {
    while true; do
        clear
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo -e "${CYAN}    🚀 PANEL DE CONTROL V2RAY-VLESS${RESET}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo -e "${YELLOW}1️⃣  Construir Servicio${RESET}"
        echo -e "${YELLOW}2️⃣  Editar Servicio${RESET}"
        echo -e "${YELLOW}3️⃣  Remover Servicio${RESET}"
        echo -e "${YELLOW}4️⃣  Salir${RESET}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo -ne "${YELLOW}👉 Seleccione una opción [1-4]: ${RESET}"

        read -r opcion

        case $opcion in
            1) 
                construir_servicio
                ;;
            2)
                editar_servicio
                ;;
            3) 
                remover_servicio
                ;;
            4)
                echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
                echo -e "${YELLOW}👋 Saliendo...${RESET}"
                echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
                echo -e "${BLUE}👾 Créditos a Leo Duarte${RESET}"
                sleep 1
                exit 0
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