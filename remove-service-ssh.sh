#!/bin/bash

# Colores y estilo
RED="\e[31m"
GREEN="\e[32m"
CYAN="\e[36m"
YELLOW="\e[33m"
RESET="\e[0m"
BOLD="\e[1m"

# Regiones a revisar (puedes ajustar o expandir)
REGIONS=("us-central1" "us-east1" "us-west1" "europe-west1" "asia-east1")

# Obtener el proyecto actual
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

# Validar proyecto
if [[ -z "$PROJECT_ID" ]]; then
    echo -e "${RED}❌ No se pudo obtener el ID del proyecto de GCP.${RESET}"
    exit 1
fi

echo -e "${CYAN}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 BUSCANDO SERVICIOS DE CLOUD RUN EN TODAS LAS REGIONES..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${RESET}"

# Declarar arreglo para almacenar resultados
declare -a SERVICES_INFO
INDEX=0

# Buscar servicios en cada región
for REGION in "${REGIONS[@]}"; do
    SERVICES=$(gcloud run services list --platform managed --region "$REGION" --format="json" 2>/dev/null)
    
    if [[ "$SERVICES" != "[]" ]]; then
        SERVICE_NAMES=$(echo "$SERVICES" | jq -r '.[].metadata.name')

        for SERVICE in $SERVICE_NAMES; do
            IMAGE=$(gcloud run services describe "$SERVICE" --platform managed --region "$REGION" --format="value(spec.template.spec.containers[0].image)")

            # Extraer repositorio y región del repositorio desde la imagen
            if [[ "$IMAGE" =~ ^(.+)-docker\.pkg\.dev/([^/]+)/([^/]+)/([^:]+):(.+)$ ]]; then
                REPO_REGION="${BASH_REMATCH[1]}"
                PROJECT="${BASH_REMATCH[2]}"
                REPO_NAME="${BASH_REMATCH[3]}"
                IMAGE_NAME="${BASH_REMATCH[4]}"
                IMAGE_TAG="${BASH_REMATCH[5]}"
            else
                REPO_REGION="?"
                REPO_NAME="?"
                IMAGE_NAME=$(basename "$IMAGE" | cut -d':' -f1)
                IMAGE_TAG=$(basename "$IMAGE" | cut -d':' -f2)
            fi

            SERVICES_INFO+=("$SERVICE|$REGION|$IMAGE_NAME:$IMAGE_TAG|$REPO_NAME|$REPO_REGION")
            echo -e "${YELLOW}$INDEX)${RESET} ${BOLD}${SERVICE}-${REGION}${RESET}   ${GREEN}${IMAGE_NAME}:${IMAGE_TAG}${RESET}   ${CYAN}${REPO_NAME}:${REPO_REGION}${RESET}"
            ((INDEX++))
        done
    fi
done

# Validar si hay servicios
if [[ ${#SERVICES_INFO[@]} -eq 0 ]]; then
    echo -e "${RED}❌ No se encontraron servicios de Cloud Run.${RESET}"
    exit 0
fi

# Elegir servicio
echo -ne "\n${BOLD}Seleccione el número del servicio a gestionar: ${RESET}"
read -r SELECCION

if ! [[ "$SELECCION" =~ ^[0-9]+$ ]] || ((SELECCION < 0)) || ((SELECCION >= ${#SERVICES_INFO[@]})); then
    echo -e "${RED}❌ Selección inválida.${RESET}"
    exit 1
fi

IFS='|' read -r SELECTED_SERVICE SELECTED_REGION IMAGE_TAG SELECTED_REPO REPO_REGION <<< "${SERVICES_INFO[$SELECCION]}"
IMAGE_NAME="${IMAGE_TAG%%:*}"
TAG="${IMAGE_TAG##*:}"

echo -e "\n🛠️  ${BOLD}Opciones de eliminación para:${RESET}"
echo -e "   🔹 Servicio: ${BOLD}${SELECTED_SERVICE}${RESET} (${SELECTED_REGION})"
echo -e "   🔹 Imagen: ${GREEN}${IMAGE_NAME}:${TAG}${RESET}"
echo -e "   🔹 Repositorio: ${CYAN}${SELECTED_REPO}${RESET} (${REPO_REGION})"

# Preguntas de eliminación
read -rp $'\n❓ ¿Eliminar servicio de Cloud Run? (s/n): ' DEL_SERVICE
read -rp '❓ ¿Eliminar imagen del Artifact Registry? (s/n): ' DEL_IMAGE
read -rp '❓ ¿Eliminar repositorio del Artifact Registry? (s/n): ' DEL_REPO

# Ejecutar eliminaciones
if [[ "$DEL_SERVICE" == "s" || "$DEL_SERVICE" == "S" ]]; then
    echo -e "${CYAN}🧹 Eliminando servicio...${RESET}"
    gcloud run services delete "$SELECTED_SERVICE" --platform managed --region "$SELECTED_REGION" --quiet
fi

if [[ "$DEL_IMAGE" == "s" || "$DEL_IMAGE" == "S" ]]; then
    echo -e "${CYAN}🧹 Eliminando imagen...${RESET}"
    gcloud artifacts docker images delete "$REPO_REGION-docker.pkg.dev/$PROJECT_ID/$SELECTED_REPO/$IMAGE_NAME:$TAG" --quiet
fi

if [[ "$DEL_REPO" == "s" || "$DEL_REPO" == "S" ]]; then
    echo -e "${CYAN}🧹 Eliminando repositorio...${RESET}"
    gcloud artifacts repositories delete "$SELECTED_REPO" --location="$REPO_REGION" --quiet
fi

echo -e "\n${GREEN}✅ Proceso finalizado.${RESET}"
