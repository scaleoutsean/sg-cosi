# syntax=docker.io/docker/dockerfile:1
# check=error=true

FROM --platform=$BUILDPLATFORM golang:1.26 AS builder

ARG TARGETOS
ARG TARGETARCH

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -ldflags="-s -w" \
    -o sg-cosi-driver ./cmd/sg-cosi-driver
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -ldflags="-s -w" \
    -o sg-cosi-snapshotlease-controller ./cmd/sg-cosi-snapshotlease-controller

FROM gcr.io/distroless/static-debian13:nonroot
COPY --from=builder /app/sg-cosi-driver /usr/bin/sg-cosi-driver
COPY --from=builder /app/sg-cosi-snapshotlease-controller /usr/bin/sg-cosi-snapshotlease-controller
ENTRYPOINT ["/usr/bin/sg-cosi-driver"]
