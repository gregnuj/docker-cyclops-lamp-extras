FROM gregnuj/cyclops-lamp:latest
LABEL MAINTAINER="Greg Junge <gregnuj@gmail.com>"
USER root

ARG HTTP_PROXY

# Copy microsoft odbc libs
FROM mcr.microsoft.com/mssql-tools as mssql

COPY --from=mssql /opt/microsoft/ /opt/microsoft/
COPY --from=mssql /opt/mssql-tools/ /opt/mssql-tools/
COPY --from=mssql /usr/lib/libmsodbcsql-13.so /usr/lib/libmsodbcsql-13.so

# Set up glibc
ENV GLIBC_VERSION="2.28-r0"

RUN set -ex \
    # download glibc
    && cd tmp \
    && curl -sLo /etc/apk/keys/sgerrand.rsa.pub https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub \
    && curl -sLo glibc.apk "https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_VERSION}/glibc-${GLIBC_VERSION}.apk" \
    && curl -sLo glibc-bin.apk "https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_VERSION}/glibc-bin-${GLIBC_VERSION}.apk" \

    # install glibc
    && apk add --no-cache glibc-bin.apk glibc.apk \
    && /usr/glibc-compat/sbin/ldconfig /lib /usr/glibc-compat/lib \
    && echo 'hosts: files mdns4_minimal [NOTFOUND=return] dns mdns4' >> /etc/nsswitch.conf \
    && rm -rf glibc.apk glibc-bin.apk

# Set up Oracle Instant Client
ENV \
    INSTACLIENT_VERSION="11.2.0.4.0" \
    BASIC="instantclient-basic-linux.x64-${INSTACLIENT_VERSION}.zip" \
    SDK="instantclient-sdk-linux.x64-${INSTACLIENT_VERSION}.zip" \
    SQLPLUS="instantclient-sqlplus-linux.x64-${INSTACLIENT_VERSION}.zip" \
    ORACLE_DEPENDENCIES="libnsl libaio" \
    BUILD_DEPENDENCIES="php7-dev unixodbc-dev gcc musl-dev build-base" \
    LD_LIBRARY_PATH="/usr/local/instantclient" \
    ORACLE_HOME="/usr/local/instantclient" 

## Install Build dependencies
RUN set -ex \
    && apk add --nocache ${ORACLE_DEPENDENCIES} ${BUILD_DEPENDENCIES}

## Install Oracle Instant Client
RUN set -ex \
    && cd /tmp \
    ## Download instaclient
    && curl -sLo ${BASIC} https://raw.githubusercontent.com/bumpx/oracle-instantclient/master/${BASIC} \
    && curl -sLo ${SDK} https://raw.githubusercontent.com/bumpx/oracle-instantclient/master/${SDK} \
    && curl -sLo ${SQLPLUS} https://raw.githubusercontent.com/bumpx/oracle-instantclient/master/${SQLPLUS} \
    ## Unpack instaclient
    && unzip -o -d /usr/local/ ${BASIC} \
    && unzip -o -d /usr/local/ ${SDK} \
    && unzip -o -d /usr/local/ ${SQLPLUS} \
    ## create symllinks
    && ln -sf /usr/local/instantclient_11_2 ${ORACLE_HOME} \
    && ln -sf ${ORACLE_HOME}/libclntsh.so.* ${ORACLE_HOME}/libclntsh.so \
    && ln -sf ${ORACLE_HOME}/libocci.so.* ${ORACLE_HOME}/libocci.so \
    && ln -sf ${ORACLE_HOME}/sqlplus /usr/bin/sqlplus \
    && ln -sf ${ORACLE_HOME}/lib* /usr/lib \
    && ln -sf /usr/lib/libnsl.so.2.0.0  /usr/lib/libnsl.so.1 \
    ## Install oci8
    && curl -sLo oci8-2.2.0.tgz https://pecl.php.net/get/oci8-2.2.0.tgz \
    && if [ -n "${HTTP_PROXY}" ]; then pear config-set http_proxy ${HTTP_PROXY}; fi \
    && echo "instantclient,${ORACLE_HOME}" | pecl install /tmp/oci8-2.2.0.tgz \
    && echo 'extension=oci8.so' > /etc/php7/conf.d/30-oci8.ini 

## Intall MSSQL lib
RUN set -ex \
    && cd /tmp \
    && apk add --nocache ${BUILD_DEPENDENCIES} \
    ## download manually
    && curl -sLo /tmp/sqlsrv.tgz https://pecl.php.net/get/sqlsrv \
    && curl -sLo /tmp/pdo_sqlsrv.tgz https://pecl.php.net/get/pdo_sqlsrv \
    ## Build OCI8 with PECL
    && if [ -n "${HTTP_PROXY}" ]; then pear config-set http_proxy ${HTTP_PROXY}; fi \
    && pecl install sqlsrv.tgz pdo_sqlsrv.tgz \
    && echo 'extension=sqlsrv.so' > /etc/php7/conf.d/31_sqlsrv.ini \
    && echo 'extension=pdo_sqlsrv.so' > /etc/php7/conf.d/32_pdo_sqlsrv.ini 

## Clean up
RUN set -ex \
    && rm -rf /tmp/* \
    && apk del ${BUILD_DEPENDENCIES}

