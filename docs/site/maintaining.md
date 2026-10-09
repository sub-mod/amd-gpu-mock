# Build and publish the documentation

The site uses Material for MkDocs and the existing repository Markdown. Demo
READMEs remain the source for runnable walkthroughs and captured logs. The staging
script preserves Markdown pages and images and points other source-file links
back to GitHub. It writes only under `tmp/`.

```bash
python3 -m venv tmp/docs-venv
. tmp/docs-venv/bin/activate
python -m pip install -r scripts/docs/requirements.txt
python scripts/docs/build.py
# Preview at http://127.0.0.1:8001; stop with Ctrl-C.
python scripts/docs/build.py --serve
```

Navigation is in `mkdocs.yml`. The quick-start page is extracted from the root
README during staging, so installation commands have one source. Add new demos
to the navigation and demo catalog; distinguish implemented behavior from plans.

The `docs-site` GitHub Actions workflow validates builds on pull requests.
On a push to `main`, or manual dispatch, it uploads the built site and deploys
through GitHub Pages. Repository Settings → Pages → Source must be **GitHub
Actions**. Once deployed, the intended address is
[the project documentation](https://sub-mod.github.io/amd-gpu-mock/).
Local changes alone do not publish the site.
