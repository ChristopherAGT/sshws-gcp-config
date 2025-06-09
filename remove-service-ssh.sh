#!/bin/bash

# ╭────────────────────────────────────────────────────────────╮
# │       GESTOR TOTAL: Cloud Run + Artifact Registry         │
# ╰────────────────────────────────────────────────────────────╯

RED="\e[31m"; GREEN="\e[32m"; CYAN="\e[36m"
YELLOW="\e[33m"; RESET="\e[0m"; BOLD="\e[1m"

REGIONS=("us-central1" "us-east1" "us-west1" "europe-west1" "asia-east1")
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [[ -z "$PROJECT_ID" ]]; then
  echo -e "${RED}❌ No se pudo obtener el ID del proyecto.${RESET}"; exit 1
fi

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 RECOLECTANDO servicios Cloud Run y repositorios Artifact Registry"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

declare -A SRV_IMG
declare -A SRV_REGION

for REGION in "${REGIONS[@]}"; do
  mapfile -t SVC_LIST < <(
    gcloud run services list --platform managed --region "$REGION" --format="value(metadata.name)" 2>/dev/null
  )
  for SVC in "${SVC_LIST[@]}"; do
    IMG=$(gcloud run services describe "$SVC" --platform managed --region "$REGION" \
      --format="value(spec.template.spec.containers[0].image)" 2>/dev/null)
    [[ -z "$IMG" ]] && continue
    SRV_IMG["$IMG"]="$SVC"; SRV_REGION["$IMG"]="$REGION"
  done
done

mapfile -t REPOS < <(gcloud artifacts repositories list --format="value(name)")

declare -a MENU
declare -a ENTRY_TYPE

idx=1
for FULL_REPO in "${REPOS[@]}"; do
  REPO_REGION=$(echo "$FULL_REPO" | cut -d/ -f4)
  REPO_NAME=$(echo "$FULL_REPO" | cut -d/ -f6)
  
  IMG_LIST=$(gcloud artifacts docker images list "${REPO_REGION}-docker.pkg.dev/$PROJECT_ID/$REPO_NAME" --format="value(name)")
  if [[ -z "$IMG_LIST" ]]; then
    MENU+=("$FULL_REPO|||$REPO_REGION")
    ENTRY_TYPE+=("repo_only")
    echo -e "${YELLOW}$idx)${RESET} ${BOLD}Repo limpio:${RESET} ${CYAN}$REPO_NAME${RESET} (${REPO_REGION})"
  else
    mapfile -t IMG_LIST <<<"$IMG_LIST"
    for IMG in "${IMG_LIST[@]}"; do
      TAG_DIGEST=$(gcloud artifacts docker images describe "${REPO_REGION}-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMG" \
        --format='value(image_summary.digest)')
      FULL_IMG="${REPO_REGION}-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMG@$TAG_DIGEST"
      
      if [[ -n "${SRV_IMG[$FULL_IMG]}" ]]; then
        SVC=${SRV_IMG[$FULL_IMG]}
        SREG=${SRV_REGION[$FULL_IMG]}
        MENU+=("$FULL_REPO|$FULL_IMG|$SVC|$SREG")
        ENTRY_TYPE+=("both")
        echo -e "${YELLOW}$idx)${RESET} ${BOLD}Servicio:${RESET} $SVC (${SREG})"
        echo -e "    📦 Imagen:&nbsp;${GREEN}$IMG@$TAG_DIGEST${RESET}"
        echo -e "    🗂️  Repo:&nbsp;${CYAN}$REPO_NAME${RESET} (${REPO_REGION})"
      else
        MENU+=("$FULL_REPO|$FULL_IMG||")
        ENTRY_TYPE+=("img_only")
        echo -e "${YELLOW}$idx)${RESET} ${BOLD}Imagen sin servicio:${RESET} ${GREEN}$IMG@$TAG_DIGEST${RESET}"
        echo -e "    🗂️  Repo:&nbsp;${CYAN}$REPO_NAME${RESET} (${REPO_REGION})"
      fi
      idx=$((idx+1))
    done
  fi
  idx=$((idx))
done

echo -e "\n${BOLD}0) Cancelar y salir${RESET}"
echo -ne "${BOLD}Seleccione un ítem para gestionar: ${RESET}"
read -r SELECTION

(( SELECTION < 1 || SELECTION > ${#MENU[@]} )) && {
  echo -e "${YELLOW}Saliendo...${RESET}"; exit 0
}

IFS='|' read -r REPO_FULL IMG_FULL SVC_FULL SVC_REGION <<< "${MENU[$((SELECTION-1))]}"

echo -e "\n🛠️ ${BOLD}Gestión del ítem seleccionado:${RESET}"
[[ -n "$SVC_FULL" ]] && echo -e "   🔹 Servicio: ${BOLD}$SVC_FULL${RESET} (${SVC_REGION})"
[[ -n "$IMG_FULL" ]] && echo -e "   📦 Imagen: ${GREEN}${IMG_FULL}${RESET}"
REPO_NAME=$(echo "$REPO_FULL" | cut -d/ -f6)
REPO_REGION=$(echo "$REPO_FULL" | cut -d/ -f4)
echo -e "   🗂️  Repo: ${CYAN}$REPO_NAME${RESET} (${REPO_REGION})"

[ -n "$SVC_FULL" ] && read -rp $'\n❓ Eliminar servicio Cloud Run? (s/n): ' DEL_SVC
[ -n "$IMG_FULL" ] && read -rp '❓ Eliminar imagen? (s/n): ' DEL_IMG
read -rp '❓ Eliminar repositorio? (s/n): ' DEL_REPO

[[ "$DEL_SVC" =~ ^[sS]$ ]] && gcloud run services delete "$SVC_FULL" --platform managed --region "$SVC_REGION" --quiet
if [[ "$DEL_IMG" =~ ^[sS]$ && -n "$IMG_FULL" ]]; then
  IMG_PATH="${IMG_FULL%@*}"
  DIGEST="${IMG_FULL#*@}"
  TAGS=$(gcloud artifacts docker tags list "$IMG_PATH" --format="get(tag)" --filter="version=\"$DIGEST\"")
  for T in $TAGS; do
    gcloud artifacts docker tags delete "$IMG_PATH:$T" --quiet
  done
  gcloud artifacts docker images delete "$IMG_FULL" --quiet
fi
[[ "$DEL_REPO" =~ ^[sS]$ ]] && gcloud artifacts repositories delete "$REPO_NAME" --location="$REPO_REGION" --quiet

echo -e "\n${GREEN}✅ Operación completada.${RESET}"
