#!/bin/bash

# Warn before setup
echo "Before running this script be sure that:"
echo "- eth0 has an IP address (this is the network that will be used for IPA)"
echo "- the FQDN has been set"
echo "- the external/dhcp interfaces has PEERDNS=no in its ifcfg file"
read -p "Confirm these have been performed and continue? [y/N]" -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]] ; then
  echo "Exiting..."
  exit 0
fi

# Variables
REALM="$(hostname -d |tr a-z A-Z)"
DOMAIN="$(hostname -d)"
MACHINE_IP="$(ifconfig eth0 |grep 'inet ' |awk '{print $2}')"
REVERSE_ZONE="$(echo $MACHINE_IP |awk -F'.' 'BEGIN {OFS = FS} {print $2,$1}')"
MACHINE_NAME="$(hostname -f)"
MACHINE_IP_REVERSE="$(echo $MACHINE_IP |awk -F'.' 'BEGIN {OFS = FS} {print $4,$3}')"
PASSWORD="ReallySecureIPApassword"
DNS_FORWARDER="$(grep ^nameserver /etc/resolv.conf -m 1 |awk '{print $2}')"

cat << EOF > /root/ipa.txt
SECUREPASS=$PASSWORD
EOF

# Install packages
yum -y install ipa-server bind bind-dyndb-ldap ipa-server-dns

# Server setup
ipa-server-install -a $PASSWORD --hostname $MACHINE_NAME --ip-address=$MACHINE_IP -r "$REALM" -p $PASSWORD -n "$DOMAIN" --no-ntp --setup-dns --forwarder="$DNS_FORWARDER" --reverse-zone="$REVERSE_ZONE.in-addr.arpa." --ssh-trust-dns --unattended

if [[ $? != 0 ]] ; then
  echo "IPA install failed!!!"
  echo "Exiting..."
  exit 1
fi

# Auth
echo $PASSWORD |kinit admin

# Add user config (home dir, shell, groups)
ipa config-mod --defaultshell /bin/bash
ipa group-add ClusterUsers --desc="Generic Cluster Users"
ipa group-add AdminUsers --desc="Admin Cluster Users"
ipa config-mod --defaultgroup ClusterUsers
ipa pwpolicy-mod --maxlife=999

# Host groups
ipa hostgroup-add usernodes --desc "All nodes allowing standard user access"
ipa hostgroup-add adminnodes --desc "All nodes allowing only admin user access"

# Add alces user
ipa user-add alces-cluster --first Alces --last Software --random
ipa group-add-member AdminUsers --users alces-cluster

# Access rules
ipa hbacrule-disable allow_all
ipa hbacrule-add siteaccess --desc "Allow admin access to admin hosts"
ipa hbacrule-add useraccess --desc "Allow user access to user hosts"
ipa hbacrule-add-service siteaccess --hbacsvcs sshd
ipa hbacrule-add-service useraccess --hbacsvcs sshd
ipa hbacrule-add-user siteaccess --groups AdminUsers
ipa hbacrule-add-user useraccess --groups ClusterUsers
ipa hbacrule-add-host siteaccess --hostgroups adminnodes
ipa hbacrule-add-host useraccess --hostgroups usernodes

# Sudo rules
ipa sudorule-add --cmdcat=all All
ipa sudorule-add-user --groups=adminusers All
ipa sudorule-mod All --hostcat='all'
ipa sudorule-add-option All --sudooption '!authenticate'

#Site stuff
ipa user-add siteadmin --first Site --last Admin --random
ipa group-add siteadmins --desc="Site admin users (power users)"
ipa hostgroup-add sitenodes --desc "All nodes allowing site admin access"
ipa group-add-member siteadmins --users siteadmin
ipa hbacrule-add siteaccess --desc "Allow siteadmins access to site hosts"
ipa hbacrule-add-service siteaccess --hbacsvcs sshd
ipa hbacrule-add-user siteaccess --groups siteadmins
ipa hbacrule-add-host siteaccess --hostgroups sitenodes
ipa hbacrule-add-service useraccess --hbacsvcgroups=Sudo
ipa hbacrule-add-service siteaccess --hbacsvcgroups=Sudo

ipa sudorule-add --cmdcat=all Site
ipa sudorule-add-user --groups=siteadmins Site
ipa sudorule-mod Site --hostcat=''
ipa sudorule-add-option Site --sudooption '!authenticate'
ipa sudorule-add-host Site --hostgroups=sitenodes

# Update name resolution
cat << EOF > /etc/resolv.conf
search $DOMAIN
nameserver $MACHINE_IP
EOF

# Fix DNS forwarding issues
sed -i 's/dnssec-validation yes/dnssec-validation no/g' /etc/named.conf

# Reboot
echo "It is recommended to reboot the system now that IPA has been configured"
