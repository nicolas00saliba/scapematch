#!/usr/bin/env python3
"""Serve um build web do Flutter. Rotas sem arquivo caem no index.html."""

import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


def arquivo_no_raiz(raiz: Path, url_path: str) -> Path | None:
    puro = url_path.split('?', 1)[0].split('#', 1)[0]
    if puro == '' or puro.startswith('//') or '\\' in puro:
        return None
    candidato = (raiz / puro.lstrip('/')).resolve()
    if not candidato.is_relative_to(raiz):
        return None
    return candidato


def main() -> None:
    porta = int(sys.argv[1])
    raiz = Path(sys.argv[2]).resolve()

    class Pedido(SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=str(raiz), **kwargs)

        def do_GET(self) -> None:
            bruto, _, consulta = self.path.partition('?')
            arquivo = arquivo_no_raiz(raiz, bruto)
            if arquivo is None:
                self.send_error(400)
                return
            if bruto != '/' and '.' not in arquivo.name and not arquivo.is_file():
                self.path = '/index.html'
            elif arquivo == raiz:
                self.path = '/' + (f'?{consulta}' if consulta else '')
            else:
                relativo = arquivo.relative_to(raiz).as_posix()
                self.path = f'/{relativo}' + (f'?{consulta}' if consulta else '')
            super().do_GET()

        def log_message(self, formato: str, *args) -> None:
            return

    ThreadingHTTPServer(('127.0.0.1', porta), Pedido).serve_forever()


if __name__ == '__main__':
    main()
