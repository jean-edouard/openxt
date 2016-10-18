#!/bin/bash -e
#
# OpenXT build script.
# Software license: see accompanying LICENSE file.
#
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
# Invocation:
# Takes a build identifier as an optional argument to the script
# to enable rerunning this script to continue an interrupted build
# or run a build with a specified directory name.

# -- Script configuration settings.

# The branch to build. Has to be at least OpenXT 6.
# Note: this branch will be used for *everything*.
#   The build will fail if one of the OpenXT repositories doesn't have it
#   To change just the OE branch, please edit oe/build.sh
BRANCH="master"

BUILD_ID=

BUILD_DIR=""

NO_OE=
NO_DEBIAN=
NO_CENTOS=
NO_WINDOWS=

THREADS=

# -- End of script configuration settings.

usage() {
    cat >&2 <<EOF
usage: $0 [-h] [-i ID] [-j threads] [-b branch] [-n build] [-O] [-D] [-C] [-W]
  -h: Help
  -i: Build ID (overrides -n)
  -j: Number of concurrent threads
  -b: Branch to build
  -n: Continue the specified build instead of creating a new one
  -O: Do not build OpenEmbedded (OpenXT core), not recommended
  -D: Do not build the Debian guest tools
  -C: Do not build the RPM tools and SyncXT
  -W: Do not build the Windows guest tools

 Note: if a container/VM didn't get setup, it will get skipped,
   even when not explicitely excluded
EOF
    exit $1
}

while getopts "hi:j:b:n:ODCW" opt; do
    case $opt in
        h)
            usage 0
            ;;
        i)
            BUILD_ID=${OPTARG}
            ;;
        j)
            THREADS=${OPTARG}
            ;;
        b)
            BRANCH="${OPTARG}"
            ;;
        n)
            BUILD_DIR="${OPTARG}"
            ;;
        O)
            NO_OE=1
            ;;
        D)
            NO_DEBIAN=1
            ;;
        C)
            NO_CENTOS=1
            ;;
        W)
            NO_WINDOWS=1
            ;;
        \?)
            usage 1
            ;;
    esac
done

CONTAINER_USER=%CONTAINER_USER%
SUBNET_PREFIX=%SUBNET_PREFIX%
BUILD_USER="$(whoami)"
BUILD_USER_ID="$(id -u ${BUILD_USER})"
BUILD_USER_HOME="$(eval echo ~${BUILD_USER})"
IP_C=$(( 150 + ${BUILD_USER_ID} % 100 ))
ALL_BUILDS_SUBDIR_NAME="xt-builds"
ALL_BUILDS_DIRECTORY="${BUILD_USER_HOME}/${ALL_BUILDS_SUBDIR_NAME}"

source version

mkdir -p $ALL_BUILDS_DIRECTORY

# If an ID was specified and the directory was not:
# if a directory with that name doesn't exist, use it;
# otherwise use the ID as the root of the build directory name.
if [ ! -z $BUILD_ID ] ; then
    [ -d "${ALL_BUILDS_DIRECTORY}/$BUILD_ID" ] || BUILD_DIR=$BUILD_ID
    BUILD_DIR_ROOT=$BUILD_ID
else
    # Use the build date as the default root for new build directories
    BUILD_DIR_ROOT=$(date +%y%m%d)
fi

# If no build directory was specified, create a new one.
if [ -z $BUILD_DIR ] ; then
    cd ${ALL_BUILDS_DIRECTORY}
    LAST_BUILD=0
    if [[ -d "${BUILD_DIR_ROOT}-1" ]]; then
        LAST_BUILD=`ls -dvr ${BUILD_DIR_ROOT}-* | head -1 | cut -d '-' -f 2`
    fi
    cd - >/dev/null
    NEW_BUILD=$((LAST_BUILD + 1))
    BUILD_DIR="${BUILD_DIR_ROOT}-${NEW_BUILD}"
fi

# If no ID was specified, use the build directory name.
if [ -z $BUILD_ID ]; then
    BUILD_ID=$BUILD_DIR
fi

BUILD_DIR_PATH="${ALL_BUILDS_DIRECTORY}/${BUILD_DIR}"
if [ -e "$BUILD_DIR_PATH" ] ; then
    echo "Build path is already present: ${BUILD_DIR_PATH}"
