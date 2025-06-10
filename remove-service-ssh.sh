#!/bin/bash

# ╭────────────────────────────────────────────────────────────╮
# │         GESTOR COMPLETO DE CLOUD RUN Y ARTIFACT REGISTRY   │
# ╰────────────────────────────────────────────────────────────╯

# Colores y estilo
RED="\e[1;31m"
GREEN="\e[1;32m"
CYAN="\e[1;36m"
YELLOW="\e[1;33m"
RESET="\e[0m"
BOLD="\e[1m"

# Spinner para mostrar mientras se recolectan servicios
spinner() {
  local pid=$1
  local delay=0.1
  local spin='/-\|'
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i+1) % 4 ))
    printf "\r$(tput el)🔄 Buscando servicios en todas las regiones... ${spin:i:1}"
    sleep $delay
  done
  printf "\r$(tput el)✅️ Servicios recolectados exitosamente.\n"
}

REGIONS=(
"africa-south1"
"northamerica-northeast1"
"northamerica-northeast2"
"northamerica-south1"
"southamerica-east1"
"southamerica-west1"
"us-central1"
"us-east1"
"us-east4"
"us-east5"
"us-south1"
"us-west1"
"us-west2"
"us-west3"
"us-west4"
"asia-east1"
"asia-east2"
"asia-northeast1"
"asia-northeast2"
"asia-northeast3"
"asia-south1"
"asia-south2"
"asia-southeast1"
"asia-southeast2"
"australia-southeast1"
"australia-southeast2"
"europe-central2"
"europe-north1"
"europe-north2"
"europe-southwest1"
"europe-west1"
"europe-west2"
"europe-west3"
"europe-west4"
"europe-west6"
"europe-west8"
"europe-west9"
"europe-west10"
"europe-west12"
"me-central1"
"me-central2"
"me-west1"
)

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
REPOS_JSON=$(gcloud artifacts repositories list --format=json 2>/dev/null)
REPO_NAMES=($(echo "$REPOS_JSON" | jq -r '.[].name'))

# Archivo temporal para recolectar servicios
tmpfile=$(mktemp)

# Obtener todos los servicios por región en segundo plano
(
  for REGION in "${REGIONS[@]}"; do
    SERVICES=$(gcloud run services list --platform managed --region "$REGION" --format=json 2>/dev/null)
    [[ "$SERVICES" == "[]" ]] && continue

    while read -r row; do
      SERVICE_NAME=$(echo "$row" | jq -r '.metadata.name')
      IMAGE=$(gcloud run services describe "$SERVICE_NAME" \
              --platform managed --region "$REGION" \
              --format="value(spec.template.spec.containers[0].image)" 2>/dev/null)
      echo "$SERVICE_NAME|$REGION|$IMAGE"
    done < <(echo "$SERVICES" | jq -c '.[]')
  done
) > "$tmpfile" &
spinner $!

# Leer resultados del archivo temporal
declare -A SERVICE_MAP
while IFS='|' read -r SERVICE_NAME REGION IMAGE; do
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
done < "$tmpfile"
rm -f "$tmpfile"

