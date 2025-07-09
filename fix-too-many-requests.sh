#!/bin/bash

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 🔁 SCRIPT COMPLETO DE REINICIO DE SERVICIOS CLOUD RUN
#    Incluye: detección de proyecto, APIs necesarias y redeploy automático
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Colores
GREEN="\e[32m"
RED="\e[31m"
CYAN="\e[36m"
YELLOW="\e[33m"
NC="\e[0m"

# Spinner para comandos largos
spinner() {
    local pid=$!
    local delay=0.1
    local spinstr='|/-\'
    while [ -d /proc/$pid ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# APIs necesarias para Cloud Run
REQUIRED_APIS=(
    run.googleapis.com
    artifactregistry.googleapis.com
    cloudbuild.googleapis.com
)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo -e "${CYAN}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 DETECTANDO PROYECTO ACTIVO DE GOOGLE CLOUD"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${NC}"

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

if [[ -z "$PROJECT_ID" ]]; then
    echo -e "${RED}❌ No se detectó un proyecto activo. Usa:${NC}"
    echo -e "${YELLOW}   gcloud config set project [ID_PROYECTO]${NC}"
    exit 1
else
    echo -e "${GREEN}✔ Proyecto activo: ${PROJECT_ID}${NC}"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo -e "${CYAN}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔐 VERIFICANDO Y HABILITANDO APIS NECESARIAS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${NC}"

for API in "${REQUIRED_APIS[@]}"; do
    echo -ne "${YELLOW}🔎 Verificando API: ${API}...${NC}"

    if gcloud services list --enabled --project="$PROJECT_ID" --format="value(config.name)" | grep -q "$API"; then
        echo -e " ${GREEN}Habilitada${NC}"
    else
        echo -e " ${RED}Deshabilitada ➡ Habilitando...${NC}"
        (gcloud services enable "$API" --project="$PROJECT_ID" --quiet) & spinner
        if [[ $? -eq 0 ]]; then
            echo -e "${GREEN}✔ API habilitada exitosamente: $API${NC}"
        else
            echo -e "${RED}❌ Error al habilitar la API: $API${NC}"
            exit 1
        fi
    fi
done

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo -e "${CYAN}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 OBTENIENDO SERVICIOS ACTIVOS DE CLOUD RUN"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${NC}"

SERVICIOS=$(gcloud run services list --platform=managed --format="value(metadata.name)" 2>/dev/null)

if [[ -z "$SERVICIOS" ]]; then
    echo -e "${RED}❌ No se encontraron servicios activos en Cloud Run.${NC}"
    exit 1
fi

echo -e "${YELLOW}🧩 Servicios detectados:${NC}"
echo "$SERVICIOS" | nl -w2 -s'. '

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo -e "${CYAN}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔁 REINICIANDO SERVICIOS (REDEPLOY)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${NC}"

for SERVICIO in $SERVICIOS; do
    REGION=$(gcloud run services describe "$SERVICIO" --platform=managed --format="value(metadata.annotations.run.googleapis.com/region)")
    IMAGE=$(gcloud run services describe "$SERVICIO" --platform=managed --region="$REGION" --format="value(spec.template.spec.containers[0].image)")

    if [[ -z "$REGION" || -z "$IMAGE" ]]; then
        echo -e "${RED}❌ No se pudo obtener información para '${SERVICIO}'. Saltando...${NC}"
        continue
    fi

    echo -e "${CYAN}🔄 Reiniciando '${SERVICIO}' en ${REGION} con imagen actual...${NC}"
    (
        gcloud run deploy "$SERVICIO" \
            --image="$IMAGE" \
            --region="$REGION" \
            --platform=managed \
            --quiet >/dev/null 2>&1
    ) & spinner

    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✔ Servicio '${SERVICIO}' reiniciado correctamente.${NC}"
    else
        echo -e "${RED}❌ Error al reiniciar el servicio '${SERVICIO}'.${NC}"
    fi
done

echo -e "${CYAN}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ TODOS LOS SERVICIOS HAN SIDO PROCESADOS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${NC}"
