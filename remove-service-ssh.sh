#!/bin/bash

# Colores y emojis
CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
BOLD='\033[1m'
RESET='\033[0m'

# Obtener ID del proyecto actual
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [[ -z "$PROJECT_ID" ]]; then
  echo -e "${YELLOW}⚠️  No se ha configurado un proyecto de GCP. Usa: gcloud config set project [PROJECT_ID]${RESET}"
  exit 1
fi

# Lista de regiones a revisar
REGIONS=(
  "us-central1" "us-east1" "us-east4" "us-west1" "us-west2" "us-west3" "us-west4"
  "northamerica-northeast1" "northamerica-northeast2"
  "southamerica-east1" "southamerica-west1"
  "europe-central2" "europe-north1" "europe-west1" "europe-west2" "europe-west3"
  "europe-west4" "europe-west6" "europe-southwest1"
  "asia-east1" "asia-east2" "asia-northeast1" "asia-northeast2" "asia-northeast3"
  "asia-south1" "asia-south2" "asia-southeast1" "asia-southeast2"
  "australia-southeast1" "australia-southeast2"
  "me-west1" "me-central1"
)

echo -e "${CYAN}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 EXPLORANDO SERVICIOS, IMÁGENES Y REPOSITORIOS EN CLOUD RUN"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${RESET}"

# Obtener todos los servicios Cloud Run por región y mapear imagen -> servicio
declare -A SERVICE_MAP
for REGION in "${REGIONS[@]}"; do
  SERVICES=$(gcloud run services list --platform=managed --region="$REGION" --format="value(metadata.name)")
  for SERVICE in $SERVICES; do
    IMAGE=$(gcloud run services describe "$SERVICE" --region="$REGION" --format="value(spec.template.spec.containers[0].image)")
    if [[ "$IMAGE" == *"docker.pkg.dev/"* ]]; then
      SERVICE_MAP["$IMAGE"]="$SERVICE|$REGION"
    fi
  done
done

# Obtener todos los repositorios
REPOS=$(gcloud artifacts repositories list --project="$PROJECT_ID" --format="value(name,format,location)")
INDEX=1
declare -a ITEMS

for REPO in $REPOS; do
  REPO_NAME=$(echo "$REPO" | awk '{print $1}')
  REPO_LOCATION=$(echo "$REPO" | awk '{print $3}')
  REPO_SHORT=$(basename "$REPO_NAME")

  IMAGES=$(gcloud artifacts docker images list "$REPO_NAME" --format="value(IMAGE)" --project="$PROJECT_ID")
  
  if [[ -z "$IMAGES" ]]; then
    echo -e "${YELLOW}${INDEX}) 🗂️ Repositorio:         ${REPO_SHORT} (${REPO_LOCATION})${RESET}"
    echo -e "    📦 Imagen Docker:    (sin imágenes)"
    echo -e "       ☁️ Servicio Cloud Run: (no asociado)"
    ITEMS+=("|$REPO_NAME|$REPO_LOCATION")
    ((INDEX++))
    continue
  fi

  for IMAGE in $IMAGES; do
    TAGS=$(gcloud artifacts docker images list-tags "$IMAGE" --format="value(tags)" --project="$PROJECT_ID")
    TAG=$(echo "$TAGS" | cut -d';' -f1 | cut -d',' -f1)
    IMAGE_FULL="${IMAGE}:${TAG}"

    MATCHED_SERVICE="${SERVICE_MAP[$IMAGE_FULL]}"
    echo -e "${GREEN}${INDEX}) 🗂️ Repositorio:         ${REPO_SHORT} (${REPO_LOCATION})${RESET}"
    echo -e "    📦 Imagen Docker:    ${TAG:+$IMAGE_FULL}"
    if [[ -n "$MATCHED_SERVICE" ]]; then
      SERVICE_NAME=$(echo "$MATCHED_SERVICE" | cut -d'|' -f1)
      SERVICE_REGION=$(echo "$MATCHED_SERVICE" | cut -d'|' -f2)
      echo -e "       ☁️ Servicio Cloud Run: ${SERVICE_NAME} (${SERVICE_REGION})"
    else
      echo -e "       ☁️ Servicio Cloud Run: (no asociado)"
    fi

    ITEMS+=("$IMAGE_FULL|$REPO_NAME|$REPO_LOCATION")
    ((INDEX++))
  done
