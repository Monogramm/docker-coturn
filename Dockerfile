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
FROM alpine:edge

LABEL maintainer="Monogramm Maintainers <opensource at monogramm dot io>"

# Build arguments
ARG COTURN_VERSION=4.5.1.1
ARG MONGO_C_DRIVER_VERSION=1.14.0

# Add coturn entrypoint
COPY docker-entrypoint.sh /entrypoint.sh

# Build and install Coturn
RUN set -ex; \
	chmod 755 /entrypoint.sh; \
	apk update \
	&& apk upgrade \
	&& apk add --no-cache \
		ca-certificates \
		curl \
	&& update-ca-certificates \
	\
	# Install Coturn dependencies
	&& apk add --no-cache \
		hiredis \
		libevent \
		libcrypto1.1 \
		libssl1.1 \
		libpq mariadb-connector-c \
		snappy \
		sqlite-libs \
		zlib \
	\
	# Install tools for building
	&& apk add --no-cache --virtual .tool-deps \
		autoconf \
		cmake \
		coreutils \
		g++ \
		libtool \
		make \
	\
	# Install Coturn build dependencies
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
	\
	# Download and prepare mongo-c-driver sources
	&& curl -fL \
		-o /tmp/mongo-c-driver.tar.gz \
		https://github.com/mongodb/mongo-c-driver/archive/${MONGO_C_DRIVER_VERSION}.tar.gz \
 	&& tar -xzf /tmp/mongo-c-driver.tar.gz -C /tmp/ \
 	&& cd /tmp/mongo-c-driver-* \
 	# Build mongo-c-driver from sources
 	# https://git.alpinelinux.org/aports/tree/non-free/mongo-c-driver/APKBUILD
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
 	# Check mongo-c-driver build
	&& MONGOC_TEST_SKIP_MOCK=on \
 	   MONGOC_TEST_SKIP_SLOW=on \
 	   MONGOC_TEST_SKIP_LIVE=on \
 	   make check \
	\
 	# Install mongo-c-driver
	&& make install \
	\
	# Download and prepare Coturn sources
	&& curl -fL \
		-o /tmp/coturn.tar.gz \
		https://github.com/coturn/coturn/archive/${COTURN_VERSION}.tar.gz \
	&& tar -xzf /tmp/coturn.tar.gz -C /tmp/ \
	&& cd /tmp/coturn-* \
	\
	# Build Coturn from sources
	&& ./configure --prefix=/usr \
		--turndbdir=/var/lib/coturn \
		--disable-rpath \
		--sysconfdir=/etc/coturn \
		# No documentation included to keep image size smaller
		--mandir=/tmp/coturn/man \
		--docsdir=/tmp/coturn/docs \
		--examplesdir=/tmp/coturn/examples \
	&& make \
	\
	# Install and configure Coturn
	&& make install \
	# Preserve license file
	&& mkdir -p /usr/share/licenses/coturn/ \
	&& cp /tmp/coturn/docs/LICENSE /usr/share/licenses/coturn/ \
	# Remove default config file
	&& rm -f /etc/coturn/turnserver.conf.default \
	\
	# Cleanup unnecessary stuff
	&& apk del .tool-deps .build-deps \
	&& rm -rf \
		/var/cache/apk/* \
		/tmp/*

# Allow volume.
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

WORKDIR /
ENTRYPOINT ["sh","/entrypoint.sh"]
