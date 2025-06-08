#!/bin/bash

# ╭━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╮
# ┃ 🔧 SCRIPT PARA GESTIONAR SERVICIOS CLOUD RUN    ┃
# ┃ ✨ Incluye eliminación de servicio, imagen y repo ┃
# ╰━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╯

# Colores
RED="\e[31m"
GREEN="\e[32m"
CYAN="\e[36m"
YELLOW="\e[33m"
RESET="\e[0m"
BOLD="\e[1m"

# Regiones a revisar (puedes ampliarlas)
REGIONS=("us-central1" "us-east1" "us-west1" "europe-west1" "asia-east1" "us-west2")

# Proyecto actual
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [[ -z "$PROJECT_ID" ]]; then
    echo -e "${RED}❌ No se pudo obtener el ID del proyecto de GCP.${RESET}"
    exit 1
fi

# Validar que jq esté instalado
if ! command -v jq &>/dev/null; then
    echo -e "${RED}❌ La herramienta 'jq' no está instalada. Instálala antes de continuar.${RESET}"
    exit 1
fi

# Crear temporales y definir limpieza al salir
TMP_DIR=$(mktemp -d)
TMP_SCRIPT=$(mktemp)
trap 'rm -f "$TMP_SCRIPT"; rm -rf "$TMP_DIR"' EXIT

echo -e "${CYAN}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 BUSCANDO SERVICIOS DE CLOUD RUN EN TODAS LAS REGIONES..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${RESET}"

# Buscar servicios por región en paralelo
buscar_servicios_en_region() {
    local REGION="$1"
    gcloud run services list --platform managed --region "$REGION" --format=json > "$TMP_DIR/$REGION.json" 2>/dev/null
}

for REGION in "${REGIONS[@]}"; do
    buscar_servicios_en_region "$REGION" &
done

# Spinner mientras espera
(
    sp='-\|/'
    i=0
    while kill -0 $(jobs -p) 2>/dev/null; do
        printf "\r${CYAN}⏳ Buscando servicios... %c${RESET}" "${sp:i++%${#sp}:1}"
        sleep 0.1
    done
    printf "\r${GREEN}✅ Búsqueda completada.            ${RESET}\n"
) &

spinner_pid=$!
wait
wait $spinner_pid 2>/dev/null

# Procesar resultados
declare -a SERVICES_INFO
INDEX=1

for REGION in "${REGIONS[@]}"; do
    FILE="$TMP_DIR/$REGION.json"
    if [[ -s "$FILE" && $(< "$FILE") != "[]" ]]; then
        SERVICE_NAMES=$(jq -r '.[].metadata.name' "$FILE")
        for SERVICE in $SERVICE_NAMES; do
            IMAGE=$(gcloud run services describe "$SERVICE" --platform managed --region "$REGION" \
              --format="value(spec.template.spec.containers[0].image)" 2>/dev/null)

            if [[ "$IMAGE" =~ ^(.+)-docker\.pkg\.dev/([^/]+)/([^/]+)/([^@:]+)([@:])(.+)$ ]]; then
                REPO_REGION="${BASH_REMATCH[1]}"
                PROJECT="${BASH_REMATCH[2]}"
                REPO_NAME="${BASH_REMATCH[3]}"
                IMAGE_NAME="${BASH_REMATCH[4]}"
                SEP="${BASH_REMATCH[5]}"
                TAG_OR_DIGEST="${BASH_REMATCH[6]}"
            else
                continue
            fi

            SERVICES_INFO+=("$SERVICE|$REGION|$IMAGE_NAME|$SEP|$TAG_OR_DIGEST|$REPO_NAME|$REPO_REGION")
        done
    fi
done

# Menú
echo -e "${YELLOW}[0]${RESET} ${BOLD}Cancelar / Salir${RESET}"

