# Reproducible image: React dist + Go server.
# Same git commit and SOURCE_DATE_EPOCH should rebuild the same binary.
# Runtime is Alpine 3.20. Its BusyBox provides /usr/bin/wget (symlink to
# /bin/busybox) including --spider; wget is not installed as a separate package.
# Verified on alpine:3.20 (BusyBox v1.36.1): HTTP 200 -> exit 0, HTTP 404 and
# connection refused -> exit 1, including as uid 100.

FROM node:20-alpine AS web
WORKDIR /src/web
COPY web/package.json web/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY web/ ./
ENV NODE_OPTIONS=--max-old-space-size=1536
RUN npm run build && test -f dist/index.html

FROM golang:1.22-alpine AS server
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG SOURCE_DATE_EPOCH=0
ENV CGO_ENABLED=0 \
    GOFLAGS=-trimpath \
    SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH}
RUN go build -buildvcs=false -ldflags='-s -w -buildid=' -o /out/api-ops-server ./cmd/server

FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata postgresql-client \
    && addgroup -g 101 -S app \
    && adduser -u 100 -S -D -H -G app app \
    && mkdir -p /data/billing-exports \
    && chown 100:101 /data/billing-exports \
    && chmod 775 /data/billing-exports
WORKDIR /app
COPY --from=server /out/api-ops-server /app/api-ops-server
COPY --from=web /src/web/dist/ /app/web/dist/
COPY internal/billing/templates/ /app/internal/billing/templates/
COPY docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod 755 /app/docker-entrypoint.sh /app/api-ops-server \
    && chown -R app:app /app
USER app
ENV TZ=Asia/Shanghai
EXPOSE 8088
VOLUME ["/data/billing-exports"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
    CMD ["wget", "-q", "--spider", "-T", "3", "http://127.0.0.1:8088/healthz"]
ENTRYPOINT ["/app/docker-entrypoint.sh"]
