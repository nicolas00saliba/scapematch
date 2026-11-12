#!/usr/bin/env python3
"""Serve um build web do Flutter. Rotas sem arquivo caem no index.html."""

import os
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer


def arquivo_no_raiz(raiz: str, url_path: str) -> tuple[str, bool] | None:
    puro = url_path.split('?', 1)[0].split('#', 1)[0]
    if puro == '' or puro.startswith('//') or '\\' in puro:
        return None
    candidato = os.path.realpath(os.path.join(raiz, puro.lstrip('/')))
    prefixo = raiz + os.sep
    if candidato.startswith(prefixo):
        relativo = os.path.relpath(candidato, raiz).replace(os.sep, '/')
        return relativo, os.path.isfile(candidato)
    if candidato == raiz:
        return '', True
    return None


def main() -> None:
    porta = int(sys.argv[1])
    raiz = os.path.realpath(sys.argv[2])

    class Pedido(SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=raiz, **kwargs)

        def do_GET(self) -> None:
            bruto, _, consulta = self.path.partition('?')
            achado = arquivo_no_raiz(raiz, bruto)
            if achado is None:
                self.send_error(400)
                return
            relativo, existe = achado
            if bruto != '/' and '.' not in os.path.basename(relativo) and not existe:
                self.path = '/index.html'
            elif relativo == '':
                self.path = '/' + (f'?{consulta}' if consulta else '')
            else:
                self.path = f'/{relativo}' + (f'?{consulta}' if consulta else '')
            super().do_GET()

        def log_message(self, formato: str, *args) -> None:
            return

    ThreadingHTTPServer(('127.0.0.1', porta), Pedido).serve_forever()


if __name__ == '__main__':
    main()
