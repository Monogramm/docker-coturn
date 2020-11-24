# Coturn TURN server in Docker
#
# This Dockerfile creates a container which runs a Coturn TURN server suitable
# for use with Spreed WebRTC.
#
# Install Docker and then run `docker build -t docker-webrtc-turnserver .` to
# build the image.
#
# Due to the nature of TURN, the container needs to use the hosts network. To
# configure the details, create the config file `data/config`. See the example
# in `data/config.example` for some ideas.
# ```
#
# Afterwards run the container like this:
#
#   ```
#   docker run --rm --net=host --name my-spreed-turnserver -i -v `pwd`/data:/srv -t monogramm/docker-coturn
#   ```
#
# This runs the container with the settings as defined in the config file which is
# made available to the container using the volume (-v) option. This volume is also
# used as storage for persistent data created by the TURN server.

# https://hub.docker.com/_/alpine
FROM alpine:3

# mongo-c-driver build arguments
ARG MONGO_C_DRIVER_VERSION=1.14.0
# Coturn build arguments
ARG VERSION=master

# Build and install Coturn
#   Install Coturn dependencies
#   Install tools for building
#   Install Coturn build dependencies
# Download and prepare mongo-c-driver sources
#   Build mongo-c-driver from sources
#   https://git.alpinelinux.org/aports/tree/non-free/mongo-c-driver/APKBUILD
#   Check mongo-c-driver build
#   Install mongo-c-driver
# Download and prepare Coturn sources
#   Build Coturn from sources
#   (No documentation included to keep image size smaller)
#   Install and configure Coturn
#   Preserve license file
#   Remove default config file
#   Cleanup unnecessary stuff
RUN set -ex; \
	apk update \
	&& apk upgrade \
	&& apk add --no-cache \
		ca-certificates \
		curl \
	&& update-ca-certificates \
	\
	&& apk add --no-cache \
		hiredis \
		icu-libs \
		libevent \
		libcrypto1.1 \
		libssl1.1 \
		libpq \
		mariadb-connector-c \
		snappy \
		sqlite-libs \
		zlib \
	\
	&& apk add --no-cache --virtual .tool-deps \
		autoconf \
		cmake \
		coreutils \
		g++ \
		libtool \
		make \
	\
	&& apk add --no-cache --virtual .build-deps \
		hiredis-dev \
		linux-headers \
		libevent-dev \
		mariadb-connector-c-dev \
		openssl-dev \
		postgresql-dev \
		snappy-dev \
		sqlite-dev \
		zlib-dev \
	; \
	curl -fL \
		-o /tmp/mongo-c-driver.tar.gz \
		https://github.com/mongodb/mongo-c-driver/archive/${MONGO_C_DRIVER_VERSION}.tar.gz \
 	&& tar -xzf /tmp/mongo-c-driver.tar.gz -C /tmp/ \
 	&& cd /tmp/mongo-c-driver-* \
 	&& mkdir -p /tmp/build/mongo-c-driver/ \
	&& cd /tmp/build/mongo-c-driver/ \
 	&& cmake \
			-DCMAKE_BUILD_TYPE=Release \
			-DCMAKE_INSTALL_PREFIX=/usr \
			-DCMAKE_INSTALL_LIBDIR=lib \
			-DENABLE_BSON:STRING=ON \
			-DENABLE_MONGOC:BOOL=ON \
			-DENABLE_SSL:STRING=OPENSSL \
			-DENABLE_AUTOMATIC_INIT_AND_CLEANUP:BOOL=OFF \
			-DENABLE_MAN_PAGES:BOOL=OFF \
			-DENABLE_TESTS:BOOL=ON \
			-DENABLE_EXAMPLES:BOOL=OFF \
			-DCMAKE_SKIP_RPATH=ON \
		/tmp/mongo-c-driver-* \
 	&& make \
	&& MONGOC_TEST_SKIP_MOCK=on \
 	   MONGOC_TEST_SKIP_SLOW=on \
 	   MONGOC_TEST_SKIP_LIVE=on \
 	   make check \
	\
	&& make install; \
	curl -fL \
		-o /tmp/coturn.tar.gz \
		"https://github.com/coturn/coturn/archive/${VERSION}.tar.gz" \
	&& tar -xzf /tmp/coturn.tar.gz -C /tmp/ \
	&& cd /tmp/coturn-* \
	\
	&& ./configure --prefix=/usr \
		--turndbdir=/var/lib/coturn \
		--disable-rpath \
		--sysconfdir=/etc/coturn \
		--mandir=/tmp/coturn/man \
		--docsdir=/tmp/coturn/docs \
		--examplesdir=/tmp/coturn/examples \
	&& make \
	\
	&& make install \
	&& mkdir -p /usr/share/licenses/coturn/ \
	&& cp /tmp/coturn/docs/LICENSE /usr/share/licenses/coturn/ \
	&& rm -f /etc/coturn/turnserver.conf.default \
	\
	&& apk del .tool-deps .build-deps \
	&& rm -rf \
		/var/cache/apk/* \
		/tmp/*

# Allow volume
VOLUME /srv

# Environment variables for runtime setup
ENV LISTENING_PORT="3478" \
	TLS_LISTENING_PORT="5349" \
	ALT_LISTENING_PORT="3479" \
	ALT_TLS_LISTENING_PORT="5350" \
	REALM="localdomain" \
	MIN_PORT="49152" \
	MAX_PORT="65535" \
	# 5 Mbit/second per TURN session
	MAX_BPS="640000" \
	# 50 Mbit/second
	BPS_CAPACITY="6400000" \
	CIPHER_LIST="ECDH+AESGCM:DH+AESGCM:ECDH+AES256:DH+AES256:ECDH+AES128:DH+AES:ECDH+3DES:DH+3DES:RSA+AES:RSA+3DES:!ADH:!AECDH:!MD5" \
	USER_QUOTA=100 \
	TOTAL_QUOTA=300 \
	USER_DB="/srv/turnserver/db/turndb.sqlite" \
	LOG_FILE="/srv/turnserver/logs/turn.log" \
	PID_FILE="/srv/turnserver/turn.pid"

# Add coturn entrypoint
COPY docker-entrypoint.sh /entrypoint.sh

RUN set -ex; \
	chmod 755 /entrypoint.sh

WORKDIR /
ENTRYPOINT ["sh","/entrypoint.sh"]

# Label build arguments
ARG BUILD_DATE
ARG VCS_REF

# Labels (docker maintainer + http://label-schema.org/)
LABEL maintainer="Monogramm Maintainers <opensource at monogramm dot io>" \
	org.label-schema.build-date=${BUILD_DATE} \
	org.label-schema.name="coturn" \
	org.label-schema.description="Free open source implementation of TURN and STUN Server" \
	org.label-schema.url="https://github.com/coturn/coturn" \
	org.label-schema.vcs-ref=${VCS_REF} \
	org.label-schema.vcs-url="https://github.com/Monogramm/docker-coturn" \
	org.label-schema.vendor="Monogramm" \
	org.label-schema.version=${VERSION} \
	org.label-schema.schema-version="1.0"
