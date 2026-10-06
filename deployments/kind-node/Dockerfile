FROM kindest/node:v1.37.0

# Install AMD Container Runtime and CDI toolkit (pre-compiled)
COPY bin/amd-container-runtime /usr/bin/amd-container-runtime
COPY bin/amd-ctk /usr/bin/amd-ctk
RUN chmod +x /usr/bin/amd-container-runtime /usr/bin/amd-ctk

# Containerd config: CDI enabled + AMD runtime as default runc handler
COPY containerd-config.toml /etc/containerd/config.toml

# AMD container runtime config: CDI mode
COPY amd-container-runtime.toml /etc/amd-container-runtime/config.toml

# CDI spec directories
RUN mkdir -p /etc/cdi /var/run/cdi
