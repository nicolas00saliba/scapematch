#!/bin/bash
# Gera um APK por conta fantasma (contas.json). Não fala com o Supabase.
# A keystore de teste e a senha dela ficam fora do repo, em
# ${APPS_FANTASMA_SECRETS:-$HOME/.secrets}, com chmod 600.
# Mesma keystore em todo build = o celular aceita atualizar por cima.
set -euo pipefail

aqui="$(cd "$(dirname "$0")" && pwd)"
segredos="${APPS_FANTASMA_SECRETS:-$HOME/.secrets}"
saida="${1:-$aqui/apks}"
keystore="$segredos/apps-fantasma.keystore"
senha_arq="$segredos/apps-fantasma.keystore.pass"

mkdir -p "$segredos" && chmod 700 "$segredos"
if [[ ! -f "$keystore" ]]; then
  umask 077
  openssl rand -base64 24 | tr -d '/+=' > "$senha_arq"
  keytool -genkeypair -noprompt -keystore "$keystore" -storetype PKCS12 \
    -alias apps-fantasma -keyalg RSA -keysize 2048 -validity 3650 \
    -dname "CN=EscapeMatch Teste, O=EscapeMatch, C=BR" \
    -storepass "$(cat "$senha_arq")" -keypass "$(cat "$senha_arq")" >/dev/null
  chmod 600 "$keystore" "$senha_arq"
fi

python3 "$aqui/gerar_icones.py"

export APPS_FANTASMA_KEYSTORE="$keystore"
export APPS_FANTASMA_STORE_PASSWORD="$(cat "$senha_arq")"
export APPS_FANTASMA_VERSION_CODE="${APPS_FANTASMA_VERSION_CODE:-$(date +%y%m%d%H)}"

gradle_bin="${GRADLE:-gradle}"
(cd "$aqui/android" && "$gradle_bin" --no-daemon -q assembleRelease)

mkdir -p "$saida"
python3 - "$aqui" "$saida" <<'PY'
import json, shutil, sys
from pathlib import Path
aqui, saida = Path(sys.argv[1]), Path(sys.argv[2])
for c in json.loads((aqui / "contas.json").read_text())["contas"]:
    nome = ("EM-Jogador-" if c["tipo"] == "jogador" else "EM-Casa-") + str(c["numero"])
    origem = aqui / f"android/app/build/outputs/apk/{c['slug']}/release/app-{c['slug']}-release.apk"
    shutil.copy(origem, saida / f"{nome}.apk")
    print(saida / f"{nome}.apk")
PY