# Mostrar repositorios con su información (orden: Repositorio > Imagen > Servicio)
for repo in "${REPO_NAMES[@]}"; do
  REPO_REGION=$(echo "$repo" | cut -d/ -f4)
  REPO_NAME=$(echo "$repo" | cut -d/ -f6)

  KEY="$REPO_REGION|$REPO_NAME"
  INFO="${SERVICE_MAP[$KEY]}"

  echo -e "${YELLOW}$INDEX)${RESET} 📦 ${BOLD}Repositorio:${RESET} ${CYAN}${REPO_NAME}${RESET} (${REPO_REGION})"

  if [[ -n "$INFO" ]]; then
    declare -A IMAGES_MAP=()

    # Agrupar servicios por imagen
    while IFS='|' read -r _ SERVICE REGION IMAGE; do
      [[ -z "$IMAGE" ]] && continue
      IMAGES_MAP["$IMAGE"]+="$SERVICE|$REGION,"
    done <<< "$INFO"

    for IMAGE in "${!IMAGES_MAP[@]}"; do
      echo -e "  └─ 📸 ${BOLD}Imagen:${RESET} ${GREEN}${IMAGE}${RESET}"

      IFS=',' read -ra SERVICES <<< "${IMAGES_MAP[$IMAGE]}"
      for SERVICE_PAIR in "${SERVICES[@]}"; do
        [[ -z "$SERVICE_PAIR" ]] && continue
        IFS='|' read -r SERVICE REGION <<< "$SERVICE_PAIR"
        if [[ -n "$SERVICE" ]]; then
          echo -e "     └─ 🚀 ${BOLD}Servicio:${RESET} $SERVICE (${REGION})"
          ITEMS+=("$SERVICE|$REGION|$IMAGE|$REPO_NAME|$REPO_REGION")
        else
          echo -e "     └─ 🚀 ${BOLD}Servicio:${RESET} (ninguno)"
          ITEMS+=("||$IMAGE|$REPO_NAME|$REPO_REGION")
        fi
        ((INDEX++))
      done
    done
  else
    echo -e "  └─ 📸 ${BOLD}Imagen:${RESET} (ninguna)"
    echo -e "     └─ 🚀 ${BOLD}Servicio:${RESET} (ninguno)"
    ITEMS+=("|||$REPO_NAME|$REPO_REGION")
    ((INDEX++))
  fi
done

