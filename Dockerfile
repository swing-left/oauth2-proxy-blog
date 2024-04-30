# All builds should be done using the platform native to the build node to allow
#  cache sharing of the go mod download step.
# Go cross compilation is also faster than emulation the go compilation across
#  multiple platforms.
FROM --platform=${BUILDPLATFORM} golang:1.17-buster AS builder

# Copy sources
WORKDIR $GOPATH/src/github.com/oauth2-proxy/oauth2-proxy

# Fetch dependencies
COPY go.mod go.sum ./
RUN go mod download

# Now pull in our code
COPY . .

# Arguments go here so that the previous steps can be cached if no external
#  sources have changed.
ARG VERSION
ARG TARGETPLATFORM
ARG BUILDPLATFORM

# Build binary and make sure there is at least an empty key file.
#  This is useful for GCP App Engine custom runtime builds, because
#  you cannot use multiline variables in their app.yaml, so you have to
#  build the key into the container and then tell it where it is
#  by setting OAUTH2_PROXY_JWT_KEY_FILE=/etc/ssl/private/jwt_signing_key.pem
#  in app.yaml instead.
# Set the cross compilation arguments based on the TARGETPLATFORM which is
#  automatically set by the docker engine.
RUN case ${TARGETPLATFORM} in \
         "linux/amd64")  GOARCH=amd64  ;; \
         "linux/arm64")  GOARCH=arm64  ;; \
         "linux/arm/v6") GOARCH=arm GOARM=6  ;; \
    esac && \
    printf "Building OAuth2 Proxy for arch ${GOARCH}\n" && \
    GOARCH=${GOARCH} VERSION=${VERSION} make build && touch jwt_signing_key.pem

# Copy binary to alpine
FROM alpine:3.15
COPY nsswitch.conf /etc/nsswitch.conf
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=builder /go/src/github.com/oauth2-proxy/oauth2-proxy/oauth2-proxy /bin/oauth2-proxy
COPY --from=builder /go/src/github.com/oauth2-proxy/oauth2-proxy/jwt_signing_key.pem /etc/ssl/private/jwt_signing_key.pem

USER 2000:2000

ENTRYPOINT [ "sh", "-c", "/bin/oauth2-proxy --upstream=http://${UPSTREAM} --http-address=0.0.0.0:4180" ]
