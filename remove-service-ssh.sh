#!/bin/bash

# Colores
RED="\e[31m"
GREEN="\e[32m"
CYAN="\e[36m"
YELLOW="\e[33m"
RESET="\e[0m"

SEPARATOR="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo -e "${CYAN}"
echo "$SEPARATOR"
echo "🔍 DETECTANDO SERVICIOS DESPLEGADOS CON IMAGEN DOCKER"
echo "$SEPARATOR"
echo -e "${RESET}"

# Pedimos datos base
read -p "🧱 Nombre del proyecto (GCP): " PROJECT_ID
read -p "🌍 Región (ej. us-central1): " REGION
read -p "📦 Nombre del repositorio (Artifact Registry): " REPO_NAME
read -p "🐳 Nombre de la imagen Docker (sin tag): " IMAGE_NAME

IMAGE_PATH="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${IMAGE_NAME}"

echo -e "${CYAN}"
echo "$SEPARATOR"
echo "🔎 BUSCANDO SERVICIOS QUE USEN LA IMAGEN: ${IMAGE_PATH}:latest"
echo "$SEPARATOR"
echo -e "${RESET}"

# Obtenemos lista de servicios en la región
SERVICES=$(gcloud run services list \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --format="value(metadata.name)")

MATCHING_SERVICES=()
for SERVICE in $SERVICES; do
  CURRENT_IMAGE=$(gcloud run services describe "$SERVICE" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --format="value(spec.template.spec.containers[0].image)")

  if [[ "$CURRENT_IMAGE" == "${IMAGE_PATH}:latest" ]]; then
    MATCHING_SERVICES+=("$SERVICE")
  fi
done

if [ ${#MATCHING_SERVICES[@]} -eq 0 ]; then
  echo -e "${YELLOW}⚠ No se encontraron servicios usando esta imagen.${RESET}"
else
  echo -e "${GREEN}✔ Se encontraron los siguientes servicios:${RESET}"
  for i in "${!MATCHING_SERVICES[@]}"; do
    echo "  $((i+1)). ${MATCHING_SERVICES[$i]}"
  done

  echo -e "${CYAN}"
  echo "$SEPARATOR"
  echo "🗑️ SELECCIONA LOS SERVICIOS A ELIMINAR"
  echo "$SEPARATOR"
  echo -e "${RESET}"

  read -p "✏️ Ingrese los números separados por espacios (ej: 1 3): " SELECTED

  for num in $SELECTED; do
    INDEX=$((num-1))
    SERVICE_NAME="${MATCHING_SERVICES[$INDEX]}"
    echo -e "${YELLOW}🧨 Eliminando servicio: ${SERVICE_NAME}${RESET}"
    gcloud run services delete "$SERVICE_NAME" \
      --project="$PROJECT_ID" \
      --region="$REGION" \
      --quiet
  done

  echo -e "${GREEN}✔ Servicios seleccionados eliminados.${RESET}"
fi

echo -e "${CYAN}"
echo "$SEPARATOR"
echo "🧹 ELIMINANDO IMAGEN EN ARTIFACT REGISTRY"
echo "$SEPARATOR"
echo -e "${RESET}"

gcloud artifacts docker images delete "${IMAGE_PATH}:latest" \
  --project="$PROJECT_ID" \
  --quiet
echo -e "${GREEN}✔ Imagen Docker eliminada.${RESET}"

echo -e "${CYAN}"
echo "$SEPARATOR"
echo "📦 OPCIONAL: ELIMINAR REPOSITORIO DE ARTIFACT REGISTRY"
echo "$SEPARATOR"
echo -e "${RESET}"

read -p "❓ ¿Quieres eliminar el repositorio '${REPO_NAME}' también? (s/N): " DELETE_REPO
DELETE_REPO=${DELETE_REPO,,}

if [[ "$DELETE_REPO" == "s" || "$DELETE_REPO" == "y" ]]; then
  gcloud artifacts repositories delete "$REPO_NAME" \
    --location="$REGION" \
    --project="$PROJECT_ID" \
    --quiet
  echo -e "${GREEN}✔ Repositorio eliminado.${RESET}"
else
  echo -e "${YELLOW}⏭ Repositorio conservado.${RESET}"
fi

echo -e "${CYAN}"
echo "$SEPARATOR"
echo "✅ REVERTIR COMPLETADO"
echo "$SEPARATOR"
echo -e "${RESET}"
