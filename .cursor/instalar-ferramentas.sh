#!/usr/bin/env bash
# Instalação idempotente das ferramentas de economia de tokens.
# Usado pelo "install" de .cursor/environment.json (Cloud Agent) e pode ser rodado à mão.
# Não grava chaves nem senhas. Falhas aqui não devem derrubar o ambiente.
set -u
export PATH="$HOME/.local/bin:$PATH"

# Garante ~/.local/bin no PATH de shells futuros
if ! grep -qs 'HOME/.local/bin' "$HOME/.bashrc"; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi

# RTK (https://github.com/rtk-ai/rtk) — instala em ~/.local/bin
if ! command -v rtk >/dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh \
    || echo "[aviso] falha ao instalar rtk"
fi
# Deixa o rtk visível para o shell do agente mesmo sem ~/.local/bin no PATH
if [ -x "$HOME/.local/bin/rtk" ] && [ ! -e /usr/local/bin/rtk ] && sudo -n true 2>/dev/null; then
  sudo ln -sf "$HOME/.local/bin/rtk" /usr/local/bin/rtk
fi

# uv (pré-requisito do Serena)
if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | sh || echo "[aviso] falha ao instalar uv"
fi

# Serena (https://github.com/oraios/serena)
if ! command -v serena >/dev/null 2>&1 && command -v uv >/dev/null 2>&1; then
  uv tool install -p 3.13 serena-agent || echo "[aviso] falha ao instalar serena"
fi
if [ -x "$HOME/.local/bin/serena" ] && [ ! -e /usr/local/bin/serena ] && sudo -n true 2>/dev/null; then
  sudo ln -sf "$HOME/.local/bin/serena" /usr/local/bin/serena
fi
if command -v serena >/dev/null 2>&1 && [ ! -f "$HOME/.serena/serena_config.yml" ]; then
  serena init </dev/null || echo "[aviso] falha no serena init"
fi

command -v rtk >/dev/null 2>&1 && rtk --version
command -v serena >/dev/null 2>&1 && serena --version
exit 0
