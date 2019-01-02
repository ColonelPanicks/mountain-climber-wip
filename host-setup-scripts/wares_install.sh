#!/bin/bash

DATE=$(date +%Y%m%d)

UNDERWARE_VERSION="${UNDERWARE_VERSION:-0.4.0}"
METALWARE_VERSION="${METALWARE_VERSION:-develop}"
CLOUDWARE_VERSION="${CLOUDWARE_VERSION:-2019.1.0.rc1}"
ADMINWARE_VERSION="${ADMINWARE_VERSION:-2018.2.0}"
USERWARE_VERSION="${USERWARE_VERSION:-feature/advanced-mode}"

#
# Functions
#

function tidy_up() {
  WARE=$1
  [ -d /opt/$WARE ] && mv /opt/$WARE /opt/$DATE-$WARE
  [ -d /var/lib/$WARE ] && mv /var/lib/$WARE /var/lib/$DATE-$WARE
}

function install_underware() {
  curl -sL https://raw.githubusercontent.com/alces-software/underware/master/scripts/bootstrap?installer/ | alces_OS=el7 alces_SOURCE_BRANCH=$UNDERWARE_VERSION /bin/bash
  mkdir -p /var/lib/underware/repo/{config,genders}

  if cd /root/mountain-climber-wip ; then
    git pull
  else
    git clone https://github.com/ColonelPanicks/mountain-climber-wip/ /root/mountain-climber-wip/
  fi
}

function install_metalware() {
  curl -sL https://raw.githubusercontent.com/alces-software/metalware/master/scripts/bootstrap?installer | alces_OS=el7 alces_SOURCE_BRANCH=$METALWARE_VERSION /bin/bash

}

function install_cloudware() {
  cd /opt/
  git clone https://github.com/alces-software/cloudware
  cd cloudware
  git checkout $CLOUDWARE_VERSION
  cat << EOF
===============================================================

There are still some additional things that require setting
up in order to get full functionality:

- Install a version of Ruby that supports Cloudware (most
  likely using RVM)
- Run 'bundle install' in /opt/cloudware/ to prepare the
  program

===============================================================
EOF
}

function install_adminware() {
  cd /opt
  git clone https://github.com/alces-software/adminware.git
  cd adminware
  git checkout $ADMINWARE_VERSION
  cd /opt/adminware/bin
  curl https://s3-eu-west-1.amazonaws.com/flightconnector/adminware/resources/sandbox-starter > sandbox-starter

  install_branding

  cat << EOF
===============================================================

There are still some additional things that require setting
up in order to get full functionality:

- Creation of clusteradmin user for adminware sandbox

===============================================================
EOF
}

function install_userware() {
  echo "checking for existing userware"
  [ -d /opt/directory ] && mv /opt/directory /opt/$DATE-directory
  [ -d /opt/share ] && mv /opt/share /opt/$DATE-share
  [ -d /tmp/userware ] && rm -rf /tmp/userware

  git clone https://github.com/alces-software/userware /tmp/userware
  cd /tmp/userware
  git checkout $USERWARE_VERSION
  rsync -auv /tmp/userware/{directory,share} /opt/
  cd /opt/directory/cli
  make setup
  echo "cw_ACCESS_fqdn=$(hostname -f)" > /opt/directory/etc/access.rc
  mkdir -p /var/www/html/secure

  install_branding

  cat << EOF
===============================================================

There are still some additional things that require setting
up in order to get full functionality:

- IPAPASSWORD=MyIPApassHere into /opt/directory/etc/config
- Creation of useradmin user for userware sandbox

===============================================================
EOF
}

function install_branding() {
  mkdir -p /opt/flight/bin
  cd /opt/flight/bin
  # Download resources/banner from this repo.
  curl https://s3-eu-west-1.amazonaws.com/flightconnector/directory/resources/banner > banner
  chmod 755 banner
}

function tidy_and_install() {
  WARE=$1
  echo "Installing $WARE"
  if [[ $WARE != "userware" ]] ; then
    tidy_up $WARE
  fi
  install_$WARE
}

#
# Run it
#

INSTALL=$1

case $INSTALL in
  "underware"|"metalware"|"cloudware"|"adminware"|"userware")
  tidy_and_install $INSTALL
  ;;
  "")
  echo "Installing Underware, Metalware, Cloudware, Adminware and Userware"
  for i in underware metalware cloudware adminware userware ; do
    tidy_and_install $INSTALL
  done
  ;;
  *)
  echo "Invalid argument, installing nothing"
  ;;
esac

