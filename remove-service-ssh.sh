#!/bin/bash

# Colores y estilo con brillo/negrita
RED="\e[1;31m"
GREEN="\e[1;32m"
CYAN="\e[1;36m"
YELLOW="\e[1;33m"
RESET="\e[0m"
BOLD="\e[1m"

# Crear archivo temporal para regiones (se usa para sincronizar el proceso paralelo)
tmpfile=$(mktemp)

# Esta función elimina el archivo temporal y el propio script al salir (por cualquier razón)
trap 'rm -f -- "$0" "$tmpfile"' EXIT

# Definir regiones en el archivo temporal
cat > "$tmpfile" << EOF
us-central1
us-east1
us-west1
europe-west1
asia-east1
EOF

# Obtener proyecto actual
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

if [[ -z "$PROJECT_ID" ]]; then
    echo -e "${RED}❌ No se pudo obtener el ID del proyecto de GCP.${RESET}"
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo -e "${RED}❌ La herramienta 'jq' no está instalada. Instálala antes de continuar.${RESET}"
    exit 1
fi

echo -e "${CYAN}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 BUSCANDO SERVICIOS DE CLOUD RUN EN TODAS LAS REGIONES..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${RESET}"

# Archivos temporales para JSON y resultados
TMP_DIR=$(mktemp -d)
declare -a SERVICES_INFO
INDEX=1

# Función para buscar servicios en una región y guardar JSON
buscar_servicios_en_region() {
    local REGION=$1
    local TMP_FILE="$TMP_DIR/$REGION.json"
    gcloud run services list --platform managed --region "$REGION" --format="json" > "$TMP_FILE" 2>/dev/null
}

# Spinner para mostrar mientras se ejecutan procesos en paralelo
spinner() {
    local pid=$1
    local delay=0.1
    local spin='/-\|'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % 4 ))
        printf "\r$(tput el)Buscando servicios en Cloud Run... ${spin:i:1}"
        sleep $delay
    done
    printf "\r$(tput el)✅️ ¡Listo!                            \n"
}

# Leer regiones del archivo tmpfile y lanzar búsquedas en paralelo
while IFS= read -r REGION; do
    buscar_servicios_en_region "$REGION" &
done < "$tmpfile"
bg_pid=$!

spinner $bg_pid

wait $bg_pid 2>/dev/null

# Mostrar opción cancelar primero
echo -e "${YELLOW}0)${RESET} ${BOLD}❌ Cancelar / Salir${RESET}"

# Procesar resultados de cada región
while IFS= read -r REGION; do
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
done < "$tmpfile"

if [[ ${#SERVICES_INFO[@]} -eq 0 ]]; then
    echo -e "${RED}❌ No se encontraron servicios de Cloud Run.${RESET}"
    rm -rf "$TMP_DIR"
    exit 0
fi

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

    IMAGE_LIST=$(gcloud artifacts docker images list "$FULL_PATH" --include-tags --format=json 2>/dev/null)

    if [[ "$SEP" == ":" ]]; then
        DIGEST=$(echo "$IMAGE_LIST" | jq -r --arg TAG "$TAG_OR_DIGEST" '.[] | select(.tags[]? == $TAG) | .digest' | head -n1)
    else
        DIGEST="$TAG_OR_DIGEST"
    fi

    if [[ -z "$DIGEST" ]]; then
        echo -e "${RED}❌ No se pudo encontrar el digest para la imagen con tag ${BOLD}$TAG_OR_DIGEST${RESET}"
    else
        echo -e "${GREEN}✅ Digest encontrado:${RESET} ${DIGEST}"
        
        TAGS=$(echo "$IMAGE_LIST" | jq -r --arg D "$DIGEST" '.[] | select(.digest == $D) | .tags[]?')

        if [[ -z "$TAGS" ]]; then
            echo -e "${YELLOW}⚠️  No se encontraron tags asociados al digest.${RESET}"
        else
            for TAG in $TAGS; do
                echo -e "${CYAN}🧹 Eliminando tag: ${BOLD}${TAG}${RESET}"
                gcloud artifacts docker images delete "$FULL_PATH:$TAG" --quiet
            done
        fi

        echo -e "${CYAN}🧹 Eliminando digest: ${BOLD}${DIGEST}${RESET}"
        gcloud artifacts docker images delete "$FULL_PATH@$DIGEST" --quiet
    fi
fi

if [[ "$DEL_REPO" =~ ^[sS]$ ]]; then
    echo -e "${CYAN}🧹 Eliminando repositorio...${RESET}"
    gcloud artifacts repositories delete "$SELECTED_REPO" --location="$REPO_REGION" --quiet
fi

rm -rf "$TMP_DIR"

echo -e "\n${GREEN}✅ Proceso finalizado.${RESET}"
