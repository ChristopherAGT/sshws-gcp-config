#!/bin/bash

# Colores y estilo
RED="\e[31m"
GREEN="\e[32m"
CYAN="\e[36m"
YELLOW="\e[33m"
RESET="\e[0m"
BOLD="\e[1m"

# Regiones a revisar
REGIONS=("us-central1" "us-east1" "us-west1" "europe-west1" "asia-east1")

# Obtener el proyecto actual
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

if [[ -z "$PROJECT_ID" ]]; then
    echo -e "${RED}❌ No se pudo obtener el ID del proyecto de GCP.${RESET}"
    exit 1
fi

echo -e "${CYAN}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 BUSCANDO SERVICIOS DE CLOUD RUN EN TODAS LAS REGIONES..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${RESET}"

# Archivos temporales
TMP_DIR=$(mktemp -d)
declare -a SERVICES_INFO
INDEX=1

# Función para procesar una región
buscar_servicios_en_region() {
    REGION=$1
    TMP_FILE="$TMP_DIR/$REGION.json"
    gcloud run services list --platform managed --region "$REGION" --format="json" > "$TMP_FILE" 2>/dev/null
}

# Lanzar procesos en paralelo
for REGION in "${REGIONS[@]}"; do
    buscar_servicios_en_region "$REGION" &
done

wait  # Esperar que todas las regiones terminen

# Procesar resultados consolidados
for REGION in "${REGIONS[@]}"; do
    FILE="$TMP_DIR/$REGION.json"
    if [[ -s "$FILE" && $(< "$FILE") != "[]" ]]; then
        SERVICE_NAMES=$(jq -r '.[].metadata.name' "$FILE")
        for SERVICE in $SERVICE_NAMES; do
            IMAGE=$(gcloud run services describe "$SERVICE" --platform managed --region "$REGION" --format="value(spec.template.spec.containers[0].image)")
            
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
            echo -e "${YELLOW}$INDEX)${RESET} ${BOLD}${SERVICE}-${REGION}${RESET}   ${GREEN}${IMAGE_NAME}${SEP}${TAG_OR_DIGEST}${RESET}   ${CYAN}${REPO_NAME}:${REPO_REGION}${RESET}"
            ((INDEX++))
        done
    fi
done

# Agregar opción de salida
if [[ ${#SERVICES_INFO[@]} -eq 0 ]]; then
    echo -e "${RED}❌ No se encontraron servicios de Cloud Run.${RESET}"
    exit 0
fi

echo -e "${YELLOW}0)${RESET} ${BOLD}❌ Cancelar / Salir${RESET}"

# Bucle hasta selección válida
while true; do
    echo -ne "\n${BOLD}Seleccione el número del servicio a gestionar (0 para salir): ${RESET}"
    read -r SELECCION

    if [[ "$SELECCION" == "0" ]]; then
        echo -e "${CYAN}👋 Operación cancelada por el usuario.${RESET}"
        rm -rf "$TMP_DIR"
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

if [[ "$DEL_SERVICE" =~ ^[sS]$ ]]; then
    echo -e "${CYAN}🧹 Eliminando servicio...${RESET}"
    gcloud run services delete "$SELECTED_SERVICE" --platform managed --region "$SELECTED_REGION" --quiet
fi

if [[ "$DEL_IMAGE" =~ ^[sS]$ ]]; then
    FULL_PATH="$REPO_REGION-docker.pkg.dev/$PROJECT_ID/$SELECTED_REPO/$IMAGE_NAME"

    # Obtener el digest
    if [[ "$SEP" == ":" ]]; then
        DIGEST=$(gcloud artifacts docker images describe "$FULL_PATH:$TAG_OR_DIGEST" --format="value(image_summary.digest)" 2>/dev/null)
    else
        DIGEST="$TAG_OR_DIGEST"
    fi

    # Obtener tags asociados al digest
    TAGS=$(gcloud artifacts docker images list-tags "$FULL_PATH" \
        --filter="image_summary.digest:$DIGEST" \
        --format="get(tags)" 2>/dev/null)

    # Eliminar los tags si existen
    if [[ -n "$TAGS" ]]; then
        echo -e "${CYAN}🧹 Eliminando tags asociados al digest:${RESET}"
        while IFS= read -r TAG; do
            [[ -n "$TAG" ]] && gcloud artifacts docker images delete "$FULL_PATH:$TAG" --quiet && \
            echo -e "   🗑️  Tag eliminado: ${TAG}"
        done <<< "$TAGS"
    else
        echo -e "${YELLOW}⚠️ No se encontraron tags asociados al digest.${RESET}"
    fi

    # Verificar que ya no hay tags antes de eliminar digest
    REMAINING=$(gcloud artifacts docker images list-tags "$FULL_PATH" \
        --filter="image_summary.digest:$DIGEST" \
        --format="get(tags)" 2>/dev/null)

    if [[ -z "$REMAINING" ]]; then
        echo -e "${CYAN}🧹 Eliminando digest: ${DIGEST}${RESET}"
        gcloud artifacts docker images delete "$FULL_PATH@$DIGEST" --quiet && \
        echo -e "${GREEN}✅ Digest eliminado correctamente.${RESET}"
    else
        echo -e "${RED}❌ Digest aún tiene tags activos. No se eliminó.${RESET}"
    fi
fi

if [[ "$DEL_REPO" =~ ^[sS]$ ]]; then
    echo -e "${CYAN}🧹 Eliminando repositorio...${RESET}"
    gcloud artifacts repositories delete "$SELECTED_REPO" --location="$REPO_REGION" --quiet
fi

# Limpieza final
rm -rf "$TMP_DIR"

echo -e "\n${GREEN}✅ Proceso finalizado.${RESET}"
