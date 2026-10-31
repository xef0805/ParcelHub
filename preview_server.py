"""本机预览服务，仅监听 127.0.0.1，不上传包裹记录。"""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit, unquote
import argparse
import webbrowser
import json


class PreviewHandler(SimpleHTTPRequestHandler):
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map, '.mjs': 'text/javascript; charset=utf-8', '.json': 'application/json; charset=utf-8'}

    def allowed_path(self):
        path = unquote(urlsplit(self.path).path)
        return '..' not in path.split('/') and (path.startswith('/preview/') or path in (
            '/shared/catalog.json', '/shared/sms-reader.js', '/shared/brand-assets.json', '/shared/identity-link.js', '/shared/import-reader.js'))

    def do_HEAD(self):
        if not self.allowed_path():
            self.send_error(404)
            return
        super().do_HEAD()

    def do_GET(self):
        path = unquote(urlsplit(self.path).path)
        if path == '/api/official-snapshot':
            if self.headers.get('Host', '').split(':')[0] not in ('127.0.0.1', 'localhost'):
                self.send_error(403)
                return
            snapshot = Path(self.directory) / '.private' / 'official-snapshot.json'
            if not snapshot.is_file():
                self.send_error(404)
                return
            try:
                data = json.loads(snapshot.read_text(encoding='utf-8'))
                if data.get('state') == 'filtered_empty':
                    if data.get('parcels') != [] or data.get('expectedCount') not in (None, 0) or not isinstance(data.get('readAt'), str) or not data['readAt']:
                        raise ValueError('Invalid empty candidate')
                    data = {'state': 'filtered_empty', 'message': str(data.get('message', '')), 'parcels': [], 'expectedCount': 0, 'readAt': data['readAt']}
                elif data.get('state') != 'ready':
                    if data.get('state') not in ('login_required', 'loading', 'error'):
                        raise ValueError('Invalid official read')
                    # 非完整状态仅传递提示，不向界面提供残缺包裹列表。
                    data = {'state': data['state'], 'message': str(data.get('message', ''))}
                body = json.dumps(data, ensure_ascii=False).encode('utf-8')
            except (ValueError, OSError):
                self.send_error(503)
                return
            self.send_response(200)
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if path == '/':
            self.send_response(302)
            self.send_header('Location', '/preview/')
            self.end_headers()
            return
        # 不暴露工程文件；禁止目录穿越和目录列表。
        if not self.allowed_path():
            self.send_error(404)
            return
        super().do_GET()

    def list_directory(self, path):
        self.send_error(404)
        return None

    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        super().end_headers()


def main():
    parser = argparse.ArgumentParser(description='涂涂取件本机预览')
    parser.add_argument('--no-open', action='store_true')
    parser.add_argument('--port', type=int, default=8765)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    handler = partial(PreviewHandler, directory=str(root))
    server = None
    for port in range(args.port, args.port + 20):
        try:
            server = ThreadingHTTPServer(('127.0.0.1', port), handler)
            break
        except OSError:
            continue
    if server is None:
        raise SystemExit('无法启动本地预览：端口均被占用，请使用 --port 指定其他端口。')
    url = f'http://127.0.0.1:{server.server_port}/preview/'
    print(f'涂涂取件预览已启动：{url}', flush=True)
    print('关闭此窗口或按 Ctrl+C 停止。数据保存在当前浏览器。', flush=True)
    if not args.no_open:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
