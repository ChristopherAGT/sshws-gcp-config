#!/bin/bash

# ╔════════════════════════════════════════════════════════╗
# ║      🚀 CREAR REPOSITORIO + CONSTRUIR Y SUBIR IMAGEN   ║
# ║                  ARTIFACT REGISTRY - GCP               ║
# ╚════════════════════════════════════════════════════════╝

# Colores 🎨
verde="\e[32m"
rojo="\e[31m"
azul="\e[34m"
amarillo="\e[33m"
cyan="\e[36m"
neutro="\e[0m"

# Lista de regiones con sus códigos y nombres
declare -A REGIONES_MAP=(
  [africa-south1]="Johannesburgo"
  [northamerica-northeast1]="Montreal"
  [northamerica-northeast2]="Toronto"
  [northamerica-south1]="México"
  [southamerica-east1]="São Paulo"
  [southamerica-west1]="Santiago"
  [us-central1]="Iowa"
  [us-east1]="Carolina del Sur"
  [us-east4]="Virginia del Norte"
  [us-east5]="Columbus"
  [us-south1]="Dallas"
  [us-west1]="Oregón"
  [us-west2]="Los Ángeles"
  [us-west3]="Salt Lake City"
  [us-west4]="Las Vegas"
  [asia-east1]="Taiwán"
  [asia-east2]="Hong Kong"
  [asia-northeast1]="Tokio"
  [asia-northeast2]="Osaka"
  [asia-northeast3]="Seúl"
  [asia-south1]="Bombay"
  [asia-south2]="Delhi"
  [asia-southeast1]="Singapur"
  [asia-southeast2]="Yakarta"
  [australia-southeast1]="Sídney"
  [australia-southeast2]="Melbourne"
  [europe-central2]="Varsovia"
  [europe-north1]="Finlandia"
  [europe-north2]="Estocolmo"
  [europe-southwest1]="Madrid"
  [europe-west1]="Bélgica"
  [europe-west2]="Londres"
  [europe-west3]="Fráncfort"
  [europe-west4]="Netherlands"
  [europe-west6]="Zúrich"
  [europe-west8]="Milán"
  [europe-west9]="París"
  [europe-west10]="Berlín"
  [europe-west12]="Turín"
  [me-central1]="Doha"
  [me-central2]="Dammam"
  [me-west1]="Tel Aviv"
)

# ---------------------------------------------------------
# 1. Buscar todos los repositorios en todas las regiones
# ---------------------------------------------------------

echo -e "${cyan}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 BUSCANDO REPOSITORIOS EN TODAS LAS REGIONES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

REPO_LIST_ALL=""
for region_code in "${!REGIONES_MAP[@]}"; do
    repos=$(gcloud artifacts repositories list --location="$region_code" --format="value(name)" 2>/dev/null)
    if [[ -n "$repos" ]]; then
        while read -r r; do
            REPO_LIST_ALL+="$region_code|$r"$'\n'
        done <<< "$repos"
    fi
done

# ---------------------------------------------------------
# 2. Si no hay repositorios, se creará uno nuevo
#    Si hay repositorios, mostrar para seleccionar
# ---------------------------------------------------------

if [[ -z "$REPO_LIST_ALL" ]]; then
    echo -e "${rojo}❌ No hay repositorios disponibles en ninguna región.${neutro}"
    opcion="Crear nuevo"
else
    echo -e "${verde}✔ Repositorios encontrados en las siguientes regiones:${neutro}"
    PS3=$'\e[33mSeleccione un repositorio:\e[0m '
    select repo_seleccionado in $(echo "$REPO_LIST_ALL" | awk -F'|' '{print $2 " (" $1 ")"}') "Crear nuevo"; do
        if [[ "$repo_seleccionado" == "Crear nuevo" ]]; then
            opcion="Crear nuevo"
            break
        elif [[ -n "$repo_seleccionado" ]]; then
            # Extraer región y nombre repo seleccionados
            linea_seleccion=$(echo "$REPO_LIST_ALL" | awk -F'|' -v repo="${repo_seleccionado% (*)}" '$2 == repo {print}')
            REGION=$(echo "$linea_seleccion" | cut -d '|' -f1)
            REPO_NAME=$(echo "$linea_seleccion" | cut -d '|' -f2)
            echo -e "${verde}✔ Repositorio seleccionado: $REPO_NAME en región $REGION${neutro}"
            break
        else
            echo -e "${rojo}❌ Selección inválida, intenta de nuevo.${neutro}"
        fi
    done
fi

# ---------------------------------------------------------
# 3. Si la opción es crear nuevo, pedir nombre y región
# ---------------------------------------------------------
if [[ "$opcion" == "Crear nuevo" ]]; then
    echo -e "${azul}📛 Ingresa un nombre para el nuevo repositorio (Enter para usar 'google-cloud'):${neutro}"
    read -p "📝 Nombre del repositorio: " input_repo
    REPO_NAME="${input_repo:-google-cloud}"

    echo -e "${cyan}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🌍 Selecciona la región para el nuevo repositorio"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    # Construir listado de regiones para selección
    regiones_array=()
    for region_code in "${!REGIONES_MAP[@]}"; do
        regiones_array+=("$region_code - ${REGIONES_MAP[$region_code]}")
    done

    PS3=$'\e[33mSeleccione la región:\e[0m '
    select region_sel in "${regiones_array[@]}"; do
        if [[ -n "$region_sel" ]]; then
            REGION="${region_sel%% -*}"  # Código antes del espacio y guion
            echo -e "${verde}✔ Región seleccionada: $REGION - ${REGIONES_MAP[$REGION]}${neutro}"
            break
        else
            echo -e "${rojo}❌ Selección inválida. Intenta de nuevo.${neutro}"
        fi
    done
