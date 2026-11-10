#!/usr/bin/env bash
# Aplica os e-mails do Auth no projeto remoto eujlhicairvksvmssruz.
#
# Não guarda token e não deve rodar no CI. Quem aplica é uma pessoa:
#
#   export SUPABASE_ACCESS_TOKEN="..."
#   # token em https://supabase.com/dashboard/account/tokens
#   tool/apply_auth_email_templates.sh
#
# --dry-run monta o JSON (assuntos e tamanho de cada HTML) e não chama a rede.
#
# Alternativa, sem API: no painel do projeto, Authentication > Email Templates.
# Para cada tipo, cole o assunto de supabase/config.toml e o HTML do arquivo:
#   Confirm signup    supabase/templates/confirmation.html
#   Reset password    supabase/templates/recovery.html
#   Magic Link        supabase/templates/magic_link.html
#   Change Email      supabase/templates/email_change.html
#   Invite user       supabase/templates/invite.html
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
dry=0
if [ "${1:-}" = "--dry-run" ]; then
  dry=1
elif [ "$#" -gt 0 ]; then
  echo "uso: $0 [--dry-run]" >&2
  exit 2
fi

if [ "$dry" -eq 0 ] && [ -z "${SUPABASE_ACCESS_TOKEN:-}" ]; then
  echo "Defina SUPABASE_ACCESS_TOKEN (https://supabase.com/dashboard/account/tokens)." >&2
  echo "Para só conferir o JSON: $0 --dry-run" >&2
  exit 2
fi

python3 - "$root" "$dry" <<'PY'
import json, os, pathlib, re, sys, urllib.error, urllib.request

root = pathlib.Path(sys.argv[1])
dry = sys.argv[2] == "1"
project = "eujlhicairvksvmssruz"
fields = {
    "confirmation": (
        "mailer_subjects_confirmation",
        "mailer_templates_confirmation_content",
    ),
    "recovery": (
        "mailer_subjects_recovery",
        "mailer_templates_recovery_content",
    ),
    "magic_link": (
        "mailer_subjects_magic_link",
        "mailer_templates_magic_link_content",
    ),
    "email_change": (
        "mailer_subjects_email_change",
        "mailer_templates_email_change_content",
    ),
    "invite": (
        "mailer_subjects_invite",
        "mailer_templates_invite_content",
    ),
}
needed = {
    "confirmation": ("{{ .ConfirmationURL }}", "{{ .Email }}", "{{ .SiteURL }}"),
    "recovery": ("{{ .ConfirmationURL }}", "{{ .Email }}", "{{ .SiteURL }}"),
    "magic_link": ("{{ .ConfirmationURL }}", "{{ .Email }}", "{{ .SiteURL }}"),
    "email_change": (
        "{{ .ConfirmationURL }}",
        "{{ .Email }}",
        "{{ .NewEmail }}",
        "{{ .SiteURL }}",
    ),
    "invite": ("{{ .ConfirmationURL }}", "{{ .Email }}", "{{ .SiteURL }}"),
}

text = (root / "supabase" / "config.toml").read_text(encoding="utf-8")
current = None
found = {}
for raw in text.splitlines():
    line = raw.strip()
    section = re.fullmatch(r"\[auth\.email\.template\.([a-z_]+)\]", line)
    if section:
        current = section.group(1)
        found.setdefault(current, {})
        continue
    if line.startswith("[") and current is not None:
        current = None
        continue
    if current is None or "=" not in line or line.startswith("#"):
        continue
    key, value = (part.strip() for part in line.split("=", 1))
    if key in ("subject", "content_path"):
        found[current][key] = value.strip().strip('"')

payload = {}
for name, (subject_key, content_key) in fields.items():
    block = found.get(name) or {}
    subject = block.get("subject")
    content_path = block.get("content_path")
    if not subject or not content_path:
        raise SystemExit(f"faltam subject ou content_path em {name}")
    path = pathlib.Path(content_path)
    if not path.is_absolute():
        path = root / content_path.removeprefix("./")
    html = path.read_text(encoding="utf-8")
    for token in needed[name]:
        if token not in html:
            raise SystemExit(f"{path.name} não tem {token}")
    lowered = html.lower()
    if "<script" in lowered or "javascript:" in lowered:
        raise SystemExit(f"{path.name} não pode ter script")
    if "<img" in lowered or "https://" in lowered or "http://" in lowered:
        raise SystemExit(f"{path.name} não pode carregar recurso remoto")
    if "app.escapematch.com.br" not in html:
        raise SystemExit(f"{path.name} não diz o destino do link")
    payload[subject_key] = subject
    payload[content_key] = html

if dry:
    for key, value in payload.items():
        if key.endswith("_content"):
            print(f"{key} {len(value)} bytes")
        else:
            print(f"{key}={value}")
    raise SystemExit(0)

body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
request = urllib.request.Request(
    f"https://api.supabase.com/v1/projects/{project}/config/auth",
    data=body,
    method="PATCH",
    headers={
        "Authorization": f"Bearer {os.environ['SUPABASE_ACCESS_TOKEN']}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    },
)
try:
    with urllib.request.urlopen(request, timeout=60) as response:
        print(f"Auth atualizado ({response.status}).")
except urllib.error.HTTPError as error:
    raw = error.read().decode("utf-8", "replace")
    message = ""
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        parsed = None
    if isinstance(parsed, dict):
        field = parsed.get("message")
        if isinstance(field, str):
            message = field.strip()
    print(f"A API respondeu {error.code}.", file=sys.stderr)
    if message:
        print(message, file=sys.stderr)
    raise SystemExit(1)
PY
