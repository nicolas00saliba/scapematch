#!/usr/bin/env python3
"""Gera o catálogo de municípios brasileiros a partir da API oficial do IBGE.

Nomes, UF e código vêm de:
  https://servicodados.ibge.gov.br/api/v1/localidades/municipios

As coordenadas das sedes (latitude/longitude), necessárias para a coluna
NOT NULL de public.cities, vêm do conjunto público que usa os mesmos
códigos IBGE (kelvins/municipios-brasileiros).

Os cinco ids já gravados no banco (curitiba, sao-paulo, rio-de-janeiro,
belo-horizonte e porto-alegre) são preservados. Os demais usam
'{slug}-{uf}'.

Uso (na raiz do repositório):

  python3 tool/generate_municipios_ibge.py

Saídas:

  tool/data/municipios_ibge_v1.json
  apps/parceiro/lib/features/partner/domain/municipios_ibge_v1.g.dart
  supabase/migrations/20261126223756_brazilian_municipalities.sql
"""

from __future__ import annotations

import json
import re
import sys
import unicodedata
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IBGE_URL = "https://servicodados.ibge.gov.br/api/v1/localidades/municipios"
COORDS_URL = (
    "https://raw.githubusercontent.com/kelvins/municipios-brasileiros/"
    "main/json/municipios.json"
)
ASSET_PATH = ROOT / "tool/data/municipios_ibge_v1.json"
DART_PATH = ROOT / "apps/parceiro/lib/features/partner/domain/municipios_ibge_v1.g.dart"
SQL_PATH = ROOT / "supabase/migrations/20261126223756_brazilian_municipalities.sql"

# Ids já usados em venues, grupos, convites e no seletor do app.
LEGACY_IDS = {
    4106902: "curitiba",
    3550308: "sao-paulo",
    3304557: "rio-de-janeiro",
    3106200: "belo-horizonte",
    4314902: "porto-alegre",
}

FROM_ACCENT = str.maketrans(
    "áàâãäåéèêëíìîïóòôõöúùûüçñýÁÀÂÃÄÅÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑÝ",
    "aaaaaaeeeeiiiiooooouuuucnyAAAAAAEEEEIIIIOOOOOUUUUCNY",
)


def fold(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value)
    stripped = "".join(ch for ch in normalized if not unicodedata.combining(ch))
    return stripped.translate(FROM_ACCENT).lower()


def slugify(name: str) -> str:
    folded = fold(name)
    slug = re.sub(r"[^a-z0-9]+", "-", folded).strip("-")
    if not slug:
        raise SystemExit(f"slug vazio para {name!r}")
    return slug


def state_of(entry: dict) -> tuple[str, str]:
    micro = entry.get("microrregiao") or {}
    meso = micro.get("mesorregiao") or {}
    uf = meso.get("UF")
    if not uf:
        imediata = entry.get("regiao-imediata") or {}
        inter = imediata.get("regiao-intermediaria") or {}
        uf = inter.get("UF")
    if not uf or not uf.get("sigla") or not uf.get("nome"):
        raise SystemExit(f"UF ausente no município {entry.get('id')} {entry.get('nome')}")
    return uf["sigla"], uf["nome"]


def sql_escape(value: str) -> str:
    return value.replace("'", "''")


def dart_escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace("'", "\\'")


def fetch_json(url: str, *, encoding: str = "utf-8") -> object:
    request = urllib.request.Request(url, headers={"User-Agent": "EscapeMatch/municipios"})
    with urllib.request.urlopen(request, timeout=60) as response:
        raw = response.read()
    text = raw.decode(encoding)
    if text.startswith("\ufeff"):
        text = text.lstrip("\ufeff")
    return json.loads(text)


def load_source() -> tuple[list[dict], dict[int, tuple[float, float]]]:
    ibge_path = Path("/tmp/ibge_municipios.json")
    coords_path = Path("/tmp/kelvins_municipios.json")
    if ibge_path.exists():
        ibge = json.loads(ibge_path.read_text(encoding="utf-8"))
    else:
        ibge = fetch_json(IBGE_URL)
    if coords_path.exists():
        coords_raw = json.loads(coords_path.read_text(encoding="utf-8-sig"))
    else:
        coords_raw = fetch_json(COORDS_URL, encoding="utf-8-sig")
    coords: dict[int, tuple[float, float]] = {}
    for row in coords_raw:
        code = int(row["codigo_ibge"])
        coords[code] = (float(row["latitude"]), float(row["longitude"]))
    return ibge, coords


def build() -> list[dict]:
    ibge, coords = load_source()
    items: list[dict] = []
    seen_ids: set[str] = set()
    seen_ibge: set[int] = set()
    for entry in ibge:
        ibge_code = int(entry["id"])
        name = entry["nome"]
        state_code, state_name = state_of(entry)
        if ibge_code in seen_ibge:
            raise SystemExit(f"código IBGE repetido: {ibge_code}")
        seen_ibge.add(ibge_code)
        city_id = LEGACY_IDS.get(ibge_code, f"{slugify(name)}-{state_code.lower()}")
        if city_id in seen_ids:
            raise SystemExit(f"id repetido: {city_id} ({name}/{state_code})")
        seen_ids.add(city_id)
        if ibge_code not in coords:
            raise SystemExit(f"sem coordenada para {ibge_code} {name}/{state_code}")
        lat, lng = coords[ibge_code]
        items.append(
            {
                "ibge": ibge_code,
                "id": city_id,
                "name": name,
                "state_code": state_code,
                "state_name": state_name,
                "lat": lat,
                "lng": lng,
            }
        )
    items.sort(key=lambda item: (item["state_code"], fold(item["name"]), item["ibge"]))
    return items


