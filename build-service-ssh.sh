#!/bin/bash

# ╔════════════════════════════════════════════════════════╗
# ║      🚀 CREAR REPOSITORIO + CONSTRUIR Y SUBIR IMAGEN             ║
# ║                  ARTIFACT REGISTRY - GCP                         ║
# ╚════════════════════════════════════════════════════════╝

# Colores 🎨
verde="\e[1;32m"
rojo="\e[1;31m"
azul="\e[1;34m"
amarillo="\e[1;33m"
cyan="\e[1;36m"
neutro="\e[0m"

# 🔧 Región por defecto (se sobrescribirá con selección)
REGION={
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
                  }
                  #"us-east1"  # Carolina del Sur

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
    echo -e "${azul}🔍 Buscando repositorios disponibles en todas las regiones...${neutro}"

    REPOSITORIOS_ENCONTRADOS=()

    for region in "${REGION_CODES[@]}"; do
        repos=$(gcloud artifacts repositories list --location="$region" --format="value(name)" 2>/dev/null)
        while read -r repo; do
            [[ -n "$repo" ]] && REPOSITORIOS_ENCONTRADOS+=("$region|$repo")
        done <<< "$repos"
    done

    if [[ ${#REPOSITORIOS_ENCONTRADOS[@]} -eq 0 ]]; then
        echo -e "${rojo}❌ No hay repositorios disponibles en ninguna región. Se creará uno nuevo.${neutro}"
        opcion="Crear nuevo"
        break 2
    else
        echo -e "${cyan}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "📁 Repositorios encontrados en todas las regiones:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo -e "${neutro}"

        PS3=$'\e[33mSeleccione un repositorio:\e[0m '
        select repo in "${REPOSITORIOS_ENCONTRADOS[@]}"; do
            if [[ -n "$repo" ]]; then
                REGION=$(cut -d'|' -f1 <<< "$repo")
                REPO_NAME=$(basename "$(cut -d'|' -f2 <<< "$repo")")
                echo -e "${verde}✔ Repositorio seleccionado: $REPO_NAME (Región: $REGION)${neutro}"
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

                # -------------------- BLOQUE DE SELECCIÓN DE REGIÓN --------------------
                echo -e "${cyan}"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo "🌍 SELECCIÓN DE REGIÓN DE DESPLIEGUE"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo -e "${neutro}"

                declare -a REGIONS=(
                  "🇿🇦 africa-south1 (Johannesburgo)"
                  "🇨🇦 northamerica-northeast1 (Montreal)"
                  "🇨🇦 northamerica-northeast2 (Toronto)"
                  "🇲🇽 northamerica-south1 (México)"
                  "🇧🇷 southamerica-east1 (São Paulo)"
                  "🇨🇱 southamerica-west1 (Santiago)"
                  "🇺🇸 us-central1 (Iowa)"
                  "🇺🇸 us-east1 (Carolina del Sur)"
                  "🇺🇸 us-east4 (Virginia del Norte)"
                  "🇺🇸 us-east5 (Columbus)"
                  "🇺🇸 us-south1 (Dallas)"
                  "🇺🇸 us-west1 (Oregón)"
                  "🇺🇸 us-west2 (Los Ángeles)"
                  "🇺🇸 us-west3 (Salt Lake City)"
                  "🇺🇸 us-west4 (Las Vegas)"
                  "🇹🇼 asia-east1 (Taiwán)"
                  "🇭🇰 asia-east2 (Hong Kong)"
                  "🇯🇵 asia-northeast1 (Tokio)"
                  "🇯🇵 asia-northeast2 (Osaka)"
                  "🇰🇷 asia-northeast3 (Seúl)"
                  "🇮🇳 asia-south1 (Bombay)"
                  "🇮🇳 asia-south2 (Delhi)"
                  "🇸🇬 asia-southeast1 (Singapur)"
                  "🇮🇩 asia-southeast2 (Yakarta)"
                  "🇦🇺 australia-southeast1 (Sídney)"
                  "🇦🇺 australia-southeast2 (Melbourne)"
                  "🇵🇱 europe-central2 (Varsovia)"
                  "🇫🇮 europe-north1 (Finlandia)"
                  "🇸🇪 europe-north2 (Estocolmo)"
                  "🇪🇸 europe-southwest1 (Madrid)"
                  "🇧🇪 europe-west1 (Bélgica)"
                  "🇬🇧 europe-west2 (Londres)"
                  "🇩🇪 europe-west3 (Fráncfort)"
                  "🇳🇱 europe-west4 (Netherlands)"
                  "🇨🇭 europe-west6 (Zúrich)"
                  "🇮🇹 europe-west8 (Milán)"
                  "🇫🇷 europe-west9 (París)"
                  "🇩🇪 europe-west10 (Berlín)"
                  "🇮🇹 europe-west12 (Turín)"
                  "🇶🇦 me-central1 (Doha)"
                  "🇸🇦 me-central2 (Dammam)"
                  "🇮🇱 me-west1 (Tel Aviv)"
                )
                declare -a REGION_CODES=(
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

                for i in "${!REGIONS[@]}"; do
                  printf "%2d) %s\n" $((i+1)) "${REGIONS[$i]}"
                done

                while true; do
                  read -p "Ingrese el número de la región deseada: " REGION_INDEX
                  
                  if ! [[ "$REGION_INDEX" =~ ^[0-9]+$ ]] || (( REGION_INDEX < 1 || REGION_INDEX > ${#REGION_CODES[@]} )); then
                    echo -e "${rojo}"
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                    echo "❌ SELECCIÓN DE REGIÓN INVÁLIDA"
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                    echo -e "${neutro}"
                    echo -e "${rojo}❌ Selección inválida. Por favor ingrese un número válido.${neutro}"
                  else
                    REGION=${REGION_CODES[$((REGION_INDEX-1))]}
                    echo -e "${verde}✔ Región seleccionada: $REGION${neutro}"
                    break
                  fi
                done
                # -------------------- FIN BLOQUE SELECCIÓN DE REGIÓN --------------------

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
          
          # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 🖼️ OPCIÓN DE IMAGEN EXISTENTE O NUEVA
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo -e "${cyan}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🖼️ OPCIÓN DE IMAGEN DOCKER"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${neutro}"

PS3=$'\e[33mSeleccione una opción:\e[0m '
select imagen_opcion in "Usar imagen existente" "Crear nueva imagen"; do
    case $REPLY in
        1)
            echo -e "${azul}🔍 Buscando imágenes en todas las regiones...${neutro}"
            IMAGENES_EXISTENTES=()

            for region in "${REGION_CODES[@]}"; do
                resultados=$(gcloud artifacts docker images list "$region-docker.pkg.dev/$PROJECT_ID/$REPO_NAME" --format="value(package)" 2>/dev/null)
                while read -r imagen; do
                    [[ -n "$imagen" ]] && IMAGENES_EXISTENTES+=("$region|$imagen")
                done <<< "$resultados"
            done

            if [[ ${#IMAGENES_EXISTENTES[@]} -eq 0 ]]; then
                echo -e "${rojo}❌ No se encontraron imágenes en el repositorio '$REPO_NAME'.${neutro}"
                echo -e "${amarillo}🔁 Se procederá a crear una nueva imagen.${neutro}"
                imagen_opcion="Crear nueva imagen"
                break
            fi

            echo -e "${cyan}"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "📂 Seleccione una imagen existente:"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo -e "${neutro}"

            PS3=$'\e[33mSeleccione una imagen:\e[0m '
            select img in "${IMAGENES_EXISTENTES[@]}"; do
                if [[ -n "$img" ]]; then
                    REGION=$(cut -d'|' -f1 <<< "$img")
                    IMAGE_NAME=$(cut -d'/' -f4 <<< "$(cut -d'|' -f2 <<< "$img")")
                    IMAGE_TAG="1.0"
                    IMAGE_PATH="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME"
                    echo -e "${verde}✔ Imagen seleccionada: $IMAGE_NAME (Región: $REGION)${neutro}"
                    break 2
                else
                    echo -e "${rojo}❌ Selección inválida. Intente de nuevo.${neutro}"
                fi
            done
            ;;
        2)
            imagen_opcion="Crear nueva imagen"
            break
            ;;
        *)
            echo -e "${rojo}❌ Opción inválida. Por favor selecciona 1 o 2.${neutro}"
            ;;
    esac
done

#Se omite si se elige usar imagen existente
if [[ "$imagen_opcion" == "Crear nueva imagen" ]]; then
                  
echo -e "${cyan}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🏗️ CONSTRUCCIÓN DE IMAGEN DOCKER"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

while true; do
    echo -e "${azul}📛 Ingresa un nombre para la imagen Docker (Enter para usar 'gcp'):${neutro}"
    read -p "📝 Nombre de la imagen: " input_image
    IMAGE_NAME="${input_image:-gcp}"
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
                  
fi
                  
# 🚀 DESPLIEGUE DEL SERVICIO EN CLOUD RUN
# 🚀 DESPLIEGUE DEL SERVICIO EN CLOUD RUN
echo -e "${cyan}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🌐 DESPLEGANDO SERVICIO EN CLOUD RUN"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${neutro}"

# 🌍 SELECCIÓN DE REGIÓN PARA CLOUD RUN
echo -e "${cyan}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🌍 SELECCIÓN DE REGIÓN PARA DESPLEGAR CLOUD RUN"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${neutro}"

for i in "${!REGIONS[@]}"; do
  printf "%2d) %s\n" $((i+1)) "${REGIONS[$i]}"
done

while true; do
  read -p "Ingrese el número de la región para el servicio: " CLOUD_RUN_INDEX

  if ! [[ "$CLOUD_RUN_INDEX" =~ ^[0-9]+$ ]] || (( CLOUD_RUN_INDEX < 1 || CLOUD_RUN_INDEX > ${#REGION_CODES[@]} )); then
    echo -e "${rojo}❌ Selección inválida. Intente nuevamente.${neutro}"
  else
    CLOUD_RUN_REGION=${REGION_CODES[$((CLOUD_RUN_INDEX-1))]}
    echo -e "${verde}✔ Región seleccionada para Cloud Run: $CLOUD_RUN_REGION${neutro}"
    break
  fi
done

# Solicitar al usuario el nombre del servicio (default: rain)
read -p "📛 Ingresa el nombre que deseas para el servicio en Cloud Run (default: rain): " SERVICE_NAME
SERVICE_NAME=${SERVICE_NAME:-rain}

# 🔐 Solicitar y validar el subdominio personalizado para DHOST
while true; do
    echo -e "${amarillo}"
    read -p "🌐 Ingrese su subdominio personalizado (Cloudflare): " DHOST
    echo -e "${neutro}"

    # Validar que no esté vacío, tenga al menos un punto, y no tenga espacios
    if [[ -z "$DHOST" || "$DHOST" != *.* || "$DHOST" == *" "* ]]; then
        echo -e "${rojo}❌ El subdominio no puede estar vacío, debe contener al menos un punto y no tener espacios.${neutro}"
        continue
    fi

    echo -e "${verde}✅ Se ingresó el subdominio: $DHOST${neutro}"
    echo
    echo -ne "${cyan}¿Desea continuar con este subdominio? (s/n): ${neutro}"
    read -r CONFIRMAR
    CONFIRMAR=${CONFIRMAR,,}

    if [[ "$CONFIRMAR" == "s" ]]; then
        break
    else
        echo -e "${azul}🔁 Vamos a volver a solicitar el subdominio...${neutro}"
    fi
done

# Obtener número de proyecto
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")

# Ejecutar despliegue en la región seleccionada
SERVICE_URL=$(gcloud run deploy "$SERVICE_NAME" \
  --image "$IMAGE_PATH:$IMAGE_TAG" \
  --platform managed \
  --region "$CLOUD_RUN_REGION" \
  --allow-unauthenticated \
  --port 8080 \
  --timeout 3600 \
  --concurrency 100 \
  --set-env-vars="DHOST=${DHOST},DPORT=22" \
  --quiet \
  --format="value(status.url)")

# Verificar éxito del despliegue
if [[ $? -ne 0 ]]; then
    echo -e "${rojo}❌ Error en el despliegue de Cloud Run.${neutro}"
    exit 1
fi

# Dominio regional del servicio
REGIONAL_DOMAIN="https://${SERVICE_NAME}-${PROJECT_NUMBER}.${CLOUD_RUN_REGION}.run.app"

# Mostrar resumen final
echo -e "${verde}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║ 📦 INFORMACIÓN DEL DESPLIEGUE EN CLOUD RUN                  ║"
echo "╠════════════════════════════════════════════════════════════╣"
echo "║ 🗂️ ID del Proyecto GCP  : $PROJECT_ID"
echo "║ 🔢 Número de Proyecto   : $PROJECT_NUMBER"
echo "║ 🗃️ Repositorio Docker   : $REPO_NAME"
echo "║ 📍 Región de Despliegue : $REGION"
echo "║ 🖼️ Nombre de la Imagen  : $IMAGE_NAME:$IMAGE_TAG"
echo "║ 📛 Nombre del Servicio  : $SERVICE_NAME"
echo "║ 📍 Región de Despliegue : $CLOUD_RUN_REGION"
echo "║ 🌐 URL del Servicio     : $SERVICE_URL"
echo "║ 🌐 Dominio Regional     : $REGIONAL_DOMAIN"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${neutro}"