fi

# ---------------------------------------------------------
# 4. Obtener el ID del proyecto
# ---------------------------------------------------------

echo -e "${cyan}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 OBTENIENDO ID DEL PROYECTO ACTIVO"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [[ -z "$PROJECT_ID" ]]; then
    echo -e "${rojo}❌ No se pudo obtener el ID del proyecto. Ejecuta 'gcloud init' primero.${neutro}"
    exit 1
fi
echo -e "${verde}✔ Proyecto activo: $PROJECT_ID${neutro}"

# ---------------------------------------------------------
# 5. Verificar o crear repositorio
# ---------------------------------------------------------

echo -e "${cyan}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 VERIFICANDO EXISTENCIA DEL REPOSITORIO"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
EXISTS=$(gcloud artifacts repositories list \
    --location="$REGION" \
    --filter="name~$REPO_NAME" \
    --format="value(name)")

if [[ -n "$EXISTS" ]]; then
    echo -e "${amarillo}⚠️ El repositorio '$REPO_NAME' ya existe en $REGION. Omitiendo creación.${neutro}"
else
    echo -e "${azul}📦 Creando repositorio...${neutro}"
    gcloud artifacts repositories create "$REPO_NAME" \
      --repository-format=docker \
      --location="$REGION" \
      --description="Repositorio Docker para SSH-WS en GCP" \
      --quiet
    [[ $? -ne 0 ]] && echo -e "${rojo}❌ Error al crear el repositorio.${neutro}" && exit 1
    echo -e "${verde}✅ Repositorio creado correctamente.${neutro}"
fi

# ---------------------------------------------------------
# 6. Configurar Docker para autenticación
# ---------------------------------------------------------

echo -e "${cyan}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔐 COMPROBANDO AUTENTICACIÓN DOCKER"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if ! grep -q "$REGION-docker.pkg.dev" ~/.docker/config.json 2>/dev/null; then
    echo -e "${azul}🔐 Configurando Docker para autenticación...${neutro}"
    gcloud auth configure-docker "$REGION-docker.pkg.dev" --quiet
    echo -e "${verde}✅ Docker autenticado correctamente.${neutro}"
else
    echo -e "${verde}🔐 Docker ya autenticado. Omitiendo configuración.${neutro}"
fi

# ---------------------------------------------------------
# 7. Construcción y subida de imagen Docker
# ---------------------------------------------------------

echo -e "${cyan}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🏗️ CONSTRUCCIÓN DE IMAGEN DOCKER"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

while true; do
    echo -e "${azul}📛 Ingresa un nombre para la imagen Docker (Enter para usar 'cloud3'):${neutro}"
    read -p "📝 Nombre de la imagen: " input_image
    IMAGE_NAME="${input_image:-cloud3}"
    IMAGE_TAG="1.0"
    IMAGE_PATH="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME"

    echo -e "${azul}🔍 Comprobando si la imagen '${IMAGE_NAME}:${IMAGE_TAG}' ya existe...${neutro}"
    
    IMAGE_FULL="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME:$IMAGE_TAG"

    if gcloud artifacts docker images describe "$IMAGE_FULL" &>/dev/null; then
        echo -e "${rojo}❌ Ya existe una imagen '${IMAGE_NAME}:${IMAGE_TAG}' en el repositorio.${neutro}"
        echo -e "${amarillo}🔁 Por favor, elige un nombre diferente para evitar sobrescribir.${neutro}"
        continue
    else
        echo -e "${verde}✔ Nombre de imagen válido y único.${neutro}"
        break
    fi
done

echo -e "${cyan}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📥 CLONANDO REPOSITORIO"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ -d "sshws-gcp" ]]; then
    echo -e "${amarillo}🧹 Eliminando versión previa del directorio sshws-gcp...${neutro}"
    rm -rf sshws-gcp
fi

git clone https://gitlab.com/PANCHO7532/sshws-gcp || {
    echo -e "${rojo}❌ Error al clonar el repositorio.${neutro}"
    exit 1
}

cd sshws-gcp || {
    echo -e "${rojo}❌ No se pudo acceder al directorio sshws-gcp.${neutro}"
    exit 1
}

echo -e "${cyan}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🐳 CONSTRUYENDO IMAGEN DOCKER"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
docker build -t "$IMAGE_PATH:$IMAGE_TAG" .

[[ $? -ne 0 ]] && echo -e "${rojo}❌ Error al construir la imagen.${neutro}" && exit 1

echo -e "${cyan}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📤 SUBIENDO IMAGEN A ARTIFACT REGISTRY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
docker push "$IMAGE_PATH:$IMAGE_TAG"

[[ $? -ne 0 ]] && echo -e "${rojo}❌ Error al subir la imagen.${neutro}" && exit 1

echo -e "${cyan}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧹 LIMPIANDO DIRECTORIO TEMPORAL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cd ..
rm -rf sshws-gcp

echo -e "${amarillo}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║ ✅ Imagen '$IMAGE_NAME:$IMAGE_TAG' subida exitosamente.       ║"
echo "║ 📍 Ruta: $IMAGE_PATH:$IMAGE_TAG"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${neutro}"
