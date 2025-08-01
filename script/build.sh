#!/bin/bash
set -e
cd "$(dirname "$0")/.."

./configure --disable-systemd \
--enable-busmonitor \
--enable-tpuart \
--enable-usb \
--enable-eibnetipserver \
--enable-eibnetip \
--enable-eibnetserver \
--enable-eibnetiptunnel \
 --enable-groupcache \
&& mkdir -p src/include/sys && ln -sf /usr/lib/bcc/include/sys/cdefs.h src/include/sys \
&& make -j$(nproc) \
&& mkdir -p bin \
&& cp src/server/knxd bin/ \
&& cp src/usb/findknxusb bin/ \
&& cp src/tools/knxtool bin/ \
&& echo "Build completed! Executables are in bin/ directory"