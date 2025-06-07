# 🚀 DESPLEGUE DEL SERVICIO EN CLOUD RUN
echo -e "${cyan}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🌐 DESPLEGANDO SERVICIO EN CLOUD RUN"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${neutro}"

# Solicitar al usuario el nombre del servicio (default: rain)
read -p "📛 Ingresa el nombre que deseas para el servicio en Cloud Run (default: rain): " SERVICE_NAME
SERVICE_NAME=${SERVICE_NAME:-rain}

# Obtener número de proyecto
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")

# Ejecutar despliegue
SERVICE_URL=$(gcloud run deploy "$SERVICE_NAME" \
  --image "$IMAGE_PATH:$IMAGE_TAG" \
  --platform managed \
  --region "$REGION" \
  --allow-unauthenticated \
  --port 8080 \
  --quiet \
  --format="value(status.url)")

if [[ $? -ne 0 ]]; then
    echo -e "${rojo}❌ Error en el despliegue de Cloud Run.${neutro}"
    exit 1
fi

# Dominio regional del servicio
REGIONAL_DOMAIN="https://${SERVICE_NAME}-${PROJECT_NUMBER}.${REGION}.run.app"

# Mostrar resumen final
echo -e "${verde}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║ 📦 INFORMACIÓN DEL DESPLIEGUE EN CLOUD RUN                  ║"
echo "╠════════════════════════════════════════════════════════════╣"
echo "║ 🗂️ ID del Proyecto GCP  : $PROJECT_ID"
echo "║ 🔢 Número de Proyecto   : $PROJECT_NUMBER"
echo "║ 🗃️ Repositorio Docker   : $REPO_NAME"
echo "║ 🖼️ Nombre de la Imagen  : $IMAGE_NAME:$IMAGE_TAG"
echo "║ 📛 Nombre del Servicio  : $SERVICE_NAME"
echo "║ 📍 Región de Despliegue : $REGION"
echo "║ 🌐 Dominio Clásico      : $SERVICE_URL"
echo "║ 🌐 Dominio Regional     : $REGIONAL_DOMAIN"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${neutro}"
