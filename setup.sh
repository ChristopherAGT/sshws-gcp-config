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

# 🔧 Región por defecto
REGION="us-east1"  # Carolina del Sur

echo -e "${cyan}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 SELECCIÓN DE REPOSITORIO EN ARTIFACT REGISTRY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

while true; do
    echo -e "${neutro}"
    PS3=$'\e[33mSeleccione una opción:\e[0m '
    select opcion in "Usar existente" "Crear nuevo"; do
        case $REPLY in
            1)
                echo -e "${azul}🔍 Buscando repositorios disponibles en $REGION...${neutro}"
                REPO_LIST=$(gcloud artifacts repositories list --location="$REGION" --format="value(name)")
                if [[ -z "$REPO_LIST" ]]; then
                    echo -e "${rojo}❌ No hay repositorios disponibles en $REGION. Se creará uno nuevo.${neutro}"
                    opcion="Crear nuevo"
                    break 2
                else
                    PS3=$'\e[33mSeleccione un repositorio:\e[0m '
                    select repo in $REPO_LIST; do
                        if [[ -n "$repo" ]]; then
                            REPO_NAME=$(basename "$repo")
                            echo -e "${verde}✔ Repositorio seleccionado: $REPO_NAME${neutro}"
                            break 3
                        else
                            echo -e "${rojo}❌ Selección no válida. Intenta nuevamente.${neutro}"
                        fi
                    done
                fi
                ;;
            2)
                echo -e "${azul}📛 Ingresa un nombre para el nuevo repositorio (Enter para usar 'google-cloud'):${neutro}"
                read -p "📝 Nombre del repositorio: " input_repo
                REPO_NAME="${input_repo:-google-cloud}"
                echo -e "${verde}✔ Repositorio a crear/usar: $REPO_NAME${neutro}"
                break 2
                ;;
            *)
                echo -e "${rojo}❌ Opción inválida. Por favor selecciona 1 o 2.${neutro}"
                break
                ;;
        esac
    done
done

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

echo -e "${cyan}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 VERIFICANDO EXISTENCIA DEL REPOSITORIO"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
EXISTS=$(gcloud artifacts repositories list \
    --location="$REGION" \
    --filter="name~$REPO_NAME" \
    --format="value(name)")

if [[ -n "$EXISTS" ]]; then
    echo -e "${amarillo}⚠️ El repositorio '$REPO_NAME' ya existe. Omitiendo creación.${neutro}"
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
    
    EXISTS_IMAGE=$(gcloud artifacts docker images list "$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME" \
        --format="get(package)" \
        --filter="package='$IMAGE_NAME'")

    if [[ -n "$EXISTS_IMAGE" ]]; then
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
