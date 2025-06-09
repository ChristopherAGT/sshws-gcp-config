#!/bin/bash

# ╭────────────────────────────────────────────────────────────╮
# │         GESTOR COMPLETO DE CLOUD RUN Y ARTIFACT REGISTRY   │
# ╰────────────────────────────────────────────────────────────╯

# Colores y estilo
RED="\e[31m"
GREEN="\e[32m"
CYAN="\e[36m"
YELLOW="\e[33m"
RESET="\e[0m"
BOLD="\e[1m"

# Lista completa de regiones para Cloud Run
REGIONS=("us-central1" "us-east1" "us-west1" "europe-west1" "asia-east1")

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
[[ -z "$PROJECT_ID" ]] && echo -e "${RED}❌ No se pudo obtener el ID del proyecto.${RESET}" && exit 1

echo -e "${CYAN}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 RECOLECTANDO SERVICIOS DE CLOUD RUN Y REPOSITORIOS DE ARTIFACT..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${RESET}"

declare -a ITEMS
INDEX=1

# Obtener todos los repositorios del proyecto
REPOS_JSON=$(gcloud artifacts repositories list --format=json)
REPO_NAMES=($(echo "$REPOS_JSON" | jq -r '.[].name'))

# Obtener todos los servicios por región y mapear por repo (clave REPO_REGION|REPO_NAME)
declare -A SERVICE_MAP
for REGION in "${REGIONS[@]}"; do
    SERVICES=$(gcloud run services list --platform managed --region "$REGION" --format=json 2>/dev/null)
    [[ "$SERVICES" == "[]" ]] && continue

    for row in $(echo "$SERVICES" | jq -r '.[] | @base64'); do
        _jq() { echo "${row}" | base64 --decode | jq -r "${1}"; }
        SERVICE_NAME=$(_jq '.metadata.name')
        IMAGE=$(
            gcloud run services describe "$SERVICE_NAME" \
            --platform managed --region "$REGION" \
            --format="value(spec.template.spec.containers[0].image)" 2>/dev/null
        )

        if [[ "$IMAGE" =~ ^([a-z0-9-]+)-docker\.pkg\.dev/([^/]+)/([^/]+)/([^@:/]+)([@:][^ ]+)?$ ]]; then
            REPO_REGION="${BASH_REMATCH[1]}"
            PROJECT="${BASH_REMATCH[2]}"
            REPO_NAME="${BASH_REMATCH[3]}"
            IMAGE_NAME="${BASH_REMATCH[4]}"
            IMAGE_SUFFIX="${BASH_REMATCH[5]}"
            [[ "$IMAGE_SUFFIX" == @* ]] && TAG_OR_DIGEST="$IMAGE_NAME${IMAGE_SUFFIX}" || TAG_OR_DIGEST="$IMAGE_NAME:${IMAGE_SUFFIX#:}"
        else
            REPO_REGION="$REGION"
            REPO_NAME="?"
            TAG_OR_DIGEST=$(basename "$IMAGE")
        fi

        KEY="$REPO_REGION|$REPO_NAME"
        SERVICE_MAP["$KEY"]+="|$SERVICE_NAME|$REGION|$TAG_OR_DIGEST"
    done
done

# Mostrar repositorios con imágenes y servicios relacionados agrupados
for repo in "${REPO_NAMES[@]}"; do
    REPO_REGION=$(echo "$repo" | cut -d/ -f4)
    REPO_NAME=$(echo "$repo" | cut -d/ -f6)

    KEY="$REPO_REGION|$REPO_NAME"
    INFO="${SERVICE_MAP[$KEY]}"

    # Obtener imágenes dentro del repositorio
    IMAGES_JSON=$(gcloud artifacts docker images list "$REPO_REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME" --format=json 2>/dev/null)
    IMAGE_NAMES=($(echo "$IMAGES_JSON" | jq -r '.[].image'))

    # Mostrar encabezado del repositorio
    echo -e "${CYAN}${BOLD}$INDEX) Repositorio:${RESET} ${BOLD}$REPO_NAME${RESET} (${REPO_REGION})"
    ITEMS+=("|||$REPO_NAME|$REPO_REGION") # para opción de gestionar repositorio solo
    ((INDEX++))

    # Mostrar servicios asociados al repo, con imagen
    if [[ -n "$INFO" ]]; then
        while IFS='|' read -r _ SERVICE REGION IMG_TAG; do
            [[ -z "$SERVICE" ]] && continue
            echo -e "    🔹 Servicio: ${YELLOW}${SERVICE}${RESET} (${REGION})"
            echo -e "      📦 Imagen: ${GREEN}${IMG_TAG}${RESET}"
            ITEMS+=("$SERVICE|$REGION|$IMG_TAG|$REPO_NAME|$REPO_REGION")
            ((INDEX++))
        done <<< "$INFO"
    fi

    # Mostrar imágenes sin servicio asociado
    for IMG in "${IMAGE_NAMES[@]}"; do
        LOCALIZADA=0
        if [[ -n "$INFO" ]]; then
            while IFS='|' read -r _ _ _ IMG_SRV _ _; do
                [[ "$IMG" == "$IMG_SRV" ]] && LOCALIZADA=1 && break
            done <<< "$INFO"
        fi

        if (( LOCALIZADA == 0 )); then
            echo -e "    🖼️ Imagen sin servicio: ${GREEN}${IMG}${RESET}"
            ITEMS+=("| |$IMG|$REPO_NAME|$REPO_REGION")
            ((INDEX++))
        fi
    done

    echo # línea en blanco para separar repositorios
