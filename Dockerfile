FROM golang:1.23-alpine AS builder

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /node-agent ./cmd/node-agent

FROM alpine:3.21
RUN apk add --no-cache tini
COPY --from=builder /node-agent /usr/local/bin/node-agent
COPY profiles/ /etc/amd-gpu-mock/profiles/
ENTRYPOINT ["tini", "--"]
CMD ["node-agent"]
