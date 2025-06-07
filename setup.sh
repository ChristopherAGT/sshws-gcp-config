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
echo "📛 SOLICITANDO NOMBRE DEL REPOSITORIO"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${azul}📛 Ingresa un nombre para el repositorio (Enter para usar 'googlo-cloud'):${neutro}"
read -p "📝 Nombre del repositorio: " input_repo
REPO_NAME="${input_repo:-googlo-cloud}"
echo -e "${verde}✔ Repositorio a usar: $REPO_NAME${neutro}"

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

# Bucle para solicitar nombre de imagen válido
while true; do
    echo -e "${azul}📛 Ingresa un nombre para la imagen Docker (Enter para usar 'cloud3'):${neutro}"
    read -p "📝 Nombre de la imagen: " input_image
    IMAGE_NAME="${input_image:-cloud3}"
    IMAGE_TAG="1.0"
    IMAGE_PATH="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME:$IMAGE_TAG"

    # Verificar si ya existe una imagen con ese nombre
    echo -e "${azul}🔍 Comprobando si la imagen '$IMAGE_NAME' ya existe...${neutro}"
    EXISTS_IMAGE=$(gcloud artifacts docker images list "$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME" \
        --format="value(NAME)" | grep -w "$IMAGE_NAME" || true)

    if [[ -n "$EXISTS_IMAGE" ]]; then
        echo -e "${amarillo}⚠️ Ya existe una imagen con el nombre '$IMAGE_NAME'.${neutro}"
        read -p "❓ ¿Deseas sobrescribirla? (s/n): " overwrite
        if [[ "$overwrite" =~ ^[Ss]$ ]]; then
            echo -e "${amarillo}⚠️ La imagen existente será sobrescrita...${neutro}"
            break
        else
            echo -e "${amarillo}🔁 Por favor, elige otro nombre para la imagen.${neutro}"
        fi
    else
        break
    fi
done

echo -e "${cyan}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📥 CLONANDO REPOSITORIO GIT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ -d "sshws-gcp" ]]; then
    echo -e "${amarillo}🧹 Eliminando versión previa del directorio sshws-gcp...${neutro}"
    rm -rf sshws-gcp
fi

git clone https://github.com/ChristopherAGT/sshws-gcp || {
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
docker build -t "$IMAGE_PATH" .

[[ $? -ne 0 ]] && echo -e "${rojo}❌ Error al construir la imagen.${neutro}" && exit 1

echo -e "${cyan}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📤 SUBIENDO IMAGEN A ARTIFACT REGISTRY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
docker push "$IMAGE_PATH"

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
echo "║ 📍 Ruta: $IMAGE_PATH"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${neutro}"