done

# Menú de selección
echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}0) Cancelar y salir${RESET}"
echo -ne "${BOLD}\nSeleccione el número del ítem a gestionar: ${RESET}"
read -r SELECCION

if [[ "$SELECCION" == "0" ]]; then
  echo -e "${YELLOW}🚪 Saliendo...${RESET}"
  exit 0
fi

IDX=$((SELECCION-1))
if (( IDX<0 || IDX>=${#ITEMS[@]} )); then
  echo -e "${RED}❌ Selección inválida.${RESET}"
  exit 1
fi

IFS='|' read -r FULL_IMAGE SELECTED_REPO SELECTED_REGION <<< "${ITEMS[$IDX]}"

# Verificar si la selección fue de repositorio vacío
if [[ -z "$FULL_IMAGE" ]]; then
  echo -e "\n🛠️  ${BOLD}Opciones para el ítem ${SELECCION}:${RESET}"
  echo -e "   🔹 Repositorio: ${CYAN}${SELECTED_REPO} (${SELECTED_REGION})${RESET}"
  read -rp '❓ ¿Eliminar repositorio vacío? (s/n): ' DEL_REPO
  if [[ "$DEL_REPO" =~ ^[sS]$ ]]; then
    gcloud artifacts repositories delete "$SELECTED_REPO" --location "$SELECTED_REGION" --quiet
    echo -e "${GREEN}✅ Repositorio eliminado.${RESET}"
  fi
  exit 0
fi

echo -e "\n🛠️  ${BOLD}Opciones para el ítem ${SELECCION}:${RESET}"
echo -e "   🔹 Repositorio: ${CYAN}${SELECTED_REPO} (${SELECTED_REGION})${RESET}"
echo -e "   🔹 Imagen Docker: ${GREEN}${FULL_IMAGE}${RESET}"

# ¿Tiene servicio asociado?
MATCHED_SERVICE="${SERVICE_MAP[$FULL_IMAGE]}"
if [[ -n "$MATCHED_SERVICE" ]]; then
  SERVICE_NAME=$(echo "$MATCHED_SERVICE" | cut -d'|' -f1)
  SERVICE_REGION=$(echo "$MATCHED_SERVICE" | cut -d'|' -f2)
  echo -e "   🔹 Servicio Cloud Run: ${SERVICE_NAME} (${SERVICE_REGION})"
  read -rp $'\n❓ ¿Eliminar servicio Cloud Run? (s/n): ' DEL_SERVICE
fi

read -rp '❓ ¿Eliminar imagen Docker? (s/n): ' DEL_IMAGE
read -rp '❓ ¿Eliminar repositorio si queda vacío? (s/n): ' DEL_REPO_IF_EMPTY

# Ejecuciones
if [[ "$DEL_SERVICE" =~ ^[sS]$ ]]; then
  gcloud run services delete "$SERVICE_NAME" --region "$SERVICE_REGION" --platform managed --quiet
fi

if [[ "$DEL_IMAGE" =~ ^[sS]$ ]]; then
  gcloud artifacts docker images delete "$(echo "$FULL_IMAGE" | sed 's/:/@/')" --quiet || \
  gcloud artifacts docker images delete "$FULL_IMAGE" --quiet
fi

if [[ "$DEL_REPO_IF_EMPTY" =~ ^[sS]$ ]]; then
  LEFT=$(gcloud artifacts docker images list "$SELECTED_REPO" --format="value(IMAGE)" | wc -l)
  if [[ "$LEFT" == "0" ]]; then
    gcloud artifacts repositories delete "$SELECTED_REPO" --location "$SELECTED_REGION" --quiet
    echo -e "${GREEN}✅ Repositorio eliminado.${RESET}"
  else
    echo -e "${YELLOW}⚠️  El repositorio aún contiene imágenes. No se eliminó.${RESET}"
  fi
fi

echo -e "\n${GREEN}✅ Proceso finalizado.${RESET}"
