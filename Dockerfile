FROM golang:1.26-bookworm AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /node-agent ./cmd/node-agent && \
    CGO_ENABLED=0 GOOS=linux go build -o /nri-plugin ./cmd/nri-plugin && \
    make -C pkg/mocksmi

FROM alpine:3.21
RUN apk add --no-cache tini
COPY --from=builder /node-agent /usr/local/bin/node-agent
COPY --from=builder /nri-plugin /usr/local/bin/nri-plugin
COPY --from=builder /src/pkg/mocksmi/libamd_smi.so /usr/lib64/libamd_smi.so
RUN ln -s /usr/lib64/libamd_smi.so /usr/lib64/libamd_smi.so.27
COPY profiles/ /etc/amd-gpu-mock/profiles/
ENTRYPOINT ["tini", "--"]
CMD ["node-agent"]
