#!/bin/bash

# Colores y estilo
RED="\e[31m"
GREEN="\e[32m"
CYAN="\e[36m"
YELLOW="\e[33m"
RESET="\e[0m"
BOLD="\e[1m"

# Validar que gcloud esté instalado
command -v gcloud >/dev/null 2>&1 || { echo -e "${RED}❌ gcloud no está instalado.${RESET}"; exit 1; }

# Regiones a revisar (todas las disponibles)
REGIONS=(
  "africa-south1" "northamerica-northeast1" "northamerica-northeast2" "northamerica-south1"
  "southamerica-east1" "southamerica-west1" "us-central1" "us-east1" "us-east4" "us-east5"
  "us-south1" "us-west1" "us-west2" "us-west3" "us-west4" "asia-east1" "asia-east2"
  "asia-northeast1" "asia-northeast2" "asia-northeast3" "asia-south1" "asia-south2"
  "asia-southeast1" "asia-southeast2" "australia-southeast1" "australia-southeast2"
  "europe-central2" "europe-north1" "europe-north2" "europe-southwest1" "europe-west1"
  "europe-west2" "europe-west3" "europe-west4" "europe-west6" "europe-west8" "europe-west9"
  "europe-west10" "europe-west12" "me-central1" "me-central2" "me-west1"
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

# Array para guardar resultados
declare -a SERVICES_INFO
INDEX=1

# Archivo temporal para almacenar resultados
TMP_FILE=$(mktemp)

# Paralelizar búsquedas y almacenar en archivo temporal
for REGION in "${REGIONS[@]}"; do
  (
    SERVICES=$(gcloud run services list --platform managed --region "$REGION" --format="json" 2>/dev/null)
    if [[ "$SERVICES" != "[]" ]]; then
      echo "$SERVICES" | jq -c ".[] | {region: \"$REGION\", name: .metadata.name}" >> "$TMP_FILE"
    fi
  ) &
done
wait

# Procesar resultados
while IFS= read -r ENTRY; do
  REGION=$(echo "$ENTRY" | jq -r '.region')
  SERVICE=$(echo "$ENTRY" | jq -r '.name')
  IMAGE=$(gcloud run services describe "$SERVICE" --platform managed --region "$REGION" --format="value(spec.template.spec.containers[0].image)" 2>/dev/null)

  if [[ -z "$IMAGE" ]]; then
    echo -e "${YELLOW}⚠️ No se pudo obtener la imagen del servicio ${SERVICE} en ${REGION}.${RESET}"
    continue
  fi

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
  echo -e "${YELLOW}${INDEX})${RESET} ${BOLD}${SERVICE}${RESET} (${REGION})   ${GREEN}${IMAGE_NAME}${SEP}${TAG_OR_DIGEST}${RESET}   ${CYAN}${REPO_NAME}:${REPO_REGION}${RESET}"
  ((INDEX++))
done < "$TMP_FILE"

rm -f "$TMP_FILE"

# Si no hay servicios
if [[ ${#SERVICES_INFO[@]} -eq 0 ]]; then
    echo -e "${RED}❌ No se encontraron servicios de Cloud Run.${RESET}"
    exit 0
fi

echo -e "${CYAN}🔎 Se encontraron ${#SERVICES_INFO[@]} servicios en total.${RESET}"

# Mostrar opción de salir
echo -e "${YELLOW}0)${RESET} ${BOLD}❌ Salir sin hacer cambios${RESET}"

# Leer selección
while true; do
  echo -e ""
  read -rp "${BOLD}Seleccione el número del servicio a gestionar (0 para salir): ${RESET}" SELECCION

  if [[ "$SELECCION" == "0" ]]; then
    echo -e "${CYAN}🚪 Saliendo sin cambios...${RESET}"
    exit 0
  elif [[ "$SELECCION" =~ ^[0-9]+$ ]] && (( SELECCION > 0 && SELECCION <= ${#SERVICES_INFO[@]} )); then
    break
  else
    echo -e "${RED}❌ Selección inválida. Intente nuevamente.${RESET}"
  fi
done

# Extraer selección
INDEX=$((SELECCION - 1))
IFS='|' read -r SELECTED_SERVICE SELECTED_REGION IMAGE_NAME SEP TAG_OR_DIGEST SELECTED_REPO REPO_REGION <<< "${SERVICES_INFO[$INDEX]}"

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

    TAGS=$(gcloud artifacts docker images list-tags "$FULL_PATH" --filter="image_summary.digest=$DIGEST" --format="value(tags[])" 2>/dev/null)
    IFS=$'\n'
    for TAG in $TAGS; do
        echo -e "${CYAN}🧹 Eliminando tag: ${TAG}${RESET}"
        gcloud artifacts docker images delete "$FULL_PATH:$TAG" --quiet
    done
    unset IFS

    echo -e "${CYAN}🧹 Eliminando digest: $DIGEST${RESET}"
    gcloud artifacts docker images delete "$FULL_PATH@$DIGEST" --quiet || \
        echo -e "${RED}⚠️ No se pudo eliminar el digest. Puede que todavía tenga etiquetas.${RESET}"
fi

if [[ "$DEL_REPO" =~ ^[sS]$ ]]; then
    echo -e "${CYAN}🧹 Eliminando repositorio...${RESET}"
    gcloud artifacts repositories delete "$SELECTED_REPO" --location="$REPO_REGION" --quiet
fi

echo -e "\n${GREEN}✅ Proceso finalizado.${RESET}"
