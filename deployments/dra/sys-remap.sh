#!/bin/sh
# Point the /sys hostPath of AMD's DRA kubelet plugin at the mock sysfs tree.
#
# Reads rendered manifests of AMD's k8s-gpu-dra-driver chart on stdin and
# writes them to stdout, changing only the "sys" volume:
#
#   - name: sys              - name: sys
#     hostPath:        ->      hostPath:
#       path: /sys               path: /var/lib/amd-gpu-mock/sys
#
# Everything else in AMD's chart is left alone, so AMD's driver runs
# unmodified. Exits non-zero if no such volume is found (the chart changed).
#
#   helm template amd-dra <chart> --kube-version 1.34.0 \
#       --api-versions resource.k8s.io/v1 \
#       -f deployments/dra/values-mock.yaml \
#     | deployments/dra/sys-remap.sh | kubectl apply -f -
#
# Works as a Helm 3 --post-renderer too. Set MOCK_SYS if the mock chart's
# mockRootDir is not /var/lib/amd-gpu-mock.
#
# This is a stop-gap until AMD's chart makes the path configurable.
MOCK_SYS="${MOCK_SYS:-/var/lib/amd-gpu-mock/sys}"

exec awk -v mock_sys="$MOCK_SYS" '
    state == 2 {
        state = 0
        if ($0 ~ /^[[:space:]]*path:[[:space:]]*"?\/sys"?[[:space:]]*$/) {
            sub(/path:.*/, "path: " mock_sys)
            replaced++
            print
            next
        }
    }
    state == 1 {
        state = ($0 ~ /^[[:space:]]*hostPath:[[:space:]]*$/) ? 2 : 0
    }
    /^[[:space:]]*-[[:space:]]+name:[[:space:]]*"?sys"?[[:space:]]*$/ { state = 1 }
    { print }
    END {
        if (!replaced) {
            print "sys-remap: no \"sys\" hostPath volume found; did AMD change the chart?" > "/dev/stderr"
            exit 1
        }
    }
'
