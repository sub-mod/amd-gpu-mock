# Host requirements for the library backend

The current validated host is an ARM64 Linux Podman VM on macOS. Kubernetes runs
inside its dedicated Kind node. CUSE runs in the Linux VM's kernel, not macOS.
The backend and workload device opens are native ARM64, not translated x86 calls.

CUSE is a host prerequisite. If `modprobe cuse` works on your Linux host, load it
before setup. A privileged container must see `/dev/cuse`. Device-node creation
alone does not provide CUSE behavior.

## This Podman VM

The existing Fedora CoreOS VM runs `7.1.3-200.fc44.aarch64`, with CONFIG_CUSE=m.
Its kernel-modules-extra package was absent. For this experiment only, the
matching signed Fedora RPM was downloaded and verified, extracted under /tmp,
and its module loaded without layering packages, replacing a VM or rebooting:

```bash
podman machine ssh
mkdir -p /tmp/amd-driver-mock-modules
cd /tmp/amd-driver-mock-modules
dnf download "kernel-modules-extra-$(uname -r)"
rpmkeys --checksig kernel-modules-extra-*.rpm
rpm2cpio kernel-modules-extra-*.rpm | cpio -id --quiet
sudo insmod "./lib/modules/$(uname -r)/kernel/fs/fuse/cuse.ko.xz"
ls -l /dev/cuse
exit
```

Use only the RPM matching the running kernel and accept no failed signature or
version check. These commands describe this Fedora environment, not a portable
installer. After a VM reboot, the temporary module load must be repeated. A
missing distribution package is an explicit setup blocker, not a reason to
substitute /dev/null. A future prepared worker image could include its matching
module package.

## Device mounts and isolation

Podman's named-volume default includes nodev, which prevents opening even a real
CUSE device stored in that volume. Setup enables dev only on the experiment's
private volume. Bind mounts inside the dedicated Kind node expose these endpoints
at /dev/kfd and /dev/dri paths; the host's actual device paths are not removed.
The provider itself is privileged infrastructure. Test workload Pods do not use
privileged mode or direct hostPath device mounts.

Cleanup destroys only amd-hami-driver, amd-driver-mock-provider and the private
state volume. The loaded CUSE module may remain until VM shutdown. Once no CUSE
users remain, `podman machine ssh 'sudo rmmod cuse'` removes that module; it must
not be forced out from under another CUSE consumer.

AMD64 Linux, Docker, CRC/OpenShift, additional GPUs and other kernels remain
unvalidated. The scripts contain a Docker runtime adapter, but that is not a
claim of a Docker clean-install result.
