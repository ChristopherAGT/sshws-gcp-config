#!/bin/bash

╔════════════════════════════════════════════╗

║     🔍 BUSCADOR Y ELIMINADOR DE CLOUD RUN   ║

╚════════════════════════════════════════════╝

Colores

RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' CYAN='\033[0;36m' NC='\033[0m'

Lista de regiones completas

REGIONES=( "africa-south1" "northamerica-northeast1" "northamerica-northeast2" "northamerica-south1" "southamerica-east1" "southamerica-west1" "us-central1" "us-east1" "us-east4" "us-east5" "us-south1" "us-west1" "us-west2" "us-west3" "us-west4" "asia-east1" "asia-east2" "asia-northeast1" "asia-northeast2" "asia-northeast3" "asia-south1" "asia-south2" "asia-southeast1" "asia-southeast2" "australia-southeast1" "australia-southeast2" "europe-central2" "europe-north1" "europe-north2" "europe-southwest1" "europe-west1" "europe-west2" "europe-west3" "europe-west4" "europe-west6" "europe-west8" "europe-west9" "europe-west10" "europe-west12" "me-central1" "me-central2" "me-west1" )

Declaración de arrays

SERVICIOS=() DETALLES=()

Buscar servicios en todas las regiones

for REGION in "${REGIONES[@]}"; do echo -e "${CYAN}🔍 Buscando en región: $REGION...${NC}" SERVICIOS_EN_REGION=$(gcloud run services list --platform=managed --region="$REGION" --format="value(metadata.name)" 2>/dev/null)

for SERVICE in $SERVICIOS_EN_REGION; do IMAGE=$(gcloud run services describe "$SERVICE" --platform=managed --region="$REGION" --format="value(spec.template.spec.containers[0].image)") IMAGE_TAG=$(basename "$IMAGE")

REPO_NAME=$(echo "$IMAGE" | cut -d'/' -f4)
REPO_REGION=$(echo "$IMAGE" | cut -d'.' -f1)

INDEX=${#SERVICIOS[@]}
SERVICIOS+=("$SERVICE|$REGION|$IMAGE|$REPO_NAME|$REPO_REGION")
DETALLES+=("$INDEX) ${SERVICE} - ${REGION}    Imagen: ${IMAGE_TAG}    Repositorio: ${REPO_NAME} - ${REPO_REGION}")

done

done

Mostrar lista de servicios encontrados

if [ ${#DETALLES[@]} -eq 0 ]; then echo -e "${YELLOW}⚠️  No se encontraron servicios en ninguna región.${NC}" exit 0 fi

echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" echo -e "${CYAN}📋 Servicios encontrados:${NC}" echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" for ITEM in "${DETALLES[@]}"; do echo "$ITEM" done

Solicitar selección

read -p $'\nIngrese el número del servicio que desea gestionar: ' SELECCION

IFS='|' read -r NAME REGION IMAGE REPO_NAME REPO_REGION <<< "${SERVICIOS[$SELECCION]}"

echo -e "\n${CYAN}Opciones de eliminación para:${NC}" echo -e "Servicio: ${YELLOW}$NAME${NC} (${REGION})" echo -e "Imagen: ${YELLOW}$IMAGE${NC}" echo -e "Repositorio: ${YELLOW}$REPO_NAME${NC} (${REPO_REGION})\n"

read -p "¿Eliminar servicio de Cloud Run? (s/n): " DEL_SERVICE read -p "¿Eliminar imagen del Artifact Registry? (s/n): " DEL_IMAGE read -p "¿Eliminar repositorio del Artifact Registry? (s/n): " DEL_REPO

Eliminar servicio

if [[ "$DEL_SERVICE" == "s" ]]; then echo -e "\n${RED}Eliminando servicio ${NAME}...${NC}" gcloud run services delete "$NAME" --platform=managed --region="$REGION" --quiet fi

Eliminar imagen

if [[ "$DEL_IMAGE" == "s" ]]; then echo -e "\n${RED}Eliminando imagen ${IMAGE}...${NC}" gcloud artifacts docker images delete "$IMAGE" --quiet || { echo -e "${YELLOW}⚠️  No se pudo eliminar la imagen. Es posible que tenga etiquetas activas.${NC}" } fi

Eliminar repositorio

if [[ "$DEL_REPO" == "s" ]]; then echo -e "\n${RED}Eliminando repositorio ${REPO_NAME} en ${REPO_REGION}...${NC}" gcloud artifacts repositories delete "$REPO_NAME" --location="$REPO_REGION" --quiet fi

echo -e "\n${GREEN}✅ Proceso finalizado.${NC}"

