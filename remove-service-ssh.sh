#!/bin/bash

# Colores y estilo
RED="\e[31m"
GREEN="\e[32m"
CYAN="\e[36m"
YELLOW="\e[33m"
RESET="\e[0m"
BOLD="\e[1m"

# Regiones a revisar
REGIONS=(
  "africa-south1" "northamerica-northeast1" "northamerica-northeast2"
  "northamerica-south1" "southamerica-east1" "southamerica-west1"
  "us-central1" "us-east1" "us-east4" "us-east5" "us-south1"
  "us-west1" "us-west2" "us-west3" "us-west4"
  "asia-east1" "asia-east2" "asia-northeast1" "asia-northeast2"
  "asia-northeast3" "asia-south1" "asia-south2" "asia-southeast1"
  "asia-southeast2" "australia-southeast1" "australia-southeast2"
  "europe-central2" "europe-north1" "europe-north2" "europe-southwest1"
  "europe-west1" "europe-west2" "europe-west3" "europe-west4"
  "europe-west6" "europe-west8" "europe-west9" "europe-west10"
  "europe-west12" "me-central1" "me-central2" "me-west1"
)

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

declare -a SERVICES_INFO
INDEX=1

# Crear directorio temporal
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Búsqueda paralelizada
for REGION in "${REGIONS[@]}"; do
  (
    SERVICES=$(gcloud run services list --platform managed --region "$REGION" --format="json" 2>/dev/null)
    if [[ "$SERVICES" != "[]" ]]; then
      echo "$SERVICES" > "$TMP_DIR/$REGION.json"
    fi
  ) &
done
wait

# Procesar resultados
for REGION in "${REGIONS[@]}"; do
  FILE="$TMP_DIR/$REGION.json"
  [[ -f "$FILE" ]] || continue
  SERVICE_NAMES=$(jq -r '.[].metadata.name' < "$FILE")

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
done

if [[ ${#SERVICES_INFO[@]} -eq 0 ]]; then
  echo -e "${RED}❌ No se encontraron servicios de Cloud Run.${RESET}"
  exit 0
fi

echo -e "${YELLOW}0)${RESET} ${BOLD}❌ Salir sin hacer cambios${RESET}"

# Bucle de selección
while true; do
  echo -ne "\n${BOLD}Seleccione el número del servicio a gestionar (0 para salir): ${RESET}"
  read -r SELECCION

  if [[ "$SELECCION" == "0" ]]; then
    echo -e "${CYAN}🚪 Saliendo...${RESET}"
    exit 0
  elif [[ "$SELECCION" =~ ^[0-9]+$ ]] && ((SELECCION >= 1 && SELECCION < INDEX)); then
    break
  else
    echo -e "${RED}❌ Opción inválida. Intente nuevamente.${RESET}"
  fi
done

# Cargar información del servicio seleccionado
INDEX_REAL=$((SELECCION - 1))
IFS='|' read -r SELECTED_SERVICE SELECTED_REGION IMAGE_NAME SEP TAG_OR_DIGEST SELECTED_REPO REPO_REGION <<< "${SERVICES_INFO[$INDEX_REAL]}"

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

  if [[ "$SEP" == ":" ]]; then
    DIGEST=$(gcloud artifacts docker images describe "$FULL_PATH:$TAG_OR_DIGEST" --format="value(image_summary.digest)" 2>/dev/null)
  else
    DIGEST="$TAG_OR_DIGEST"
  fi

  TAGS=$(gcloud artifacts docker images list-tags "$FULL_PATH" --filter="image_summary.digest:$DIGEST" --format="value(tags[])" 2>/dev/null)
  for TAG in $TAGS; do
    echo -e "${CYAN}🧹 Eliminando tag: ${TAG}${RESET}"
    gcloud artifacts docker images delete "$FULL_PATH:$TAG" --quiet
  done

  echo -e "${CYAN}🧹 Eliminando digest: ${DIGEST}${RESET}"
  gcloud artifacts docker images delete "$FULL_PATH@$DIGEST" --quiet
fi

if [[ "$DEL_REPO" =~ ^[sS]$ ]]; then
  echo -e "${CYAN}🧹 Eliminando repositorio...${RESET}"
  gcloud artifacts repositories delete "$SELECTED_REPO" --location="$REPO_REGION" --quiet
fi

echo -e "\n${GREEN}✅ Proceso finalizado.${RESET}"