fi
if ! mkdir -p "${BUILD_DIR_PATH}" ; then
    echo "Error: Failed to create build directory: ${BUILD_DIR_PATH}" >&2
    exit 1
fi

echo "Fetching git mirrors..."
./fetch.sh > "${BUILD_DIR_PATH}/git_heads"
echo "Done"

echo "Running build: ${BUILD_DIR}"
mkdir -p "${BUILD_DIR_PATH}/raw"

build_container() {
    NUMBER=$1           # 01
    NAME=$2             # oe

    CONTAINER_IP="${SUBNET_PREFIX}.${IP_C}.1${NUMBER}"

    if [ -d $NAME ]; then
        echo "Building container $NUMBER : $NAME"
    else
        echo "Not building $NUMBER : $NAME"
        return
    fi

    # Build
    # Note: we cat all the layers and the build script to the ssh command
    #   Another approach could be to `source *.layer` here and send them to the
    #   container using the ssh option "SendEnv".
    #   The way we do it here, the shell will for example turn tabulations into
    #   completion requests, which is not ideal...
    cat *.layer $NAME/build.sh | \
        sed -e "s|\%BUILD_USER\%|${BUILD_USER}|" \
            -e "s|\%BUILD_DIR\%|${BUILD_DIR}|" \
            -e "s|\%SUBNET_PREFIX\%|${SUBNET_PREFIX}|" \
            -e "s|\%IP_C\%|${IP_C}|" \
            -e "s|\%BUILD_ID\%|${BUILD_ID}|" \
            -e "s|\%BRANCH\%|${BRANCH}|" \
            -e "s|\%THREADS\%|${THREADS}|" \
            -e "s|\%ALL_BUILDS_SUBDIR_NAME\%|${ALL_BUILDS_SUBDIR_NAME}|" |\
        ssh -i "${BUILD_USER_HOME}"/ssh-key/openxt \
            -oStrictHostKeyChecking=no ${CONTAINER_USER}@${CONTAINER_IP}
}

build_windows() {
    NUMBER=$1           # 04

    DEST="${ALL_BUILDS_SUBDIR_NAME}/${BUILD_DIR}/windows"

    if [ -d windows ]; then
        echo "Building the Windows tools"
    else
        echo "Not building the Windows tools"
        return
    fi

    mkdir -p $DEST

    # Build
    cd windows
    ./build.sh "$NUMBER" \
               "$BUILD_ID" \
               "$BRANCH" \
               "$BUILD_USER" \
               "${SUBNET_PREFIX}.${IP_C}" \
               "${DEST}"
    cd - >/dev/null
}

build_tools_iso() {
    WORKDIR="${ALL_BUILDS_DIRECTORY}/${BUILD_DIR}"

    cd $WORKDIR
    mkdir -p raw
    rm -rf iso_tmp
    mkdir -p iso_tmp/linux
    if [ -r windows/xctools-iso.zip ]; then
	unzip -q windows/xctools-iso.zip -d iso_tmp
    fi
    if [ -d debian ]; then
	ln -s ../../debian iso_tmp/linux/debian
    fi
    if [ -d rpms ]; then
	ln -s ../../rpms iso_tmp/linux/rpms
    fi
    echo "Creating xc-tools.iso..."
    genisoimage -o "raw/xc-tools.iso" \
		-R \
		-J \
		-joliet-long \
		-input-charset utf8 \
		-V "OpenXT-tools" \
		-f \
		-quiet \
		iso_tmp
    echo "Done"
    rm -rf iso_tmp
}

