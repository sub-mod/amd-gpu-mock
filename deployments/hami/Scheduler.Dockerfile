FROM docker.io/library/golang:1.27.2 AS build
COPY tmp/hami-main/HAMi/ /hami/
WORKDIR /hami
RUN go build -o /scheduler ./cmd/scheduler
FROM docker.io/library/ubuntu:24.04
COPY --from=build /scheduler /usr/local/bin/scheduler
ENTRYPOINT ["scheduler"]
