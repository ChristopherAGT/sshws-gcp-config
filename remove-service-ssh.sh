#!/bin/bash

# ╭━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╮
# ┃ 🌐 GCP: GESTOR DE SERVICIOS CLOUD RUN         ┃
# ┃ 🔎 Buscar, mostrar y eliminar interactivo     ┃
# ╰━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╯

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# Lista completa de regiones
REGIONS=(
  "africa-south1" "northamerica-northeast1" "northamerica-northeast2"
  "northamerica-south1" "southamerica-east1" "southamerica-west1"
  "us-central1" "us-east1" "us-east4" "us-east5" "us-south1"
  "us-west1" "us-west2" "us-west3" "us-west4" "asia-east1" "asia-east2"
  "asia-northeast1" "asia-northeast2" "asia-northeast3" "asia-south1"
  "asia-south2" "asia-southeast1" "asia-southeast2" "australia-southeast1"
  "australia-southeast2" "europe-central2" "europe-north1" "europe-north2"
  "europe-southwest1" "europe-west1" "europe-west2" "europe-west3"
  "europe-west4" "europe-west6" "europe-west8" "europe-west9"
  "europe-west10" "europe-west12" "me-central1" "me-central2" "me-west1"
)

# Mapa de servicios
declare -A SERVICE_MAP
INDEX=0

echo -e "${CYAN}"
echo    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo    "🔍 BUSCANDO SERVICIOS DE CLOUD RUN EN TODAS LAS REGIONES"
echo    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${NC}"

for region in "${REGIONS[@]}"; do
  services=$(gcloud run services list --platform=managed --region="$region" --format="value(metadata.name)")
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    image=$(gcloud run services describe "$name" --region="$region" --format="value(spec.template.spec.containers[0].image)")
    [[ -z "$image" ]] && continue

    # Extraer nombre del repositorio y región de imagen
    REPO_REGION=$(echo "$image" | cut -d'.' -f1)
    REPOSITORY_NAME=$(echo "$image" | cut -d'/' -f3)

    SERVICE_MAP[$INDEX]="$name|$region|$image|$REPOSITORY_NAME|$REPO_REGION"
    echo -e "${YELLOW}${INDEX})${NC} ${BOLD}${name}${NC} (${region}) 🐳 ${image} 📦 ${REPOSITORY_NAME}:${REPO_REGION}"
    ((INDEX++))
  done <<< "$services"
done

if [ "$INDEX" -eq 0 ]; then
  echo -e "${RED}❌ No se encontraron servicios en ninguna región.${NC}"
  exit 1
fi

echo -e "\n${CYAN}📌 Ingresa el número del servicio que deseas gestionar:${NC}"
read -rp "➡️  Opción: " selected

if [[ ! ${SERVICE_MAP[$selected]} ]]; then
  echo -e "${RED}❌ Opción inválida.${NC}"
  exit 1
fi

IFS='|' read -r SERVICE_NAME SERVICE_REGION IMAGE_NAME REPOSITORY_NAME REPO_REGION <<< "${SERVICE_MAP[$selected]}"

echo -e "\n${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🛠️  OPCIONES DE ELIMINACIÓN PARA:"
echo -e "🔹 Servicio: ${SERVICE_NAME} (${SERVICE_REGION})"
echo -e "🔹 Imagen: ${IMAGE_NAME}"
echo -e "🔹 Repositorio: ${REPOSITORY_NAME} (${REPO_REGION})"
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

read -rp "❓ Eliminar servicio de Cloud Run? (s/n): " DEL_SVC
read -rp "❓ Eliminar imagen del Artifact Registry? (s/n): " DEL_IMG
read -rp "❓ Eliminar repositorio del Artifact Registry? (s/n): " DEL_REPO

# Eliminar servicio
if [[ "$DEL_SVC" =~ ^[sS]$ ]]; then
  echo -e "${CYAN}🧨 Eliminando servicio ${SERVICE_NAME}${NC}"
  gcloud run services delete "$SERVICE_NAME" --region="$SERVICE_REGION" --quiet
fi

# Eliminar imagen
if [[ "$DEL_IMG" =~ ^[sS]$ ]]; then
  echo -e "${CYAN}🧨 Eliminando imagen ${IMAGE_NAME}${NC}"
  gcloud artifacts docker images delete "$IMAGE_NAME" --quiet
fi

# Eliminar repositorio
if [[ "$DEL_REPO" =~ ^[sS]$ ]]; then
  if [[ -n "$REPOSITORY_NAME" && -n "$REPO_REGION" ]]; then
    echo -e "${CYAN}🧨 Eliminando repositorio ${REPOSITORY_NAME} (${REPO_REGION})${NC}"
    gcloud artifacts repositories delete "$REPOSITORY_NAME" --location="$REPO_REGION" --quiet
  else
    echo -e "${YELLOW}⚠️ No hay información válida de repositorio para eliminar.${NC}"
  fi
fi

echo -e "\n${GREEN}✅ Operación finalizada.${NC}"
