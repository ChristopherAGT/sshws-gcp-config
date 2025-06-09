#!/bin/bash

╭──────────────────────────────────────────────╮

│        SCRIPT DE GESTIÓN DE CLOUD RUN        │

╰──────────────────────────────────────────────╯

Colores y estilo

RED="\e[31m" GREEN="\e[32m" CYAN="\e[36m" YELLOW="\e[33m" RESET="\e[0m" BOLD="\e[1m"

Regiones a revisar

REGIONS=("us-central1" "us-east1" "us-west1" "europe-west1" "asia-east1")

Obtener el proyecto actual

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

if [[ -z "$PROJECT_ID" ]]; then echo -e "${RED}❌ No se pudo obtener el ID del proyecto de GCP.${RESET}" exit 1 fi

echo -e "${CYAN}" echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" echo "🔍 BUSCANDO SERVICIOS DE CLOUD RUN EN TODAS LAS REGIONES..." echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" echo -e "${RESET}"

Declarar arreglo para almacenar resultados

declare -a SERVICES_INFO INDEX=0

Buscar servicios en cada región

for REGION in "${REGIONS[@]}"; do SERVICES=$(gcloud run services list --platform managed --region "$REGION" --format="json" 2>/dev/null)

if [[ "$SERVICES" != "[]" ]]; then
    SERVICE_NAMES=$(echo "$SERVICES" | jq -r '.[].metadata.name')

    for SERVICE in $SERVICE_NAMES; do
        IMAGE=$(gcloud run services describe "$SERVICE" --platform managed --region "$REGION" --format="value(spec.template.spec.containers[0].image)")

        if [[ "$IMAGE" =~ ^([a-z0-9-]+)-docker\.pkg\.dev/([^/]+)/([^/]+)/([^@:/]+)([@:][^ ]+)?$ ]]; then
            REPO_REGION="${BASH_REMATCH[1]}"
            PROJECT="${BASH_REMATCH[2]}"
            REPO_NAME="${BASH_REMATCH[3]}"
            IMAGE_NAME="${BASH_REMATCH[4]}"
            IMAGE_SUFFIX="${BASH_REMATCH[5]}"
            [[ "$IMAGE_SUFFIX" == @* ]] && TAG_OR_DIGEST="$IMAGE_NAME${IMAGE_SUFFIX}" || TAG_OR_DIGEST="$IMAGE_NAME:${IMAGE_SUFFIX#:}"
        else
            REPO_REGION="?"
            REPO_NAME="?"
            TAG_OR_DIGEST=$(basename "$IMAGE")
        fi

        SERVICES_INFO+=("$SERVICE|$REGION|$TAG_OR_DIGEST|$REPO_NAME|$REPO_REGION")
        echo -e "${YELLOW}$INDEX)${RESET} ${BOLD}${SERVICE}-${REGION}${RESET}   ${GREEN}${TAG_OR_DIGEST}${RESET}   ${CYAN}${REPO_NAME}:${REPO_REGION}${RESET}"
        ((INDEX++))
    done
fi

done

if [[ ${#SERVICES_INFO[@]} -eq 0 ]]; then echo -e "${RED}❌ No se encontraron servicios de Cloud Run.${RESET}" exit 0 fi

echo -ne "\n${BOLD}Seleccione el número del servicio a gestionar: ${RESET}" read -r SELECCION

if ! [[ "$SELECCION" =~ ^[0-9]+$ ]] || ((SELECCION < 0)) || ((SELECCION >= ${#SERVICES_INFO[@]})); then echo -e "${RED}❌ Selección inválida.${RESET}" exit 1 fi

IFS='|' read -r SELECTED_SERVICE SELECTED_REGION IMAGE_TAG SELECTED_REPO REPO_REGION <<< "${SERVICES_INFO[$SELECCION]}"

if [[ "$IMAGE_TAG" == @sha256: ]]; then IMAGE_NAME=$(echo "$IMAGE_TAG" | cut -d'@' -f1) DIGEST=$(echo "$IMAGE_TAG" | cut -d'@' -f2) TAG="" else IMAGE_NAME="${IMAGE_TAG%%:}" TAG="${IMAGE_TAG##:}" DIGEST=$(gcloud artifacts docker images describe "$REPO_REGION-docker.pkg.dev/$PROJECT_ID/$SELECTED_REPO/$IMAGE_NAME:$TAG" --format="get(image_summary.digest)") fi

echo -e "\n🛠️  ${BOLD}Opciones de eliminación para:${RESET}" echo -e "   🔹 Servicio: ${BOLD}${SELECTED_SERVICE}${RESET} (${SELECTED_REGION})" echo -e "   🔹 Imagen: ${GREEN}${IMAGE_NAME}${RESET} ${TAG:+(${TAG})}${DIGEST:+ [digest: ${DIGEST:0:12}...]}" echo -e "   🔹 Repositorio: ${CYAN}${SELECTED_REPO}${RESET} (${REPO_REGION})"

read -rp $'\n❓ ¿Eliminar servicio de Cloud Run? (s/n): ' DEL_SERVICE read -rp '❓ ¿Eliminar imagen del Artifact Registry? (s/n): ' DEL_IMAGE read -rp '❓ ¿Eliminar repositorio del Artifact Registry si queda vacío? (s/n): ' DEL_REPO

if [[ "$DEL_SERVICE" =~ ^[sS]$ ]]; then echo -e "${CYAN}🧹 Eliminando servicio...${RESET}" gcloud run services delete "$SELECTED_SERVICE" --platform managed --region "$SELECTED_REGION" --quiet fi

if [[ "$DEL_IMAGE" =~ ^[sS]$ ]]; then echo -e "${CYAN}🧹 Eliminando todos los tags asociados...${RESET}" TAGS=$(gcloud artifacts docker tags list "$REPO_REGION-docker.pkg.dev/$PROJECT_ID/$SELECTED_REPO/$IMAGE_NAME" --format="value(tag)" --filter="version.tags:* AND version.metadata.image_summary.digest=$DIGEST") for TAG_TO_DELETE in $TAGS; do gcloud artifacts docker tags delete "$TAG_TO_DELETE" --quiet done

echo -e "${CYAN}🧹 Eliminando imagen por digest...${RESET}"
gcloud artifacts docker images delete "$REPO_REGION-docker.pkg.dev/$PROJECT_ID/$SELECTED_REPO/$IMAGE_NAME@$DIGEST" --quiet

fi

if [[ "$DEL_REPO" =~ ^[sS]$ ]]; then echo -e "${CYAN}🔍 Verificando si el repositorio está vacío...${RESET}" REMAINING_IMAGES=$(gcloud artifacts docker images list "$REPO_REGION-docker.pkg.dev/$PROJECT_ID/$SELECTED_REPO" --format="value(name)" 2>/dev/null) if [[ -z "$REMAINING_IMAGES" ]]; then echo -e "${CYAN}🧹 Repositorio vacío. Eliminando...${RESET}" gcloud artifacts repositories delete "$SELECTED_REPO" --location="$REPO_REGION" --quiet else echo -e "${YELLOW}⚠️  El repositorio aún contiene imágenes. No se eliminará.${RESET}" fi fi

echo -e "${CYAN}🚪 Cerrando sesión de Docker en Artifact Registry...${RESET}" gcloud auth configure-docker --quiet

echo -e "\n${GREEN}✅ Proceso finalizado.${RESET}"