def write_asset(items: list[dict], generated_at: str) -> None:
    payload = {
        "version": 1,
        "source": {
            "names": IBGE_URL,
            "coordinates": COORDS_URL,
        },
        "generated_at": generated_at,
        "count": len(items),
        "legacy_ids": {str(k): v for k, v in LEGACY_IDS.items()},
        "municipalities": items,
    }
    ASSET_PATH.parent.mkdir(parents=True, exist_ok=True)
    ASSET_PATH.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def write_dart(items: list[dict], generated_at: str) -> None:
    lines = [
        "// GENERATED FILE. Não edite à mão.",
        f"// Gerado em {generated_at} por tool/generate_municipios_ibge.py",
        "// ignore_for_file: lines_longer_than_80_chars",
        "",
        "part of 'brazilian_municipalities.dart';",
        "",
        f"const municipiosIbgeGeneratedAt = '{generated_at}';",
        f"const municipiosIbgeCount = {len(items)};",
        "",
        "const municipiosIbgeV1 = <BrazilianMunicipality>[",
    ]
    for item in items:
        lines.append(
            "  BrazilianMunicipality("
            f"{item['ibge']}, "
            f"'{dart_escape(item['id'])}', "
            f"'{dart_escape(item['name'])}', "
            f"'{dart_escape(item['state_code'])}', "
            f"'{dart_escape(item['state_name'])}'"
            "),"
        )
    lines.append("];")
    lines.append("")
    DART_PATH.write_text("\n".join(lines), encoding="utf-8")


def write_sql(items: list[dict], generated_at: str) -> None:
    chunks: list[str] = []
    header = f"""-- Municípios brasileiros do IBGE ({len(items)} registros).
-- Gerado em {generated_at} por tool/generate_municipios_ibge.py
--
-- Não destrutivo: não apaga cidades, não troca os ids já usados
-- (curitiba, sao-paulo, rio-de-janeiro, belo-horizonte, porto-alegre)
-- e só preenche ibge_code / insere os municípios que ainda não existem.
-- Não aplicar em produção neste PR: espera o ok do Nícolas.

alter table public.cities
  add column if not exists ibge_code text;

alter table public.cities
  drop constraint if exists cities_ibge_code_format;

alter table public.cities
  add constraint cities_ibge_code_format
  check (ibge_code is null or ibge_code ~ '^[0-9]{{7}}$');

comment on column public.cities.ibge_code is
  'Código de 7 dígitos do município no IBGE.';

create unique index if not exists cities_ibge_code_key
  on public.cities (ibge_code)
  where ibge_code is not null;
"""
    chunks.append(header)

    updates = [
        "update public.cities",
        "set ibge_code = case id",
    ]
    for ibge_code, city_id in LEGACY_IDS.items():
        updates.append(f"  when '{city_id}' then '{ibge_code}'")
    updates.append("  else ibge_code")
    updates.append("end")
    updates.append("where id in (")
    updates.append("  " + ", ".join(f"'{city_id}'" for city_id in LEGACY_IDS.values()))
    updates.append(")")
    updates.append("  and ibge_code is null;")
    chunks.append("\n".join(updates) + "\n")

    batch_size = 400
    for start in range(0, len(items), batch_size):
        batch = items[start : start + batch_size]
        rows = []
        for item in batch:
            rows.append(
                "  ("
                f"'{sql_escape(item['id'])}', "
                f"'{sql_escape(item['name'])}', "
                f"'{sql_escape(item['state_code'])}', "
                f"'{sql_escape(item['state_name'])}', "
                f"{item['lat']}, "
                f"{item['lng']}, "
                f"'{item['ibge']}'"
                ")"
            )
        statement = (
            "insert into public.cities "
            "(id, name, state_code, state_name, latitude, longitude, ibge_code)\n"
            "values\n"
            + ",\n".join(rows)
            + "\non conflict (id) do nothing;\n"
        )
        chunks.append(statement)

    SQL_PATH.write_text("\n".join(chunks) + "\n", encoding="utf-8")


def main() -> int:
    from datetime import datetime, timezone

    generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    items = build()
    if len(items) < 5500:
        raise SystemExit(f"contagem inesperada: {len(items)}")
    for ibge_code, city_id in LEGACY_IDS.items():
        match = next((item for item in items if item["ibge"] == ibge_code), None)
        if match is None or match["id"] != city_id:
            raise SystemExit(f"id legado perdido: {city_id}")
    write_asset(items, generated_at)
    write_dart(items, generated_at)
    write_sql(items, generated_at)
    print(
        f"{len(items)} municípios -> {ASSET_PATH.relative_to(ROOT)}, "
        f"{DART_PATH.relative_to(ROOT)}, {SQL_PATH.relative_to(ROOT)}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
