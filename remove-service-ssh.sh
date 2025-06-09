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

# Obtener todos los repositorios
REPOS_JSON=$(gcloud artifacts repositories list --format=json)
REPO_NAMES=($(echo "$REPOS_JSON" | jq -r '.[].name'))

# Mapear servicios
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

        # Extraer datos de la imagen
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

# Mostrar todos los repositorios
for repo in "${REPO_NAMES[@]}"; do
    REPO_REGION=$(echo "$repo" | cut -d/ -f4)
    REPO_NAME=$(echo "$repo" | cut -d/ -f6)
    KEY="$REPO_REGION|$REPO_NAME"
    INFO="${SERVICE_MAP[$KEY]}"

    if [[ -n "$INFO" ]]; then
        while IFS='|' read -r _ SERVICE REGION IMAGE; do
            [[ -z "$SERVICE" ]] && continue
            printf "${YELLOW}%s)${RESET} ☁️ %-20s %s\n" "$INDEX" "Servicio Cloud Run:" "$SERVICE ($REGION)"
            printf "    📦 %-20s %s\n" "Imagen Docker:" "$IMAGE"
            printf "    🗂️  %-20s %s\n" "Repositorio:" "$REPO_NAME ($REPO_REGION)"
            ITEMS+=("$SERVICE|$REGION|$IMAGE|$REPO_NAME|$REPO_REGION")
            ((INDEX++))
        done <<< "$INFO"
    else
        printf "${YELLOW}%s)${RESET} ☁️ %-20s %s\n" "$INDEX" "Servicio Cloud Run:" "-"
        printf "    📦 %-20s %s\n" "Imagen Docker:" "-"
        printf "    🗂️  %-20s %s\n" "Repositorio:" "$REPO_NAME ($REPO_REGION)"
        ITEMS+=("|||$REPO_NAME|$REPO_REGION")
        ((INDEX++))
    fi
done

[[ ${#ITEMS[@]} -eq 0 ]] && echo -e "${RED}❌ No se encontraron servicios ni repositorios.${RESET}" && exit 0

echo -e "\n${BOLD}0) Cancelar y salir${RESET}"
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

# Procesar imagen
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
[[ -n "$IMAGE_NAME" ]] && echo -e "   🔹 Imagen: ${GREEN}${IMAGE_NAME}${RESET} ${TAG:+(${TAG})}${DIGEST:+ [digest: ${DIGEST:0:12}...]}"
echo -e "   🔹 Repositorio: ${CYAN}${REPO}${RESET} (${REPO_REGION})"

[[ -n "$SERVICE" ]] && read -rp $'\n❓ ¿Eliminar servicio de Cloud Run? (s/n): ' DEL_SERVICE
[[ -n "$IMAGE_NAME" ]] && read -rp '❓ ¿Eliminar imagen del Artifact Registry? (s/n): ' DEL_IMAGE
read -rp '❓ ¿Eliminar repositorio del Artifact Registry? (s/n): ' DEL_REPO

IMAGE_PATH="${REPO_REGION}-docker.pkg.dev/$PROJECT_ID/$REPO/$IMAGE_NAME"

[[ "$DEL_SERVICE" =~ ^[sS]$ ]] && gcloud run services delete "$SERVICE" --platform managed --region "$REGION" --quiet

if [[ "$DEL_IMAGE" =~ ^[sS]$ && -n "$IMAGE_NAME" ]]; then
    echo -e "${CYAN}🧹 Verificando imagen...${RESET}"
    if [[ -n "$DIGEST" ]]; then
        TAGS_JSON=$(gcloud artifacts docker tags list "$IMAGE_PATH" --format=json)
        TAGS_LINKED=($(echo "$TAGS_JSON" | jq -r --arg digest "$DIGEST" '.[] | select(.version == $digest) | .tag'))

        if (( ${#TAGS_LINKED[@]} > 1 )); then
            echo -e "${YELLOW}⚠️ Otros tags apuntan al digest: ${RESET}${TAGS_LINKED[*]}"
            read -rp '❓ ¿Eliminar de todos modos? (s/n): ' CONFIRM
            [[ "$CONFIRM" =~ ^[sS]$ ]] && gcloud artifacts docker images delete "${IMAGE_PATH}@${DIGEST}" --quiet
        else
            gcloud artifacts docker images delete "${IMAGE_PATH}@${DIGEST}" --quiet
        fi
    elif [[ -n "$TAG" ]]; then
        gcloud artifacts docker images delete "${IMAGE_PATH}:$TAG" --quiet
    fi
fi

[[ "$DEL_REPO" =~ ^[sS]$ ]] && gcloud artifacts repositories delete "$REPO" --location="$REPO_REGION" --quiet

echo -e "\n${GREEN}✅ Proceso finalizado.${RESET}"
