# ==============================================================================
# Hostvra API — Multi-stage Docker Build
# ==============================================================================

# ── Stage 1: Build ────────────────────────────────────────────────────────────
FROM golang:1.26-alpine AS builder

RUN apk add --no-cache git ca-certificates tzdata

WORKDIR /src

# Copy both go modules (api depends on agent via replace directive)
COPY apps/agent/go.mod apps/agent/go.sum* ./apps/agent/
COPY apps/api/go.mod apps/api/go.sum* ./apps/api/

# Download dependencies first (layer cache)
WORKDIR /src/apps/agent
RUN go mod download

WORKDIR /src/apps/api
RUN go mod download

# Copy full source
WORKDIR /src
COPY apps/agent/ ./apps/agent/
COPY apps/api/ ./apps/api/

# Build static binary
WORKDIR /src/apps/api
RUN CGO_ENABLED=0 GOOS=linux go build \
    -ldflags="-s -w -X main.version=$(date +%Y%m%d)" \
    -o /hostvra-api \
    cmd/server/main.go

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM alpine:3.21

RUN apk add --no-cache ca-certificates tzdata curl

# Non-root user
RUN addgroup -S hostvra && adduser -S hostvra -G hostvra

COPY --from=builder /hostvra-api /usr/local/bin/hostvra-api

# Create data directories
RUN mkdir -p /var/lib/hostvra /var/log/hostvra && \
    chown -R hostvra:hostvra /var/lib/hostvra /var/log/hostvra

USER hostvra

EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -sf http://localhost:8080/api/v1/health || exit 1

ENTRYPOINT ["hostvra-api"]
