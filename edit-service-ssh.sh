#!/bin/bash

# Colores
CYAN="\e[36m" ; GREEN="\e[32m" ; YELLOW="\e[33m" ; RED="\e[31m" ; NC="\e[0m"

# Eliminar este script automaticamente al salir.
trap 'rm -f -- "$0"' EXIT

# Lista de regiones de Cloud Run
REGIONS=(
  "asia-east1" "asia-east2" "asia-northeast1" "asia-northeast2" "asia-northeast3"
  "asia-south1" "asia-south2" "asia-southeast1" "asia-southeast2"
  "australia-southeast1" "australia-southeast2"
  "europe-central2" "europe-north1" "europe-west1" "europe-west2" "europe-west3"
  "europe-west4" "europe-west6"
  "me-west1" "me-central1"
  "northamerica-northeast1" "northamerica-northeast2"
  "southamerica-east1" "southamerica-west1"
  "us-central1" "us-east1" "us-east4" "us-east5"
  "us-south1" "us-west1" "us-west2" "us-west3" "us-west4"
)

# Función para mostrar el spinner
spinner() {
  local pid=$1
  local delay=0.1
  local spin='/-\|'
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i+1) % 4 ))
    printf "\r$(tput el)Buscando servicios en Cloud Run... ${spin:i:1}"
    sleep $delay
  done
  printf "\r$(tput el)Listo!                          \n"
}

# Encabezado
echo -e "${CYAN}"
echo    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo    "🔎 BUSCANDO SERVICIOS CLOUD RUN EN TODAS LAS REGIONES"
echo    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${NC}"

# Archivo temporal y cleanup
tmpfile=$(mktemp)
trap "rm -f $tmpfile" EXIT

# Buscar servicios en segundo plano
(
  for region in "${REGIONS[@]}"; do
    output=$(gcloud run services list --platform=managed --region="$region" --format="value(metadata.name)" 2>/dev/null)
    while read -r service; do
      if [[ -n "$service" ]]; then
        echo "$service|$region"
      fi
    done <<< "$output"
  done
) > "$tmpfile" &
pid=$!

# Mostrar spinner
spinner "$pid"

# Leer resultados
SERVICIOS=()
INFO_SERVICIOS=()

while IFS= read -r line; do
  service=$(cut -d '|' -f1 <<< "$line")
  SERVICIOS+=("$service")
  INFO_SERVICIOS+=("$line")
done < "$tmpfile"

# Validación
if [ ${#SERVICIOS[@]} -eq 0 ]; then
  echo -e "${RED}❌ No se encontraron servicios en Cloud Run.${NC}"
  exit 1
fi

# Mostrar servicios
echo -e "${YELLOW}Servicios disponibles:${NC}"
for i in "${!SERVICIOS[@]}"; do
  num=$((i + 1))
  region=$(cut -d '|' -f2 <<< "${INFO_SERVICIOS[$i]}")
  echo -e "  [${num}] ${GREEN}${SERVICIOS[$i]}${NC} (${CYAN}${region}${NC})"
done

# Selección
echo
while true; do
  read -p "👉 Seleccione el servicio que desea editar: " seleccion
  if [[ "$seleccion" =~ ^[0-9]+$ ]] && [ "$seleccion" -ge 1 ] && [ "$seleccion" -le "${#SERVICIOS[@]}" ]; then
    seleccion=$((seleccion - 1))
    break
  fi
  echo -e "${RED}❌ Selección inválida. Intente nuevamente.${NC}"
done

# Extraer nombre y región
SERVICIO_SELECCIONADO=$(cut -d '|' -f1 <<< "${INFO_SERVICIOS[$seleccion]}")
REGION_SELECCIONADA=$(cut -d '|' -f2 <<< "${INFO_SERVICIOS[$seleccion]}")

# Solicitar nuevo subdominio
echo
while true; do
  read -p "🌐 Ingrese su nuevo subdominio personalizado (cloudflare): " DHOST_VALOR
  if [[ -z "$DHOST_VALOR" ]]; then
    echo -e "${RED}❌ El campo no puede estar vacío.${NC}"
    continue
  fi
  if [[ ! "$DHOST_VALOR" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    echo -e "${RED}❌ Subdominio inválido. Ej: ejemplo.com o sub.dominio.net${NC}"
    continue
  fi
  break
done

# Confirmación
echo -e "\n🔧 Editando: ${GREEN}$SERVICIO_SELECCIONADO${NC} en ${CYAN}$REGION_SELECCIONADA${NC}"

# Aplicar cambios
echo -e "${CYAN}"
echo    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo    "🚀 APLICANDO CAMBIOS AL SERVICIO"
echo    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${NC}"

gcloud run services update "$SERVICIO_SELECCIONADO" \
  --region="$REGION_SELECCIONADA" \
  --platform=managed \
  --timeout=3600s \
  --concurrency=100 \
  --update-env-vars="DHOST=${DHOST_VALOR},DPORT=22"

# Verificación
if [ $? -eq 0 ]; then
  echo -e "\n✅ ${GREEN}Todos los cambios se aplicaron correctamente.${NC}"

  # Obtener URL pública
  SERVICE_URL=$(gcloud run services describe "$SERVICIO_SELECCIONADO" \
    --region="$REGION_SELECCIONADA" --platform=managed \
    --format="value(status.url)")

  # Obtener ID y número de proyecto
  PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
  PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")

  # Construir dominio regional
  REGIONAL_DOMAIN="https://${SERVICIO_SELECCIONADO}-${PROJECT_NUMBER}.${REGION_SELECCIONADA}.run.app"

  # Mostrar resultado final
  echo -e "🌐 URL del servicio   : ${CYAN}${SERVICE_URL}${NC}"
  echo -e "🌐 Dominio regional   : ${CYAN}${REGIONAL_DOMAIN}${NC}"
else
  echo -e "\n❌ ${RED}Hubo un error al aplicar los cambios.${NC}"
fi
