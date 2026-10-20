# HAMi consumer images

The mock backend remains the published `amd-gpu-mock-driver:v0.1.1` image.
These two additional images package unchanged pinned HAMi consumers:

| Image | Contents |
| --- | --- |
| `docker.io/submod/amd-gpu-mock-hami:v0.1.0` | HAMi AMD device plugin and its upstream native allocation hook, on the shared driver image |
| `docker.io/submod/amd-gpu-mock-hami-scheduler:v0.1.0` | HAMi scheduler/extender binary on Ubuntu 24.04 |

Both target Linux AMD64 and ARM64. Source pins live in
[versions.env](../../demo/hami/versions.env). The build checks the amd-hami-core
submodule pin and compiles upstream source without patching it. The plugin links
against the shared AMD SMI/libdrm ABI; deployment selects the libraries staged
by main's node agent. No RocJITsu, HIP SDK or separate provider is required.

Maintainer native build, from the repository root:

```bash
CONTAINER_RUNTIME=docker scripts/build-hami-images.sh
# Optional per-architecture publication after validation; refuses existing tags.
CONTAINER_RUNTIME=docker scripts/build-hami-images.sh --push
```

Run on each native architecture. Publication creates `v0.1.0-amd64` and
`v0.1.0-arm64` tags; compose the multiarch indexes after both pass validation.
The `hami-e2e` workflow exports its exact tested images for this purpose and has
a `published=true` dispatch that installs the public images/chart without builds.
Use `HAMI_IMAGE_TAG` for a new immutable release instead of overwriting tags.
Users run [the setup script](../../demo/hami/setup.sh) and need no compiler.
