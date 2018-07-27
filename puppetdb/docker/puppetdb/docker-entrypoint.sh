#!/bin/bash

# Clean up ssl certs to allow new certs
# Clean up not needed for fixed container names
#rm -rf /etc/puppetlabs/puppet/ssl/*
#rm -rf /etc/puppetlabs/puppetdb/ssl/*
#if [ ! -d "/etc/puppetlabs/puppetdb/ssl/certs" ]; then

#Set Puppet server in the stack yaml file, such as PUPPET_SERVER
if test -n "${CA_SERVER}" ; then
  CA_SERVER="${CA_SERVER}"
else
  CA_SERVER="puppet"  # default puppet server
fi

# In case Different port willl be needed. For now will use standard port
#Set Puppetca port in the stack, such as CA_PORT
if test -z ${CA_PORT} ; then
  CA_PORT="8140"
else
  CA_PORT="$CA_PORT"
fi

if [ ! -d "/etc/puppetlabs/puppetdb/ssl" ]; then
  while ! nc -z "$CA_SERVER" $CA_PORT; do
  #while ! nc -z puppet 8140; do
    sleep 1
  done
  set -e
  /opt/puppetlabs/bin/puppet config set certname "$HOSTNAME"
  /opt/puppetlabs/bin/puppet agent --verbose --onetime --no-daemonize --waitforcert 120 --server="$CA_SERVER" --masterport=$CA_PORT --ca_port=$CA_PORT
  /opt/puppetlabs/server/bin/puppetdb ssl-setup -f
fi

exec /opt/puppetlabs/server/bin/puppetdb "$@"
