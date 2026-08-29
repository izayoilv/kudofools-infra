FROM alpine:3.24 AS fetch
ARG RATHOLE_VERSION=v0.5.0
RUN apk add --no-cache unzip \
    && wget -q -O /rathole.zip https://github.com/rathole-org/rathole/releases/download/${RATHOLE_VERSION}/rathole-aarch64-unknown-linux-musl.zip \
    && unzip -o /rathole.zip -d /out \
    && chmod +x /out/rathole

FROM scratch
COPY --from=fetch /out/rathole /usr/bin/rathole
ENTRYPOINT ["/usr/bin/rathole"]
