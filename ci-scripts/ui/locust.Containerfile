FROM registry.access.redhat.com/ubi9/python-312:latest

USER root

ARG CFT_VERSION=147.0.7727.24
ARG CFT_BASE=https://storage.googleapis.com/chrome-for-testing-public
ARG LOCUST_VERSION=
ARG SELENIUM_VERSION=4.41.0

RUN dnf install -y --nodocs \
  alsa-lib atk at-spi2-atk at-spi2-core cups-libs dbus-libs gtk3 libdrm \
  libX11 libXcomposite libXdamage libXext libXfixes libXrandr libxcb libxkbcommon \
  libxshmfence libXtst mesa-libgbm nss nspr \
  fontconfig dejavu-sans-fonts \
  unzip \
  && dnf clean all \
  && rm -rf /var/cache/dnf /var/lib/dnf/repos

RUN curl -fsSL "${CFT_BASE}/${CFT_VERSION}/linux64/chrome-linux64.zip" -o /tmp/chrome.zip \
  && curl -fsSL "${CFT_BASE}/${CFT_VERSION}/linux64/chromedriver-linux64.zip" -o /tmp/driver.zip \
  && unzip -q /tmp/chrome.zip -d /opt/ \
  && unzip -q /tmp/driver.zip -d /opt/ \
  && rm -f /tmp/chrome.zip /tmp/driver.zip \
  && chmod -R a+rx /opt/chrome-linux64 /opt/chromedriver-linux64 \
  && ln -sf /opt/chrome-linux64/chrome /usr/local/bin/chromium \
  && ln -sf /opt/chromedriver-linux64/chromedriver /usr/local/bin/chromedriver

RUN python3 -m pip install --no-cache-dir --upgrade pip \
  && if [ -z "${LOCUST_VERSION}" ]; then \
       python3 -m pip install --upgrade --no-cache-dir locust "selenium==${SELENIUM_VERSION}"; \
     else \
       python3 -m pip install --no-cache-dir "locust==${LOCUST_VERSION}" "selenium==${SELENIUM_VERSION}"; \
     fi

ENV CHROME_BIN=/usr/local/bin/chromium \
  CHROMEDRIVER_PATH=/usr/local/bin/chromedriver \
  CHROME_SINGLE_PROCESS=0

USER 1001

WORKDIR /opt/app-root/src

EXPOSE 8089 5557

ENTRYPOINT ["locust"]
