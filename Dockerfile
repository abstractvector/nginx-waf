ARG DEBIAN_VERSION=11

ARG NGINX_VERSION=1.20.2

# use Debian as the base image to build nginx
FROM debian:${DEBIAN_VERSION}-slim AS build

ARG NGINX_VERSION

ARG HEADERS_MORE_VERSION=0.33

ARG MODSECURITY_VERSION=3.0.6
ARG MODSECURITY_NGINX_VERSION=1.0.2

ARG OWASP_CRS_VERSION=3.3.2

ARG NGINX_CC_OPT="-g -O2 -fstack-protector-strong -Wformat -Werror=format-security -Wp,-D_FORTIFY_SOURCE=2 -fPIC"
ARG NGINX_LD_OPT="-Wl,-z,relro -Wl,-z,now -Wl,--as-needed -pie"

ARG NGINX_COMPILE_ARGS="\
  --with-compat \
  --with-file-aio \
  --with-threads \
  --with-http_auth_request_module \
  --with-http_geoip_module \
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
  apt-utils \
  autoconf \
  automake \
  build-essential \
  ca-certificates \
  gcc \
  git \
  libc-dev \
  libbz2-dev \
  libcurl4-openssl-dev \
  libgeoip-dev \
  liblmdb-dev \
  libpcre3-dev \
  libpcre++-dev \
  libssl-dev \
  libtool \
  libxml2-dev \
  libyajl-dev \
  libxslt1-dev \
  lsb-release \
  make \
  pkgconf \
  wget \
  zlib1g-dev"

# prevent packages from prompting interactive input
ENV DEBIAN_FRONTEND=noninteractive

# install build dependencies
RUN apt-get update && \
  apt-get install -y ${BUILD_DEPENDENCIES}

# download, build and install modsecurity
RUN wget https://github.com/SpiderLabs/ModSecurity/releases/download/v${MODSECURITY_VERSION}/modsecurity-v${MODSECURITY_VERSION}.tar.gz && \
  tar xf modsecurity-v${MODSECURITY_VERSION}.tar.gz && \
  cd modsecurity-v${MODSECURITY_VERSION} && \
  ./build.sh && \
  ./configure && \
  make && \
  make install && \
  cd ..

# download and extract modsecurity-nginx
RUN wget https://github.com/SpiderLabs/ModSecurity-nginx/releases/download/v${MODSECURITY_NGINX_VERSION}/modsecurity-nginx-v${MODSECURITY_NGINX_VERSION}.tar.gz && \
  tar xf modsecurity-nginx-v${MODSECURITY_NGINX_VERSION}.tar.gz && \
  mv modsecurity-nginx-v${MODSECURITY_NGINX_VERSION} modsecurity-nginx

# download and extract ngx_headers_more
RUN wget https://github.com/openresty/headers-more-nginx-module/archive/refs/tags/v${HEADERS_MORE_VERSION}.tar.gz && \
  tar xf v${HEADERS_MORE_VERSION}.tar.gz && \
  mv headers-more-nginx-module-${HEADERS_MORE_VERSION} headers-more-nginx

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
  --error-log-path=/dev/stderr \
  --http-log-path=/proc/self/fd/2 \
  --pid-path=/var/run/nginx.pid \
  --lock-path=/var/run/nginx.lock \
  --http-client-body-temp-path=/var/cache/nginx/client_temp \
  --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
  --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
  --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
  --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
  --user=nonroot \
  --group=nonroot \
  --add-module=../modsecurity-nginx \
  --add-module=../headers-more-nginx \
  ${NGINX_COMPILE_ARGS} \
  --with-cc-opt="${NGINX_CC_OPT}" \
  --with-ld-opt="${NGINX_LD_OPT}" \
  && \
  make && \
  make install

# create directories in the build image as mkdir won't exist in the distroless image
RUN mkdir -p /var/cache/nginx/ && \
  mkdir -p /var/cache/nginx/client_temp && \
  mkdir -p /var/cache/nginx/proxy_temp && \
  mkdir -p /var/cache/nginx/fastcgi_temp && \
  mkdir -p /var/cache/nginx/uwsgi_temp && \
  mkdir -p /var/cache/nginx/scgi_temp && \
  mkdir -p /var/lib/nginx && \
  mkdir -p /etc/nginx/conf.d/ && \
  mkdir -p /etc/nginx/modsecurity/ && \
  mkdir -p /etc/nginx/crs/ && \
  mkdir -p /nginx/lib/ && \
  mkdir -p /nginx/usr/lib/ && \
  touch /var/run/nginx.pid

# copy in the default configuration
COPY nginx.conf /etc/nginx/nginx.conf
COPY modsecurity/*.conf /etc/nginx/modsecurity/

# configure modsecurity and the owasp core rule set (crs)
RUN cp -pr modsecurity-v${MODSECURITY_VERSION}/unicode.mapping /etc/nginx/modsecurity && \
  wget https://github.com/coreruleset/coreruleset/archive/refs/tags/v${OWASP_CRS_VERSION}.tar.gz && \
  tar xf v${OWASP_CRS_VERSION}.tar.gz && \
  mv coreruleset-${OWASP_CRS_VERSION}/crs-setup.conf.example /etc/nginx/crs/crs-setup.conf && \
  mv coreruleset-${OWASP_CRS_VERSION}/rules/ /etc/nginx/crs/rules/

# copy the dependencies into a single folder so they're easy to copy to the runtime image later
RUN ldd /usr/sbin/nginx | grep '=>' | cut -d' ' -f 3 | grep -e '^/lib' | xargs -I{} cp -p {} /nginx/lib/ && \
  ldd /usr/sbin/nginx | grep '=>' | cut -d' ' -f 3 | grep -e '^/usr/lib' | xargs -I{} cp -p {} /nginx/usr/lib/ && \
  ldd /usr/local/modsecurity/lib/libmodsecurity.so.3 | grep '=>' | cut -d' ' -f 3 | grep -e '^/lib' | xargs -I{} cp -p {} /nginx/lib/ && \
  ldd /usr/local/modsecurity/lib/libmodsecurity.so.3 | grep '=>' | cut -d' ' -f 3 | grep -e '^/usr/lib' | xargs -I{} cp -p {} /nginx/usr/lib/ && \
  cp -p /usr/local/modsecurity/lib/libmodsecurity.so.3 /nginx/usr/lib/

RUN cp -p /lib/x86_64-linux-gnu/libnss_compat.so.2 /nginx/lib/ && \
  cp -p /lib/x86_64-linux-gnu/libnss_files.so.2 /nginx/lib/

# use the static distroless image for our runtime image
FROM gcr.io/distroless/static:nonroot

ARG NGINX_VERSION
ARG TZ="UTC"

LABEL nginx.version=${NGINX_VERSION}

ENV TZ=${TZ}

COPY --from=build --chown=nonroot /var/cache/nginx /var/cache/nginx
COPY --from=build --chown=nonroot /var/run/nginx.pid /var/run/nginx.pid

COPY --from=build /etc/nginx /etc/nginx

COPY --from=build /usr/sbin/nginx /usr/bin/nginx

COPY --from=build /lib64/ld-linux-x86-64.so.2 /lib64/

COPY --from=build /nginx/lib/ /lib/x86_64-linux-gnu/
COPY --from=build /nginx/usr/lib/ /usr/lib/x86_64-linux-gnu/

EXPOSE 80/tcp
EXPOSE 443/tcp

STOPSIGNAL SIGTERM

ENTRYPOINT ["nginx", "-g", "daemon off;"]