if [[ ${#SERVICES_INFO[@]} -eq 0 ]]; then
    echo -e "${RED}❌ No se encontraron servicios de Cloud Run.${RESET}"
    exit 0
fi

for (( i=0; i<${#SERVICES_INFO[@]}; i++ )); do
    IFS='|' read -r SERVICE REGION IMAGE_NAME SEP TAG_OR_DIGEST REPO_NAME REPO_REGION <<< "${SERVICES_INFO[i]}"
    echo -e "${YELLOW}[$((i+1))]${RESET} ${BOLD}${SERVICE}-${REGION}${RESET}   ${GREEN}${IMAGE_NAME}${SEP}${TAG_OR_DIGEST}${RESET}   ${CYAN}${REPO_NAME}:${REPO_REGION}${RESET}"
done

# Selección
while true; do
    echo -ne "\n${BOLD}Seleccione el número del servicio a gestionar (0 para salir): ${RESET}"
    read -r SELECCION

    if [[ "$SELECCION" == "0" ]]; then
        echo -e "${CYAN}👋 Operación cancelada por el usuario.${RESET}"
        exit 0
    fi

    if [[ "$SELECCION" =~ ^[0-9]+$ && "$SELECCION" -gt 0 && "$SELECCION" -le "${#SERVICES_INFO[@]}" ]]; then
        break
    fi

    echo -e "${RED}❌ Selección inválida. Intente de nuevo.${RESET}"
done

SELECCION=$((SELECCION - 1))
IFS='|' read -r SELECTED_SERVICE SELECTED_REGION IMAGE_NAME SEP TAG_OR_DIGEST SELECTED_REPO REPO_REGION <<< "${SERVICES_INFO[$SELECCION]}"

echo -e "\n🛠️  ${BOLD}Opciones de eliminación para:${RESET}"
echo -e "   🔹 Servicio: ${BOLD}${SELECTED_SERVICE}${RESET} (${SELECTED_REGION})"
echo -e "   🔹 Imagen: ${GREEN}${IMAGE_NAME}${SEP}${TAG_OR_DIGEST}${RESET}"
echo -e "   🔹 Repositorio: ${CYAN}${SELECTED_REPO}${RESET} (${REPO_REGION})"

read -rp $'\n❓ ¿Eliminar servicio de Cloud Run? (s/n): ' DEL_SERVICE
read -rp '❓ ¿Eliminar imagen del Artifact Registry? (s/n): ' DEL_IMAGE
read -rp '❓ ¿Eliminar repositorio del Artifact Registry? (s/n): ' DEL_REPO

# Eliminar servicio
if [[ "$DEL_SERVICE" =~ ^[sS]$ ]]; then
    echo -e "${CYAN}🧹 Eliminando servicio...${RESET}"
    gcloud run services delete "$SELECTED_SERVICE" --platform managed --region "$SELECTED_REGION" --quiet
fi

# Eliminar imagen (solo tag o digest seleccionado)
if [[ "$DEL_IMAGE" =~ ^[sS]$ ]]; then
    FULL_PATH="$REPO_REGION-docker.pkg.dev/$PROJECT_ID/$SELECTED_REPO/$IMAGE_NAME"
    IMAGE_LIST=$(gcloud artifacts docker images list "$FULL_PATH" --include-tags --format=json 2>/dev/null)

    if [[ "$SEP" == ":" ]]; then
        DIGEST=$(echo "$IMAGE_LIST" | jq -r --arg TAG "$TAG_OR_DIGEST" '.[] | select(.tags[]? == $TAG) | .digest' | head -n1)
    else
        DIGEST="$TAG_OR_DIGEST"
    fi

    if [[ -z "$DIGEST" || "$DIGEST" == "null" ]]; then
        echo -e "${RED}❌ No se pudo encontrar el digest para la imagen con ${BOLD}$TAG_OR_DIGEST${RESET}"
    else
        echo -e "${GREEN}✅ Digest encontrado:${RESET} ${DIGEST}"

        if [[ "$SEP" == ":" ]]; then
            echo -e "${CYAN}🧹 Eliminando tag: ${BOLD}${TAG_OR_DIGEST}${RESET}"
            gcloud artifacts docker images delete "$FULL_PATH:$TAG_OR_DIGEST" --quiet
        fi

        echo -e "${CYAN}🧹 Eliminando digest: ${BOLD}${DIGEST}${RESET}"
        gcloud artifacts docker images delete "$FULL_PATH@$DIGEST" --quiet
    fi
fi

# Eliminar repositorio
if [[ "$DEL_REPO" =~ ^[sS]$ ]]; then
    echo -e "${CYAN}🧹 Eliminando repositorio...${RESET}"
    gcloud artifacts repositories delete "$SELECTED_REPO" --location="$REPO_REGION" --quiet
fi

echo -e "\n${GREEN}✅ Proceso finalizado.${RESET}"