build_repository () {
    WORKDIR="${ALL_BUILDS_DIRECTORY}/${BUILD_DIR}"

    local repository="$WORKDIR/repository/packages.main"

    cat > manifest <<EOF
control tarbz2 required control.tar.bz2 /
dom0 ext3gz required dom0-rootfs.i686.xc.ext3.gz /
uivm vhdgz required uivm-rootfs.i686.xc.ext3.vhd.gz /storage/uivm
ndvm vhdgz required ndvm-rootfs.i686.xc.ext3.vhd.gz /storage/ndvm
syncvm vhdgz optional syncvm-rootfs.i686.xc.ext3.vhd.gz /storage/syncvm
file iso optional xc-tools.iso /storage/isos/xc-tools.iso
EOF

    echo "Creating the repository..."
    mkdir -p "$repository"
    echo -n > "$repository/XC-PACKAGES"

    # Format of the manifest file is
    # name format optional/required source_filename dest_path
    while read l; do
        local name=`echo "$l" | awk '{print $1}'`
        local format=`echo "$l" | awk '{print $2}'`
        local opt_req=`echo "$l" | awk '{print $3}'`
        local src=`echo "$l" | awk '{print $4}'`
        local dest=`echo "$l" | awk '{print $5}'`

        if [ ! -e "$WORKDIR/raw/$src" ] ; then
            if [ "$opt_req" = "required" ] ; then
                echo "Error: Required file $src is missing"
                exit 1
            fi

            echo "Optional file $src is missing: skipping"
            continue
        fi

        cp "$WORKDIR/raw/$src" "$repository/$src"

        local filesize=$( du -b $repository/$src | awk '{print $1}' )
        local sha256sum=$( sha256sum $repository/$src | awk '{print $1}' )

        echo "$name" "$filesize" "$sha256sum" "$format" \
             "$opt_req" "$src" "$dest" >> "${repository}/XC-PACKAGES"
    done < manifest

    PACKAGES_SHA256SUM=$(sha256sum "$repository/XC-PACKAGES" |
                                    awk '{print $1}')

    set +o pipefail #fragile part

    # Pad XC-REPOSITORY to 1 MB with blank lines. If this is changed, the
    # repository-signing process will also need to change.
    {
        cat <<EOF
xc:main
pack:Base Pack
product:OpenXT
build:${BUILD_ID}
version:${VERSION}
release:${RELEASE}
upgrade-from:${UPGRADEABLE_RELEASES}
packages:${PACKAGES_SHA256SUM}
EOF
        yes ""
    } | head -c 1048576 > "$repository/XC-REPOSITORY"

    set -o pipefail #end of fragile part

    openssl smime -sign \
            -aes256 \
            -binary \
            -in "$repository/XC-REPOSITORY" \
            -out "$repository/XC-SIGNATURE" \
            -outform PEM \
            -signer "$BUILD_USER_HOME/certificates/dev-cacert.pem" \
            -inkey "$BUILD_USER_HOME/certificates/dev-cakey.pem"
    echo "Done"
}

build_iso() {
    WORKDIR="${ALL_BUILDS_DIRECTORY}/${BUILD_DIR}"

    cd $WORKDIR
    mkdir -p iso
    rm -rf iso_tmp
    mkdir -p iso_tmp/isolinux
    cp -rf netboot/* iso_tmp/isolinux/
    cp -rf installer/iso/* iso_tmp/isolinux/
    ln -s ../repository/packages.main iso_tmp/packages.main
    ln -s ../../raw/installer-rootfs.i686.cpio.gz iso_tmp/isolinux/rootfs.gz
    sed -i -re "s|[$]OPENXT_VERSION|$VERSION|g" iso_tmp/isolinux/bootmsg.txt
    sed -i -re "s|[$]OPENXT_BUILD_ID|$BUILD_ID|g" iso_tmp/isolinux/bootmsg.txt

    echo "Creating installer.iso..."
    genisoimage -o "iso/installer.iso" \
                -b "isolinux/isolinux.bin" \
                -c "isolinux/boot.cat" \
                -no-emul-boot \
                -boot-load-size 4 \
                -boot-info-table \
                -r \
                -J \
                -l \
                -V "OpenXT-${VERSION}" \
		-f \
		-quiet \
                "iso_tmp"
    echo "Done"
    rm -rf iso_tmp
    isohybrid iso/installer.iso
    cd - > /dev/null
}

build_finalize() {
    WORKDIR="${ALL_BUILDS_DIRECTORY}/${BUILD_DIR}"

    cd $WORKDIR

    # Build info file (should be safe to remove)
    cat > info <<EOF
installer: iso/installer.iso
netboot: netboot
ota-update: update/update.tar
repository: repository
EOF

    # Build the update tarball
    mkdir -p "update"
    tar -C "repository" -cf "update/update.tar" packages.main

}

[ -z $NO_OE ]      && build_container "01" "oe"
[ -z $NO_DEBIAN ]  && build_container "02" "debian"
[ -z $NO_CENTOS ]  && build_container "03" "centos"
[ -z $NO_WINDOWS ] && build_windows   "04"

build_tools_iso
build_repository
build_iso
build_finalize