[[ ${#ITEMS[@]} -eq 0 ]] && echo -e "${RED}❌ No se encontraron servicios ni repositorios.${RESET}" && exit 0

while true; do
  echo -e "\n${BOLD}0) Salir sin hacer cambios${RESET}"
  echo -ne "${BOLD}\nSeleccione el ítem a gestionar: ${RESET}"
  read -r SELECCION

  # Validar que sea número entero
  if ! [[ "$SELECCION" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}❌ Entrada no válida. Por favor, seleccione una opción.${RESET}"
    continue
  fi

  if [[ "$SELECCION" == "0" ]]; then
    echo -e "${YELLOW}🚪 Saliendo...${RESET}"
    exit 0
  fi

  IDX=$((SELECCION - 1))
  if (( IDX < 0 || IDX >= ${#ITEMS[@]} )); then
    echo -e "${RED}❌ Selección no válida. Intente nuevamente.${RESET}"
  else
    break
  fi
done

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

# Mostrar datos
echo -e "\n🛠️  ${BOLD}Opciones para:${RESET}"
[[ -n "$SERVICE" ]] && echo -e "   🔹 Servicio: ${BOLD}${SERVICE}${RESET} (${REGION})"
[[ -z "$SERVICE" ]] && echo -e "   🔹 Servicio: (ninguno)"
[[ -n "$IMAGE_NAME" ]] && echo -e "   🔹 Imagen: ${GREEN}${IMAGE_NAME}${RESET} ${TAG:+(${TAG})}${DIGEST:+ [digest: ${DIGEST:0:12}...]}"
echo -e "   🔹 Repositorio: ${CYAN}${REPO}${RESET} (${REPO_REGION})"

# Función para pedir confirmación con validación
confirmar() {
  local pregunta="$1"
  local respuesta

  while true; do
    read -rp "$pregunta (s/n): " respuesta
    respuesta="${respuesta,,}"  # convertir a minúscula

    if [[ -z "$respuesta" ]]; then
      echo -e "${YELLOW}❎ Opción no seleccionada. Se tomará como NO.${RESET}"
      return 1
    elif [[ "$respuesta" == "s" ]]; then
      return 0
    elif [[ "$respuesta" == "n" ]]; then
      return 1
    else
      echo -e "${RED}⚠️ Opción inválida. Por favor, escriba ${BOLD}s${RESET}${RED} para sí o ${BOLD}n${RESET}${RED} para no.${RESET}"
    fi
  done
}

# Confirmaciones usando la función
[[ -n "$SERVICE" ]] && confirmar $'\n⛔️ ¿Desea eliminar el servicio de Cloud Run?' && DEL_SERVICE="s"
[[ -n "$IMAGE_NAME" ]] && confirmar '⛔️ ¿Desea eliminar la Imagen Docker del Repositorio?' && DEL_IMAGE="s"
confirmar '⛔️ ¿Desea eliminar el repositorio del Artifact Registry?' && DEL_REPO="s"

IMAGE_PATH="${REPO_REGION}-docker.pkg.dev/$PROJECT_ID/$REPO/$IMAGE_NAME"

# Eliminar servicio si se confirmó
if [[ "$DEL_SERVICE" == "s" ]]; then
  echo -e "${CYAN}🗑️ Eliminando servicio ${SERVICE}...${RESET}"
  gcloud run services delete "$SERVICE" --platform managed --region "$REGION" --quiet
fi

# Eliminar imagen si se confirmó
if [[ "$DEL_IMAGE" == "s" && -n "$IMAGE_NAME" ]]; then
  echo -e "${CYAN}🧹 Verificando imagen...${RESET}"

  # Verificar si existe otro servicio que usa esta imagen
  OTHER_SERVICE_FOUND=0
  for CHECK_REGION in "${REGIONS[@]}"; do
    SERVICES_IN_REGION=$(gcloud run services list --platform managed --region "$CHECK_REGION" --format=json 2>/dev/null)
    for row in $(echo "$SERVICES_IN_REGION" | jq -r '.[] | @base64'); do
      _jq() { echo "${row}" | base64 --decode | jq -r "${1}"; }
      S_NAME=$(_jq '.metadata.name')
      S_IMAGE=$(
        gcloud run services describe "$S_NAME" \
        --platform managed --region "$CHECK_REGION" \
        --format="value(spec.template.spec.containers[0].image)" 2>/dev/null
      )
      if [[ "$S_IMAGE" == *"$IMAGE_NAME"* ]]; then
        if [[ "$S_NAME" != "$SERVICE" || "$CHECK_REGION" != "$REGION" ]]; then
          OTHER_SERVICE_FOUND=1
          break 2
        fi
      fi
    done
  done

  if (( OTHER_SERVICE_FOUND == 1 )); then
    echo -e "${RED}❌ ERROR: No se puede borrar la imagen porque existe otro servicio Cloud Run que la está usando.${RESET}"
    exit 1
  fi

  # Si no encontró otro servicio usando la imagen, procede a eliminar
  if [[ -n "$DIGEST" ]]; then
    TAGS_JSON=$(gcloud artifacts docker tags list "$IMAGE_PATH" --format=json)
    TAGS_LINKED=($(echo "$TAGS_JSON" | jq -r --arg digest "$DIGEST" '.[] | select(.version == $digest) | .tag'))

    if (( ${#TAGS_LINKED[@]} > 1 )); then
      echo -e "${YELLOW}⚠️ Advertencia: Esta imagen tiene múltiples tags asociados a este digest. No se eliminarán para evitar afectar otras versiones.${RESET}"
    else
      echo -e "${CYAN}🗑️ Eliminando imagen por digest...${RESET}"
      gcloud artifacts docker images delete "$IMAGE_PATH@$DIGEST" --quiet
    fi
  else
    if [[ -n "$TAG" ]]; then
      echo -e "${CYAN}🗑️ Eliminando imagen con tag ${TAG}...${RESET}"
      gcloud artifacts docker images delete "$IMAGE_PATH:$TAG" --quiet
    else
      echo -e "${RED}❌ No se pudo determinar el tag o digest para eliminar la imagen.${RESET}"
    fi
  fi
fi

# Eliminar repositorio si se confirmó
if [[ "$DEL_REPO" == "s" ]]; then
  IMAGES_COUNT=$(gcloud artifacts docker images list "$REPO_REGION-docker.pkg.dev/$PROJECT_ID/$REPO" --format="value(NAME)" 2>/dev/null | wc -l)
  if (( IMAGES_COUNT == 0 )); then
    echo -e "${CYAN}🗑️ Eliminando repositorio ${REPO}...${RESET}"
    gcloud artifacts repositories delete "$REPO" --location="$REPO_REGION" --quiet
  else
    echo -e "${RED}❌ No se puede eliminar el repositorio porque contiene imágenes.${RESET}"
  fi
fi

echo -e "${GREEN}✅️ Operación completada.${RESET}"
