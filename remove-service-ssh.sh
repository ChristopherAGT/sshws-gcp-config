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
REGIONS=(
  "us-central1" "us-east1" "us-west1" "europe-west1" "asia-east1"
)

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
[[ -z "$PROJECT_ID" ]] && echo -e "${RED}❌ No se pudo obtener el ID del proyecto.${RESET}" && exit 1

clear
echo -e "${CYAN}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 RECOLECTANDO SERVICIOS DE CLOUD RUN Y REPOSITORIOS DE ARTIFACT..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${RESET}"

declare -A SERVICE_MAP
declare -A IMAGE_MAP
declare -A REPO_IMAGES_MAP

# Obtener todos los repositorios del proyecto
REPOS_JSON=$(gcloud artifacts repositories list --format=json 2>/dev/null)
REPO_NAMES=($(echo "$REPOS_JSON" | jq -r '.[].name'))

if [[ ${#REPO_NAMES[@]} -eq 0 ]]; then
    echo -e "${RED}❌ No se encontraron repositorios en el proyecto.${RESET}"
    exit 0
fi

# Para cada repositorio, obtener sus imágenes
for repo_fullname in "${REPO_NAMES[@]}"; do
    REPO_REGION=$(echo "$repo_fullname" | cut -d/ -f4)
    REPO_NAME=$(echo "$repo_fullname" | cut -d/ -f6)
    REPO_IMAGES_JSON=$(gcloud artifacts docker images list "$REPO_REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME" --format=json 2>/dev/null)
    IMAGES=($(echo "$REPO_IMAGES_JSON" | jq -r '.[].image'))
    REPO_IMAGES_MAP["$REPO_REGION|$REPO_NAME"]="${IMAGES[*]}"
done

# Buscar servicios Cloud Run en todas las regiones y mapearlos con repositorio + imagen
for REGION in "${REGIONS[@]}"; do
    SERVICES_JSON=$(gcloud run services list --platform managed --region "$REGION" --format=json 2>/dev/null)
    [[ "$SERVICES_JSON" == "[]" ]] && continue

    for row in $(echo "$SERVICES_JSON" | jq -r '.[] | @base64'); do
        _jq() { echo "${row}" | base64 --decode | jq -r "${1}"; }
        SERVICE_NAME=$(_jq '.metadata.name')
        IMAGE_FULL=$(
            gcloud run services describe "$SERVICE_NAME" \
            --platform managed --region "$REGION" \
            --format="value(spec.template.spec.containers[0].image)" 2>/dev/null
        )
        if [[ "$IMAGE_FULL" =~ ^([a-z0-9-]+)-docker\.pkg\.dev/([^/]+)/([^/]+)/([^@:/]+)([@:][^ ]+)?$ ]]; then
            REPO_REGION="${BASH_REMATCH[1]}"
            PROJECT="${BASH_REMATCH[2]}"
            REPO_NAME="${BASH_REMATCH[3]}"
            IMAGE_NAME="${BASH_REMATCH[4]}"
            IMAGE_SUFFIX="${BASH_REMATCH[5]}"
            [[ "$IMAGE_SUFFIX" == @* ]] && TAG_OR_DIGEST="$IMAGE_NAME${IMAGE_SUFFIX}" || TAG_OR_DIGEST="$IMAGE_NAME:${IMAGE_SUFFIX#:}"
        else
            REPO_REGION="$REGION"
            REPO_NAME="?"
            TAG_OR_DIGEST=$(basename "$IMAGE_FULL")
        fi
        # Guardamos mapeo servicio -> repo/imagen
        KEY="$REPO_REGION|$REPO_NAME"
        SERVICE_MAP["$KEY"]+="$SERVICE_NAME|$REGION|$TAG_OR_DIGEST;"
        IMAGE_MAP["$SERVICE_NAME"]="$TAG_OR_DIGEST"
    done
done

clear
echo -e "${BOLD}Listado completo de servicios, imágenes y repositorios:${RESET}\n"

INDEX=1
declare -a ITEMS

for repo_fullname in "${REPO_NAMES[@]}"; do
    REPO_REGION=$(echo "$repo_fullname" | cut -d/ -f4)
    REPO_NAME=$(echo "$repo_fullname" | cut -d/ -f6)
    KEY="$REPO_REGION|$REPO_NAME"

    # Obtener servicios asociados a este repo
    SERVICES_INFO="${SERVICE_MAP[$KEY]}"
    IFS=';' read -ra SERVICE_ENTRIES <<< "$SERVICES_INFO"

    # Obtener imágenes en este repo
    IMAGES_STRING="${REPO_IMAGES_MAP[$KEY]}"
    IFS=' ' read -ra IMAGES <<< "$IMAGES_STRING"

    if [[ -z "$SERVICES_INFO" ]]; then
        # No hay servicios para este repo
        echo -e "${YELLOW}$INDEX)${RESET} ☁️ Servicio Cloud Run: ${RED}ninguno${RESET} Asociado a 🖼️ ${RED}ninguno${RESET}"
        echo -e "    📦 Imagen Docker: ${#IMAGES[@]} - "
        if [[ ${#IMAGES[@]} -eq 0 ]]; then
            echo -e "       ${RED}ninguno${RESET}"
        else
            for img in "${IMAGES[@]}"; do
                echo -e "       ${GREEN}${img}${RESET}"
            done
        fi
        echo -e "    📂 Repositorio: ${CYAN}${REPO_NAME}${RESET} (${REPO_REGION})"
        ITEMS+=("|||$REPO_NAME|$REPO_REGION")
        ((INDEX++))
    else
        # Para cada servicio, mostrar su info + la imagen y repo
        for srv_entry in "${SERVICE_ENTRIES[@]}"; do
            [[ -z "$srv_entry" ]] && continue
            IFS='|' read -r SERVICE REGION TAG_OR_DIGEST <<< "$srv_entry"
            IMAGE_DISPLAY="${IMAGE_MAP[$SERVICE]}"
            [[ -z "$IMAGE_DISPLAY" ]] && IMAGE_DISPLAY="ninguno"

            echo -e "${YELLOW}$INDEX)${RESET} ☁️ Servicio Cloud Run: ${BOLD}$SERVICE${RESET} Asociado a 🖼️ ${GREEN}${IMAGE_DISPLAY}${RESET}"
            echo -e "    📦 Imagen Docker:"

            # Mostrar todas las imágenes del repositorio
            if [[ ${#IMAGES[@]} -eq 0 ]]; then
                echo -e "       ${RED}ninguno${RESET}"
            else
                for img in "${IMAGES[@]}"; do
                    echo -e "       ${GREEN}${img}${RESET}"
                done
            fi

            echo -e "    📂 Repositorio: ${CYAN}${REPO_NAME}${RESET} (${REPO_REGION})"
            ITEMS+=("$SERVICE|$REGION|$IMAGE_DISPLAY|$REPO_NAME|$REPO_REGION")
            ((INDEX++))
        done
    fi
done

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