done

[[ ${#ITEMS[@]} -eq 0 ]] && echo -e "${RED}❌ No se encontraron servicios ni repositorios.${RESET}" && exit 0

echo -e "${BOLD}0) Cancelar y salir${RESET}"
echo -ne "${BOLD}\nSeleccione el número del ítem a gestionar: ${RESET}"
read -r SELECCION

if [[ "$SELECCION" == "0" ]]; then
    echo -e "${YELLOW}🚪 Saliendo...${RESET}"
    exit 0
fi

IDX=$((SELECCION - 1))
if (( IDX < 0 || IDX >= ${#ITEMS[@]} )); then
    echo -e "${RED}❌ Selección inválida.${RESET}"
    exit 1
fi

IFS='|' read -r SERVICE REGION IMAGE_TAG REPO REPO_REGION <<< "${ITEMS[$IDX]}"

if [[ "$IMAGE_TAG" == *@sha256:* ]]; then
    IMAGE_NAME=$(echo "$IMAGE_TAG" | cut -d'@' -f1)
    DIGEST=$(echo "$IMAGE_TAG" | cut -d'@' -f2)
    TAG=""
elif [[ "$IMAGE_TAG" == *:* ]]; then
    IMAGE_NAME="${IMAGE_TAG%%:*}"
    TAG="${IMAGE_TAG##*:}"
    DIGEST=""
else
    IMAGE_NAME="$IMAGE_TAG"
    TAG=""
    DIGEST=""
fi

echo -e "\n🛠️  ${BOLD}Opciones para:${RESET}"
[[ -n "$SERVICE" ]] && echo -e "   🔹 Servicio: ${BOLD}${SERVICE}${RESET} (${REGION})"
[[ -n "$IMAGE_NAME" ]] && echo -e "   🔹 Imagen: ${GREEN}${IMAGE_NAME}${RESET} ${TAG:+(tag: $TAG)}${DIGEST:+ (digest: ${DIGEST:0:12}...)}"
echo -e "   🔹 Repositorio: ${CYAN}${REPO}${RESET} (${REPO_REGION})"

if [[ -n "$SERVICE" ]]; then
    read -rp $'\n❓ ¿Eliminar servicio de Cloud Run? (s/n): ' DEL_SERVICE
fi
if [[ -n "$IMAGE_NAME" ]]; then
    read -rp '❓ ¿Eliminar imagen del Artifact Registry? (s/n): ' DEL_IMAGE
fi
read -rp '❓ ¿Eliminar repositorio del Artifact Registry? (s/n): ' DEL_REPO

IMAGE_PATH="${REPO_REGION}-docker.pkg.dev/$PROJECT_ID/$REPO/$IMAGE_NAME"

if [[ "$DEL_SERVICE" =~ ^[sS]$ ]]; then
    echo -e "${YELLOW}🗑️ Eliminando servicio Cloud Run...${RESET}"
    gcloud run services delete "$SERVICE" --platform managed --region "$REGION" --quiet
fi

if [[ "$DEL_IMAGE" =~ ^[sS]$ && -n "$IMAGE_NAME" ]]; then
    echo -e "${YELLOW}🧹 Eliminando imagen Docker...${RESET}"
    if [[ -n "$DIGEST" ]]; then
        # Borrar por digest
        gcloud artifacts docker images delete "$IMAGE_PATH@$DIGEST" --quiet
    elif [[ -n "$TAG" ]]; then
        gcloud artifacts docker images delete "$IMAGE_PATH:$TAG" --quiet
    else
        # Borrar imagen sin tag específico
        gcloud artifacts docker images delete "$IMAGE_PATH" --quiet
    fi
fi

if [[ "$DEL_REPO" =~ ^[sS]$ ]]; then
    echo -e "${YELLOW}🗃️ Verificando si el repositorio está vacío...${RESET}"
    COUNT_IMAGES=$(gcloud artifacts docker images list "$REPO_REGION-docker.pkg.dev/$PROJECT_ID/$REPO" --format="value(image)" | wc -l)
    if (( COUNT_IMAGES == 0 )); then
        echo -e "${YELLOW}🗑️ Eliminando repositorio...${RESET}"
        gcloud artifacts repositories delete "$REPO" --quiet
    else
        echo -e "${RED}❌ El repositorio no está vacío, no se puede eliminar.${RESET}"
    fi
fi

echo -e "${GREEN}✔️ Operación finalizada.${RESET}"
