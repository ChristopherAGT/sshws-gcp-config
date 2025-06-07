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
neutro="\e[0m"

# 🔧 Región por defecto
REGION="us-east1"  # Carolina del Sur

# 📝 Solicita nombre del repositorio
echo -e "${azul}📛 Ingresa un nombre para el repositorio (Enter para usar 'googlo-cloud'):${neutro}"
read -p "📝 Nombre del repositorio: " input_repo
REPO_NAME="${input_repo:-googlo-cloud}"
echo -e "${verde}✔ Repositorio a usar: $REPO_NAME${neutro}"

# 🔍 Obtener ID del proyecto
echo -e "${azul}🔍 Obteniendo ID del proyecto activo...${neutro}"
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [[ -z "$PROJECT_ID" ]]; then
    echo -e "${rojo}❌ No se pudo obtener el ID del proyecto. Ejecuta 'gcloud init' primero.${neutro}"
    exit 1
fi
echo -e "${verde}✔ Proyecto activo: $PROJECT_ID${neutro}"

# 📦 Verificar si el repositorio ya existe
echo -e "${azul}📦 Verificando existencia del repositorio '$REPO_NAME' en '$REGION'...${neutro}"
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

# 🔐 Verificar autenticación Docker
if ! grep -q "$REGION-docker.pkg.dev" ~/.docker/config.json 2>/dev/null; then
    echo -e "${azul}🔐 Configurando Docker para autenticación...${neutro}"
    gcloud auth configure-docker "$REGION-docker.pkg.dev" --quiet
    echo -e "${verde}✅ Docker autenticado correctamente.${neutro}"
else
    echo -e "${verde}🔐 Docker ya autenticado. Omitiendo configuración.${neutro}"
fi

# ╔════════════════════════════════════════════════════════════╗
# ║         🏗️ CREANDO / CONSTRUYENDO LA IMAGEN DOCKER       ║
# ╚════════════════════════════════════════════════════════════╝

# Bucle para obtener un nombre de imagen válido
while true; do
  echo -e "${azul}📛 Ingresa un nombre para la imagen Docker (Enter para usar 'cloud3'):${neutro}"
  read -p "📝 Nombre de la imagen: " input_image
  IMAGE_NAME="${input_image:-cloud3}"
  IMAGE_TAG="1.0"
  FULL_IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME:$IMAGE_TAG"

  # Verifica si la imagen ya existe
  EXISTS_IMG=$(gcloud artifacts docker images list "$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME" \
    --format="get(uri)" | grep "$IMAGE_NAME:$IMAGE_TAG")

  if [[ -n "$EXISTS_IMG" ]]; then
    echo -e "${amarillo}⚠️ Ya existe una imagen con el nombre '$IMAGE_NAME:$IMAGE_TAG'.${neutro}"
    echo -e "${amarillo}❓ ¿Deseas sobrescribirla? (s/n)${neutro}"
    read -p "👉 " resp
    if [[ "$resp" == "s" || "$resp" == "S" ]]; then
      break
    else
      echo -e "${rojo}🔁 Por favor ingresa un nuevo nombre para la imagen.${neutro}"
    fi
  else
    break
  fi
done

# 📁 Eliminar carpeta vieja si existe
if [[ -d "sshws-gcp" ]]; then
  echo -e "${amarillo}🧹 Eliminando versión anterior del repositorio 'sshws-gcp'...${neutro}"
  rm -rf sshws-gcp
fi

# 📥 Clonando repositorio
echo -e "${azul}📥 Clonando repositorio desde GitLab...${neutro}"
git clone https://gitlab.com/PANCHO7532/sshws-gcp

cd sshws-gcp || {
    echo -e "${rojo}❌ No se pudo acceder al directorio sshws-gcp.${neutro}"
    exit 1
}

# 🐳 Construyendo la imagen
echo -e "${azul}🐳 Iniciando construcción de la imagen Docker '$IMAGE_NAME:$IMAGE_TAG'...${neutro}"
docker build -t "$FULL_IMAGE" .

[[ $? -ne 0 ]] && echo -e "${rojo}❌ Error al construir la imagen.${neutro}" && exit 1

# 📤 Subiendo la imagen
echo -e "${azul}📤 Subiendo imagen a Artifact Registry...${neutro}"
docker push "$FULL_IMAGE"

[[ $? -ne 0 ]] && echo -e "${rojo}❌ Error al subir la imagen.${neutro}" && exit 1

# 🧹 Limpiar el repositorio clonado
cd ..
rm -rf sshws-gcp

# 🎉 Mensaje final
echo -e "${amarillo}"
echo "╔═════════════════════════════════════════════════════════════════╗"
echo "║ ✅ Imagen '$IMAGE_NAME:$IMAGE_TAG' subida exitosamente.            ║"
echo "║ 📍 Ruta: $FULL_IMAGE"
echo "╚═════════════════════════════════════════════════════════════════╝"
echo -e "${neutro}"
