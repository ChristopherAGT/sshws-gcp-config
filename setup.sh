#!/bin/bash

# ╔══════════════════════════════════════════════╗
# ║      🚀 CREACIÓN DE REPOSITORIO DOCKER      ║
# ║        EN ARTIFACT REGISTRY - GCP           ║
# ╚══════════════════════════════════════════════╝

# Colores 🎨
verde="\e[32m"
rojo="\e[31m"
azul="\e[34m"
amarillo="\e[33m"
neutro="\e[0m"

# 🔧 Configura esta variable
REGION="us-central1"

# 📝 Solicita nombre del repositorio
echo -e "${azul}📛 Ingresa un nombre para el repositorio (Enter para usar 'googlo-cloud'):${neutro}"
read -p "📝 Nombre del repositorio: " input_repo

# Usa el valor ingresado o el valor por defecto
REPO_NAME="${input_repo:-googlo-cloud}"

echo -e "${verde}✔ Repositorio a crear: $REPO_NAME${neutro}"

echo -e "${azul}🔍 Obteniendo ID del proyecto activo...${neutro}"
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

if [[ -z "$PROJECT_ID" ]]; then
    echo -e "${rojo}❌ No se pudo obtener el ID del proyecto. Asegúrate de tener una configuración activa con 'gcloud init'.${neutro}"
    exit 1
fi

echo -e "${verde}✔ Proyecto activo: $PROJECT_ID${neutro}"

echo -e "${azul}📦 Creando repositorio '$REPO_NAME' en región '$REGION'...${neutro}"

gcloud artifacts repositories create "$REPO_NAME" \
  --repository-format=docker \
  --location="$REGION" \
  --description="Repositorio Docker para SSH-WS en GCP" \
  --quiet

if [[ $? -ne 0 ]]; then
    echo -e "${rojo}❌ Error al crear el repositorio.${neutro}"
    exit 1
else
    echo -e "${verde}✅ Repositorio creado correctamente.${neutro}"
fi

echo -e "${azul}🔐 Configurando Docker para autenticación con Artifact Registry...${neutro}"

gcloud auth configure-docker "$REGION-docker.pkg.dev" --quiet

if [[ $? -ne 0 ]]; then
    echo -e "${rojo}❌ Error al configurar Docker.${neutro}"
    exit 1
else
    echo -e "${verde}✅ Docker configurado exitosamente.${neutro}"
fi

# 🎉 Mensaje final
echo -e "${amarillo}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║ ✅ El repositorio está listo para recibir tu imagen! ║"
echo "║ Usa este comando para construir tu imagen Docker:    ║"
echo "║                                                      ║"
echo "║  docker build -t $REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/sshws-image:latest ."
echo "║                                                      ║"
echo "║ Y luego púshala con:                                 ║"
echo "║                                                      ║"
echo "║  docker push $REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/sshws-image:latest"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${neutro}"
