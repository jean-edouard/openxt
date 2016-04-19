#!/bin/sh
# Copyright (c) 2016 Assured Information Security, Inc.
# Copyright (c) 2016 BAE Systems
#
# Contributions by Jean-Edouard Lejosne
# Contributions by Christopher Clark
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#

set -e

BUILD_USER=%BUILD_USER%
BUILD_DIR=%BUILD_DIR%
IP_C=%IP_C%
BRANCH=%BRANCH%
SUBNET_PREFIX=%SUBNET_PREFIX%
ALL_BUILDS_SUBDIR_NAME=%ALL_BUILDS_SUBDIR_NAME%

HOST_IP=${SUBNET_PREFIX}.${IP_C}.1
LOCAL_USER=`whoami`
BUILD_PATH=`pwd`/openxt/build

cd ~/certs
CERTS_PATH=`pwd`
cd ..

setupoe() {
    source version
    cp build/conf/local.conf-dist build/conf/local.conf
    cat common-config >> build/conf/local.conf
    cat >> build/conf/local.conf <<EOF
# Distribution feed
XENCLIENT_PACKAGE_FEED_URI="file:///storage/ipk"

SSTATE_DIR ?= "$BUILD_PATH/sstate-cache/$BRANCH"

DL_DIR ?= "$BUILD_PATH/downloads"
export CCACHE_DIR = "$BUILD_PATH/cache"
CCACHE_TARGET_DIR="$CACHE_DIR"

OPENXT_MIRROR="http://mirror.openxt.org"
OPENXT_GIT_MIRROR="$HOST_IP/$BUILD_USER"
OPENXT_GIT_PROTOCOL="git"
OPENXT_BRANCH="$BRANCH"
OPENXT_TAG="$BRANCH"

XENCLIENT_BUILD_DATE = "`date +'%T %D'`"
XENCLIENT_BUILD_BRANCH = "${BRANCH}"
XENCLIENT_VERSION = "$VERSION"
XENCLIENT_RELEASE = "$RELEASE"
XENCLIENT_TOOLS = "$XENCLIENT_TOOLS"

# dir for generated deb packages
XCT_DEB_PKGS_DIR := "${BUILD_PATH}/xct_deb_packages"

# Production and development repository-signing CA certificates
REPO_PROD_CACERT="/home/${LOCAL_USER}/certs/prod-cacert.pem"
REPO_DEV_CACERT="/home/${LOCAL_USER}/certs/dev-cacert.pem"
EOF
}

build_step() {
    MACHINE=$1
    STEP=$2

    MACHINE=$MACHINE ./bb $STEP | tee -a build.log

    # The return value of `./bb` got hidden by `tee`. Bring it back.
    # Get the return value
    ret=${PIPESTATUS[0]}
    # Surface the value, the "-e" bash flag will pick up on any error
    ( exit $ret )
}

mkdir -p $BUILD_DIR
cd $BUILD_DIR

if [ ! -d openxt ] ; then
    # Clone main repos
    git clone -b ${BRANCH} git://${HOST_IP}/${BUILD_USER}/openxt.git
    cd openxt

    # Fetch "upstream" layers
    git submodule init
    git submodule update

    # Clone OpenXT layers
    git clone -b ${BRANCH} git://${HOST_IP}/${BUILD_USER}/xenclient-oe.git build/repos/xenclient-oe

    # Configure OpenXT
    setupoe
else
    cd openxt
fi

# Build
mkdir -p build
cd build
build_step "xenclient-dom0"       "xenclient-initramfs-image"
build_step "xenclient-stubdomain" "xenclient-stubdomain-initramfs-image"
build_step "xenclient-dom0"       "xenclient-dom0-image"
build_step "xenclient-uivm"       "xenclient-uivm-image"
build_step "xenclient-ndvm"       "xenclient-ndvm-image"

# Copy the build output
scp -r build-output/* "${BUILD_USER}@${SUBNET_PREFIX}.${IP_C}.1:${ALL_BUILDS_SUBDIR_NAME}/${BUILD_DIR}/"

# The script may run in an "ssh -t -t" environment, that won't exit on its own
set +e
exit
