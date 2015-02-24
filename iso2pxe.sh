#!/usr/bin/env bash
#  
# The MIT License (MIT)
# 
# Copyright (c) 2015 Assured Information Security, Inc.
# Author: Kyle J. Temkin <temkink@ainfosec.com>
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
# 

CONFIG_FILE=${HOME}/.config/openxt_scripts

#Get the path in which this script resides.
SCRIPT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

#If we have a configuration file, source it!
if [ -f $CONFIG_FILE ]; then
  . $CONFIG_FILE 
fi

#Extract our command-line arguments. If these aren't set,
#try to fall back to variables from the environment, which may
#have been set in our config_file.
ISO=${1:-installer.iso}
TFTP_ROOT=${2:-$TFTP_ROOT}
REPO_ROOT=${3:-$REPO_ROOT}

TFTP_TARGET="${TFTP_ROOT}/${ISO_PREFIX}"
REPO_TARGET="${REPO_ROOT}/${ISO_PREFIX}"

ISO_PREFIX=${ISO_PREFIX:-}

#
# Warn the user if they don't have 7zip installed.
#
if !(command -v 7z >/dev/null 2>&1); then
  echo "You will need 7zip installed to use this script. To install on Ubuntu/Debian"
  echo 
  echo "    sudo apt-get install p7zip"
  echo 
  echo "On Arch:"
  echo 
  echo "    sudo pacman -S p7zip"
  echo
  exit 1
fi

#
# If we don't have a proper set of arguments, print the usage and bail out.
#
if ! [ -f $ISO ]; then
  echo 
  echo "ISO to PXE target converter for OpenXT."
  echo "usage: $0 <installer.iso> <target_name> [tftp_root] [repo_root]" 
  echo
  exit 1
fi

#Ensure that our prefixed directories exist.
mkdir -p "${TFTP_TARGET}"
mkdir -p "${REPO_TARGET}"

#First, extract the core repository to the repository directory.
7z x -y "${ISO}" -o"${REPO_TARGET}" "packages.main" || exit 1

#Ensure that the repository directory is enumerable by everyone,
#(who can get to that path), including our web server.
chmod a+x "${REPO_TARGET}/packages.main" || exit 1

#Next, populate the TFTP...
7z e -y "${ISO}" -o"${TFTP_TARGET}" "isolinux" || exit 1

#... and /if empty/, remove the leftover isolinux directory.
rmdir "${TFTP_TARGET}/isolinux" 2>&1  > /dev/null

#Copy the answerfiles and PXE configuration to our TFTP root.
cp "${SCRIPT_DIR}"/targetfiles/* "$TFTP_TARGET"

#If we don't have a TFTP PATH set, stop here and let the user 
if [ x"$NETBOOT_URL" = x ]; then
    echo "-------------------"
    echo 
    echo "You'll need to set up the netboot/repository locations manually by editing pxelinux.cfg and your answer files."
    echo "You can automate this by setting up a configuration file. See the openxt_scripts.sample included with this script."
    echo
    exit 0
fi

TFTP_PATH_TARGET="${TFTP_PATH}${ISO_PREFIX}"
NETBOOT_URL_TARGET="${NETBOOT_URL}/${ISO_PREFIX}"

#And populate the variables held within.
for file in "$TFTP_TARGET"/*.cfg "$TFTP_TARGET"/*.ans; do
    sed -i "s!@ISO_PREFIX@!${ISO_PREFIX}!g"          $file
    sed -i "s!@TFTP_PATH@!${TFTP_PATH_TARGET}!g"     $file
    sed -i "s!@NETBOOT_URL@!${NETBOOT_URL_TARGET}!g" $file
    sed -i "s!@TFTP_IP@!${TFTP_IP}!g"                $file
done

#Finally, add a menu entry.
DATE=$(date +%F)
NAME=${ISO_PREFIX:-$DATE}

#If we have a path to a PXE configuration file, append a menu entry to it.
if [ x"$PXE_CONFIG" = "x" ]; then
    echo "-------------------"
    echo 
    echo "A netboot configuration has been written for you in \"${TFTP_TARGET}/pxelinux.cfg\"."
    echo "You'll need to include this to your core PXE configuration; for example, using:"
    echo 
    echo "MENU INCLUDE ${TFTP_PATH_TARGET}/pxelinux.cfg"
    echo 
    echo "You can automate this by setting up a configuration file. See the openxt_scripts.sample included with this script."
    echo
    exit 0
fi

#Ensure that the PXE configuration file exists.
touch ${PXE_CONFIG}

#And insert the menu contents into it!
cat <<EOF >> ${PXE_CONFIG}

MENU BEGIN OpenXT From ISO ($NAME) 
MENU TITLE OpenXT From ISO ($NAME)
  LABEL Previous
  MENU LABEL Previous Menu
  TEXT HELP
  Return to previous menu
  ENDTEXT
  MENU EXIT
  MENU SEPARATOR
EOF

echo -n "  MENU INCLUDE " >> ${PXE_CONFIG}

#If we have a prefix, include it as well
if ! [ x"$ISO_PREFIX" = x ]; then
    echo -n "${ISO_PREFIX}/" >> ${PXE_CONFIG}
fi

echo "pxelinux.cfg" >> ${PXE_CONFIG}
echo "MENU END" >> ${PXE_CONFIG}

