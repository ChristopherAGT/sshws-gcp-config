#!/bin/bash

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 🔁 SCRIPT COMPLETO PARA REINICIAR SERVICIOS CLOUD RUN
# Incluye: APIs, selección de proyecto, verificación de estado Ready
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Colores
GREEN="\e[32m"
RED="\e[31m"
CYAN="\e[36m"
YELLOW="\e[33m"
NC="\e[0m"

# Spinner
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

# APIs necesarias
REQUIRED_APIS=(
    run.googleapis.com
    artifactregistry.googleapis.com
    cloudbuild.googleapis.com
)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo -e "${CYAN}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔐 VERIFICANDO AUTENTICACIÓN EN GOOGLE CLOUD"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${NC}"

ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")

if [[ -z "$ACCOUNT" ]]; then
    echo -e "${RED}❌ No hay cuentas autenticadas. Usa:${NC}"
    echo -e "${YELLOW}   gcloud auth login${NC}"
    exit 1
else
    echo -e "${GREEN}✔ Cuenta activa: $ACCOUNT${NC}"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo -e "${CYAN}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📌 SELECCIÓN DEL PROYECTO ACTIVO"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${NC}"

CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null)
echo -e "${YELLOW}📍 Proyecto actual: ${NC}${CURRENT_PROJECT}"

read -p "¿Quieres cambiar el proyecto? (s/N): " CAMBIO
if [[ "$CAMBIO" == "s" || "$CAMBIO" == "S" ]]; then
    echo -e "${CYAN}📋 Lista de proyectos disponibles:${NC}"
    gcloud projects list --format="value(projectId)"
    read -p "Introduce el ID del nuevo proyecto: " NUEVO_PROYECTO
    gcloud config set project "$NUEVO_PROYECTO"
    CURRENT_PROJECT="$NUEVO_PROYECTO"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo -e "${CYAN}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 VERIFICANDO Y HABILITANDO APIS NECESARIAS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${NC}"

for API in "${REQUIRED_APIS[@]}"; do
    echo -ne "${YELLOW}🔎 Verificando API: ${API}...${NC}"
    if gcloud services list --enabled --project="$CURRENT_PROJECT" --format="value(config.name)" | grep -q "$API"; then
        echo -e " ${GREEN}Habilitada${NC}"
    else
        echo -e " ${RED}Deshabilitada ➡ Habilitando...${NC}"
        (gcloud services enable "$API" --project="$CURRENT_PROJECT" --quiet) & spinner
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

SERVICIOS=$(gcloud run services list --platform=managed --format="value(metadata.name)" --project="$CURRENT_PROJECT")

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
    REGION=$(gcloud run services describe "$SERVICIO" --platform=managed --project="$CURRENT_PROJECT" --format="value(metadata.annotations.run.googleapis.com/region)")
    IMAGE=$(gcloud run services describe "$SERVICIO" --platform=managed --region="$REGION" --project="$CURRENT_PROJECT" --format="value(spec.template.spec.containers[0].image)")

    if [[ -z "$REGION" || -z "$IMAGE" ]]; then
        echo -e "${RED}❌ No se pudo obtener información para '${SERVICIO}'. Saltando...${NC}"
        continue
    fi

    echo -e "${CYAN}🔄 Reiniciando '${SERVICIO}' en ${REGION}...${NC}"
    (
        gcloud run deploy "$SERVICIO" \
            --image="$IMAGE" \
            --region="$REGION" \
            --platform=managed \
            --project="$CURRENT_PROJECT" \
            --quiet >/dev/null 2>&1
    ) & spinner

    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✔ Redeploy completado para '${SERVICIO}'${NC}"

        # ✅ Verificación del estado Ready
        STATUS=$(gcloud run services describe "$SERVICIO" --region="$REGION" --platform=managed --project="$CURRENT_PROJECT" \
            --format="value(status.conditions[?type='Ready'].status)")
        if [[ "$STATUS" == "True" ]]; then
            echo -e "${GREEN}   ✔ Servicio está funcionando correctamente (Ready).${NC}"
        else
            echo -e "${RED}   ⚠ Servicio no está en estado Ready después del redeploy.${NC}"
        fi
    else
        echo -e "${RED}❌ Error al reiniciar el servicio '${SERVICIO}'.${NC}"
    fi
done

echo -e "${CYAN}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ TODOS LOS SERVICIOS HAN SIDO PROCESADOS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${NC}"
