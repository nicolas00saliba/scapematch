#!/usr/bin/env python3
"""Serve um build web do Flutter. Rotas sem arquivo caem no index.html."""

import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


def main() -> None:
    porta = int(sys.argv[1])
    raiz = Path(sys.argv[2]).resolve()

    class Pedido(SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=str(raiz), **kwargs)

        def do_GET(self) -> None:
            caminho = self.path.split('?', 1)[0]
            nome = caminho.rsplit('/', 1)[-1]
            arquivo = raiz / caminho.lstrip('/')
            if caminho != '/' and '.' not in nome and not arquivo.exists():
                self.path = '/index.html'
            super().do_GET()

        def log_message(self, formato: str, *args) -> None:
            return

    ThreadingHTTPServer(('127.0.0.1', porta), Pedido).serve_forever()


if __name__ == '__main__':
    main()
