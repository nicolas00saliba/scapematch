#!/usr/bin/env bash
# Instalação idempotente do RTK e do Serena para cloud agents.
# Roda no "install" de .cursor/environment.json e pode ser chamada à mão.
# Não grava chaves. Falha aqui não derruba o ambiente (sempre sai 0).
set -u
export PATH="${HOME}/.local/bin:${PATH}"

log() { printf '%s\n' "$1"; }

ensure_path_file() {
  local file="$1"
  touch "$file"
  if ! grep -qs 'HOME/.local/bin' "$file"; then
    printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$file"
  fi
}

# Login e bash interativo. Processo não interativo não lê estes arquivos;
# por isso os binários também vão para /usr/local/bin (PATH padrão).
ensure_path_file "${HOME}/.bashrc"
ensure_path_file "${HOME}/.profile"
mkdir -p "${HOME}/.local/bin"

publish() {
  local name="$1"
  local src="${HOME}/.local/bin/${name}"
  if [ ! -x "$src" ]; then
    log "[aviso] ${name} não está em ${src}"
    return 0
  fi
  if ! sudo -n true 2>/dev/null; then
    log "[aviso] sem sudo; ${name} fica só em ${src} (o hook e o launcher do Serena procuram lá)"
    return 0
  fi
  sudo ln -sfn "$src" "/usr/local/bin/${name}" || log "[aviso] não foi possível publicar ${name}"
}

# RTK (https://github.com/rtk-ai/rtk) — binário em ~/.local/bin
if ! command -v rtk >/dev/null 2>&1 || ! rtk hook cursor --help >/dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh \
    || log "[aviso] falha ao instalar rtk"
fi

# uv / uvx (pré-requisito do Serena)
if ! command -v uv >/dev/null 2>&1 || ! command -v uvx >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | sh || log "[aviso] falha ao instalar uv"
fi

# Serena (https://github.com/oraios/serena). Pacote oficial: serena-agent.
if ! command -v serena >/dev/null 2>&1 && command -v uv >/dev/null 2>&1; then
  uv tool install -p 3.13 serena-agent || log "[aviso] falha ao instalar serena"
fi
if command -v serena >/dev/null 2>&1 && [ ! -f "${HOME}/.serena/serena_config.yml" ]; then
  serena init </dev/null || log "[aviso] falha no serena init"
fi

publish rtk
publish serena
publish uv
publish uvx

# Confere o PATH de um processo não interativo (sem bashrc).
ni_path='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
if env -i HOME="${HOME}" PATH="${ni_path}" bash --noprofile --norc -c 'command -v rtk >/dev/null && command -v serena >/dev/null'; then
  log "[ok] rtk e serena visíveis sem bashrc"
else
  log "[aviso] rtk ou serena ausentes no PATH não interativo"
fi

command -v rtk >/dev/null 2>&1 && rtk --version || true
command -v serena >/dev/null 2>&1 && serena --version || true
exit 0
