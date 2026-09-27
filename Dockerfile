# Start with alpine for musl compile
FROM alpine:3.24 AS builder

ARG OPENGFX_VERSION=7.1

RUN apk add --no-cache \
    alpine-sdk \
    wget \
    ca-certificates \
    g++\
    make \
    patch \
    zlib-dev \
    xz-dev \
    libpng-dev \
    lzo-dev \
    zstd-dev \
    libcurl \
    curl \
    sdl2 \
    unzip \
    tar \
    git \
    cmake \
    musl-dev \
    musl-utils

RUN mkdir -p /openttd_data/baseset

WORKDIR /openttd_data/baseset
RUN wget -q -O opengfx-${OPENGFX_VERSION}.zip https://cdn.openttd.org/opengfx-releases/${OPENGFX_VERSION}/opengfx-${OPENGFX_VERSION}-all.zip \
  && unzip opengfx-${OPENGFX_VERSION}.zip \
  && tar -xf opengfx-${OPENGFX_VERSION}.tar \
  && rm -rf opengfx-*.tar opengfx-*.zip

COPY OpenTTD-patches /OpenTTD-patches
WORKDIR /OpenTTD-patches

RUN mkdir -p /OpenTTD-patches/build
WORKDIR /OpenTTD-patches/build

# ldconfig is not working properly so don't install
RUN cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DOPTION_DEDICATED=ON \
        -DOPTION_COMPRESS_DEBUG=ON \
        -DOPTION_LTO=ON \
        -DOPTION_TRIM_PATH_PREFIX=ON \
        -DOPTION_PACKAGE_DEPENDENCIES=ON \
    && cmake --build . -j $(nproc)

RUN mkdir -p /openttd && \
  mv ai/ /openttd && \
  mv baseset/ /openttd && \
  mv game/ /openttd && \
  mv lang /openttd && \
  mv openttd /openttd && \
  mv scripts /openttd && \
  chmod +x /openttd/openttd

RUN printf '#include <sys/socket.h>\n#include <netinet/in.h>\n#include <arpa/inet.h>\n#include <unistd.h>\nint main(){\n    int s = socket(AF_INET, SOCK_STREAM, 0);\n    if (s < 0) return 1;\n    struct sockaddr_in a = {\n        .sin_family = AF_INET,\n        .sin_port = htons(3979),\n        .sin_addr.s_addr = htonl(INADDR_LOOPBACK)\n    };\n    int r = connect(s, (struct sockaddr*)&a, sizeof(a));\n    close(s);\n    return (r == 0) ? 0 : 1;\n}\n' > /tmp/healthcheck.c \
  && gcc -static -O2 -s /tmp/healthcheck.c -o /openttd/healthcheck \
  && chmod 755 /openttd/healthcheck

RUN mkdir -p /requirements \
  && ldd /openttd/openttd | awk 'NF == 4 { system("cp --parents " $3 " /requirements") }'

RUN echo "openttd:x:901:901:OpenTTD User,,,:/openttd_data:/openttd/openttd" > /etc/passwd

# Just the necessary
FROM scratch

COPY --chown=901 --from=builder /openttd /openttd
COPY --chown=901 --from=builder /openttd_data /openttd_data
COPY --chown=0 --from=builder /requirements /
COPY --chown=0 --from=builder /etc/passwd /etc/passwd

VOLUME /openttd_data

EXPOSE 3979/tcp
EXPOSE 3979/udp

STOPSIGNAL 3

USER openttd

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD [ "/openttd/healthcheck" ]

ENTRYPOINT [ "/openttd/openttd", "-D", "-c", "/openttd_data/openttd.cfg", "-x", "-g" ]
