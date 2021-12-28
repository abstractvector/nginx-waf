ARG NGINX_VERSION=1.20.2
ARG DEBIAN_VERSION=11
ARG TZ="UTC"

# use Debian as the base image to build nginx
FROM debian:${DEBIAN_VERSION}-slim AS build

ARG NGINX_VERSION

ARG NGINX_CC_OPT="-g -O2 -fstack-protector-strong -Wformat -Werror=format-security -Wp,-D_FORTIFY_SOURCE=2 -fPIC"
ARG NGINX_LD_OPT="-Wl,-z,relro -Wl,-z,now -Wl,--as-needed -pie"

ARG NGINX_COMPILE_ARGS="\
  --with-compat \
  --with-file-aio \
  --with-threads \
  --with-http_auth_request_module \
  --with-http_gunzip_module \
  --with-http_realip_module \
  --with-http_ssl_module \
  --with-http_stub_status_module \
  --with-http_v2_module \
  --with-stream \
  --with-stream_realip_module \
  --with-stream_ssl_module \
  --with-stream_ssl_preread_module"

ARG BUILD_DEPENDENCIES="\
  apt-transport-https \
  autoconf \
  ca-certificates \
  gcc \
  libc-dev \
  libbz2-dev \
  libpcre3-dev \
  libssl-dev \
  libxml2-dev \
  libxslt1-dev \
  lsb-release \
  make \
  wget \
  zlib1g-dev"

# install build dependencies
RUN apt-get update && \
  apt-get install -y ${BUILD_DEPENDENCIES}

# download nginx source
RUN wget http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz && \
  tar xf nginx-${NGINX_VERSION}.tar.gz

# compile, make and install nginx
RUN cd nginx-${NGINX_VERSION} && \
  ./configure \
  --prefix=/etc/nginx \
  --sbin-path=/usr/sbin/nginx \
  --modules-path=/usr/lib/nginx/modules \
  --conf-path=/etc/nginx/nginx.conf \
  --error-log-path=/var/log/nginx/error.log \
  --http-log-path=/var/log/nginx/access.log \
  --pid-path=/var/run/nginx.pid \
  --lock-path=/var/run/nginx.lock \
  --http-client-body-temp-path=/var/cache/nginx/client_temp \
  --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
  --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
  --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
  --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
  --user=nonroot \
  --group=nonroot \
  ${NGINX_COMPILE_ARGS} \
  --with-cc-opt="${NGINX_CC_OPT}" \
  --with-ld-opt="${NGINX_LD_OPT}" \
  && \
  make && \
  make install

# create directories in the build image as mkdir won't exist in the distroless image
RUN mkdir -p /var/cache/nginx/ && \
  mkdir -p /var/lib/nginx && \
  mkdir -p /etc/nginx/conf.d/ && \
  mkdir -p /nginx/lib/

# copy in the nginx.conf
COPY nginx.conf /etc/nginx/nginx.conf

# copy the dependencies into a single folder so they're easy to copy to the runtime image later
RUN ldd /usr/sbin/nginx | grep '=>' | cut -d' ' -f 3 | grep -e '^/lib' | xargs -I{} cp -p {} /nginx/lib/

RUN cp -p /lib/x86_64-linux-gnu/libnss_compat.so.2 /nginx/lib/ && \
  cp -p /lib/x86_64-linux-gnu/libnss_files.so.2 /nginx/lib/

# use the static distroless image for our runtime image
FROM gcr.io/distroless/static

ARG NGINX_VERSION
ARG TZ

LABEL nginx.version=${NGINX_VERSION}

ENV TZ=${TZ}

COPY --from=build /var/cache/nginx /var/cache/nginx
COPY --from=build /var/log /var/log
COPY --from=build /var/run /var/run

COPY --from=build /etc/nginx /etc/nginx

COPY --from=build /usr/sbin/nginx /usr/bin/nginx

COPY --from=build /nginx/lib/ /lib/x86_64-linux-gnu/

COPY --from=build /usr/lib/x86_64-linux-gnu/libssl.so.1.1 /usr/lib/x86_64-linux-gnu/
COPY --from=build /usr/lib/x86_64-linux-gnu/libcrypto.so.1.1 /usr/lib/x86_64-linux-gnu/

COPY --from=build /lib64/ld-linux-x86-64.so.2 /lib64/

COPY --from=build /lib/x86_64-linux-gnu/libnss_compat.so.2 /lib/x86_64-linux-gnu/
COPY --from=build /lib/x86_64-linux-gnu/libnss_files.so.2 /lib/x86_64-linux-gnu/

EXPOSE 80/tcp
EXPOSE 443/tcp

STOPSIGNAL SIGTERM

ENTRYPOINT ["nginx", "-g", "daemon off;"]
