#!/usr/bin/env python3
"""Stage repository documentation without modifying its Markdown sources."""
import argparse
import os
import re
import shutil
import subprocess
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[2]
STAGE = ROOT / 'tmp/docs-source'
SOURCE_URL = 'https://github.com/sub-mod/amd-gpu-mock/blob/main/'
LINK = re.compile(r'(!?\[[^\]]*\]\()([^\s)]+)([^)]*\))')


def stage():
    if STAGE.exists():
        shutil.rmtree(STAGE)
    STAGE.mkdir(parents=True)
    sources = [ROOT / 'README.md']
    for directory in ('docs', 'demo', 'artifacts'):
        sources.extend(p for p in (ROOT / directory).rglob('*') if p.is_file() and '__pycache__' not in p.parts and not p.name.startswith('.'))
    markdown = {p.resolve() for p in sources if p.suffix == '.md'}
    for source in sources:
        destination = STAGE / ('repository.md' if source == ROOT / 'README.md' else source.relative_to(ROOT))
        destination.parent.mkdir(parents=True, exist_ok=True)
        if source.suffix == '.md':
            def rewrite(match):
                target = match[2]
                parsed = urlsplit(target)
                if parsed.scheme or parsed.netloc or target.startswith('#'):
                    return match[0]
                resolved = (source.parent / unquote(parsed.path)).resolve()
                if resolved == ROOT / 'README.md':
                    relative = os.path.relpath(STAGE / 'repository.md', destination.parent)
                    return match[1] + relative + ('#' + parsed.fragment if parsed.fragment else '') + match[3]
                if resolved in markdown or (resolved.is_file() and resolved.suffix in ('.png', '.jpg', '.svg', '.gif')):
                    return match[0]
                try:
                    relative = resolved.relative_to(ROOT).as_posix()
                except ValueError:
                    return match[0]
                url = SOURCE_URL + relative
                if parsed.fragment:
                    url += '#' + parsed.fragment
                return match[1] + url + match[3]
            destination.write_text(LINK.sub(rewrite, source.read_text()))
        else:
            shutil.copyfile(source, destination)
    landing = (STAGE / 'docs/site/index.md').read_text()
    landing = landing.replace('(getting-started.md)', '(docs/site/getting-started.md)').replace('(demos.md)', '(docs/site/demos.md)').replace('(../architecture.md)', '(docs/architecture.md)').replace('(../how-it-works.md)', '(docs/how-it-works.md)').replace('(../guides/testing.md)', '(docs/guides/testing.md)')
    (STAGE / 'index.md').write_text(landing)
    readme = (STAGE / 'repository.md').read_text()
    quickstart = readme.split('## Quick start\n', 1)[1].split('## Dashboard\n', 1)[0]
    quickstart = quickstart.replace('(docs/', '(../').replace('deployments/kind-node/', 'deployments/kind-node/')
    (STAGE / 'docs/site/getting-started.md').write_text('# Quick start\n\n' + quickstart + '\nSee [telemetry](../guides/telemetry.md) for Grafana and dashboard details.\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serve', action='store_true', help='Preview at http://127.0.0.1:8001')
    args = parser.parse_args()
    stage()
    command = ['mkdocs', 'serve', '--dev-addr', '127.0.0.1:8001'] if args.serve else ['mkdocs', 'build', '--strict']
    subprocess.run(command, cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
