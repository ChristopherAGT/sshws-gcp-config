#!/bin/bash

# Colores para salida
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # Sin color

# Lista oficial completa de regiones GCP para Cloud Run
REGIONES=(
  africa-south1
  northamerica-northeast1
  northamerica-northeast2
  northamerica-south1
  southamerica-east1
  southamerica-west1
  us-central1
  us-east1
  us-east4
  us-east5
  us-south1
  us-west1
  us-west2
  us-west3
  us-west4
  asia-east1
  asia-east2
  asia-northeast1
  asia-northeast2
  asia-northeast3
  asia-south1
  asia-south2
  asia-southeast1
  asia-southeast2
  australia-southeast1
  australia-southeast2
  europe-central2
  europe-north1
  europe-north2
  europe-southwest1
  europe-west1
  europe-west2
  europe-west3
  europe-west4
  europe-west6
  europe-west8
  europe-west9
  europe-west10
  europe-west12
  me-central1
  me-central2
  me-west1
)

# Variables globales para guardar servicios listados
declare -a SERVICIOS
declare -a REGIONES_SERV
declare -a IMAGENES
declare -a REPOSITORIOS
declare -a REGIONES_REPO

PROYECTO=$(gcloud config get-value project)

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🔎 BUSCANDO SERVICIOS DE CLOUD RUN EN TODAS LAS REGIONES"
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Función para obtener repositorio y región desde imagen
function extraer_repo_region() {
  local imagen="$1"
  # Imagen típica: REGION-docker.pkg.dev/PROJECT/REPO/IMAGEN:TAG
  # Extraer repo y región del repositorio:
  # Ejemplo: us-east1-docker.pkg.dev/my-project/my-repo/my-image:tag
  # repo = my-repo, región repo = us-east1
  if [[ "$imagen" =~ ^([a-z0-9-]+)-docker\.pkg\.dev/[^/]+/([^/]+)/ ]]; then
    echo "${BASH_REMATCH[2]}" # repo
    echo "${BASH_REMATCH[1]}" # región repo
  else
    echo "" ""
  fi
}

# Recopilar servicios de todas las regiones
indice=0
for region in "${REGIONES[@]}"; do
  echo -ne "${YELLOW}Buscando en región: $region ... ${NC}"
  servicios_reg=$(gcloud run services list --platform managed --region "$region" --format="value(metadata.name)" 2>/dev/null)
  if [ -z "$servicios_reg" ]; then
    echo "no encontrado."
    continue
  fi
  echo "encontrado."

  # Para cada servicio, obtener imagen del último revision
  while IFS= read -r servicio; do
    imagen=$(gcloud run services describe "$servicio" --region "$region" --format="value(status.traffic[0].revisionName)" 2>/dev/null)
    # Obtener imagen desde revision:
    imagen_full=$(gcloud run revisions describe "$imagen" --region "$region" --format="value(spec.containers[0].image)" 2>/dev/null)
    if [ -z "$imagen_full" ]; then
      imagen_full="(no image info)"
    fi

    # Extraer repo y región repo
    read repo repo_region < <(extraer_repo_region "$imagen_full")

    SERVICIOS[indice]="$servicio"
    REGIONES_SERV[indice]="$region"
    IMAGENES[indice]="$imagen_full"
    REPOSITORIOS[indice]="$repo"
    REGIONES_REPO[indice]="$repo_region"

    ((indice++))
  done <<< "$servicios_reg"
done

if [ ${#SERVICIOS[@]} -eq 0 ]; then
  echo -e "${RED}No se encontraron servicios Cloud Run en ninguna región.${NC}"
  exit 0
fi

# Mostrar menú con todos los servicios encontrados
echo -e "\n${CYAN}Listado de servicios encontrados:${NC}"
for i in "${!SERVICIOS[@]}"; do
  echo -e "${YELLOW}$i)${NC} ${SERVICIOS[i]} (${REGIONES_SERV[i]})    Imagen: ${IMAGENES[i]}    Repo: ${REPOSITORIOS[i]} (${REGIONES_REPO[i]})"
done

echo
read -p "Ingrese el número del servicio a gestionar (o 'q' para salir): " opcion

if [[ "$opcion" =~ ^[Qq]$ ]]; then
  echo "Saliendo..."
  exit 0
fi

if ! [[ "$opcion" =~ ^[0-9]+$ ]] || [ "$opcion" -ge "${#SERVICIOS[@]}" ]; then
  echo -e "${RED}Opción inválida. Saliendo.${NC}"
  exit 1
fi

# Variables del servicio seleccionado
servicio_sel="${SERVICIOS[opcion]}"
region_sel="${REGIONES_SERV[opcion]}"
imagen_sel="${IMAGENES[opcion]}"
repo_sel="${REPOSITORIOS[opcion]}"
repo_region_sel="${REGIONES_REPO[opcion]}"

echo -e "\n${CYAN}Opciones de eliminación para:${NC}"
echo -e "Servicio: ${YELLOW}${servicio_sel} (${region_sel})${NC}"
echo -e "Imagen: ${YELLOW}${imagen_sel}${NC}"
echo -e "Repositorio: ${YELLOW}${repo_sel} (${repo_region_sel})${NC}"

# Preguntar confirmaciones
function preguntar() {
  local pregunta="$1"
  while true; do
    read -p "$pregunta (s/n): " yn
    case $yn in
      [Ss]*) return 0 ;;
      [Nn]*) return 1 ;;
      *) echo "Por favor responda s o n." ;;
    esac
  done
}

# Eliminar servicio Cloud Run
if preguntar "Eliminar servicio de Cloud Run?"; then
  echo -e "${YELLOW}Eliminando servicio ${servicio_sel}...${NC}"
  if gcloud run services delete "$servicio_sel" --region "$region_sel" --quiet; then
    echo -e "${GREEN}Servicio eliminado correctamente.${NC}"
  else
    echo -e "${RED}Error al eliminar servicio.${NC}"
  fi
else
  echo "Servicio NO eliminado."
fi

# Eliminar imagen Artifact Registry
if [ -n "$imagen_sel" ] && [ "$imagen_sel" != "(no image info)" ]; then
  if preguntar "Eliminar imagen del Artifact Registry?"; then
    echo -e "${YELLOW}Eliminando imagen ${imagen_sel}...${NC}"
    # Intentar eliminar la imagen completa (digest)
    if gcloud artifacts docker images delete "$imagen_sel" --quiet --delete-tags; then
      echo -e "${GREEN}Imagen eliminada correctamente.${NC}"
    else
      echo -e "${RED}Error al eliminar imagen. Puede que tenga etiquetas asociadas o esté en uso.${NC}"
    fi
  else
    echo "Imagen NO eliminada."
  fi
else
  echo "No hay información válida de imagen para eliminar."
fi

# Eliminar repositorio Artifact Registry
if [ -n "$repo_sel" ] && [ -n "$repo_region_sel" ]; then
  if preguntar "Eliminar repositorio del Artifact Registry?"; then
    echo -e "${YELLOW}Eliminando repositorio ${repo_sel} en región ${repo_region_sel}...${NC}"
    if gcloud artifacts repositories delete "$repo_sel" --location "$repo_region_sel" --quiet; then
      echo -e "${GREEN}Repositorio eliminado correctamente.${NC}"
    else
      echo -e "${RED}Error al eliminar repositorio.${NC}"
    fi
  else
    echo "Repositorio NO eliminado."
  fi
else
  echo "No hay información válida de repositorio para eliminar."
fi

echo -e "\n${GREEN}Proceso finalizado.${NC}"
