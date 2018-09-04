#!/bin/bash

chown -R puppet:puppet /etc/puppetlabs/puppet/ssl
chown -R puppet:puppet /opt/puppetlabs/server/data/puppetserver/

if test -n "${PUPPETDB_SERVER_URLS}" ; then
  sed -i "s@^server_urls.*@server_urls = ${PUPPETDB_SERVER_URLS}@" /etc/puppetlabs/puppet/puppetdb.conf
fi

# Configure dns_alt_names if provided in compose yaml file
# Value like DNS_ALT_NAMES=puppet1.fqdn,puppet2.fwdn,puppet3.fqdn
if test -n "${DNS_ALT_NAMES}" ; then
  puppet config set dns_alt_names "$DNS_ALT_NAMES" --section main
fi


# Configure CA server
# Inheritance of environment variable by stack deployment remote client from host seems not supported.
# Use fqdn hostname to specify CA servers. 
# MUST provide at least one CA_SERVER
# if test -n "${CA_SERVER}" ; then
if [ -n "${CA_SERVER}" ] || [  -n "${CA_SERVER1}" ] || [ -n "${CA_SERVER2}" ] ; then

  if [  -n "$CA_SERVER" ]; then
    CA_SERVER=${CA_SERVER}

  elif [ -n "${CA_SERVER1}" ]; then

    CA_SERVER=${CA_SERVER1}
  else
    CA_SERVER=${CA_SERVER2} 
  fi

else
echo "CA_SERVER is mandatory in docker-compose.yml\n"
echo "Exiting!! \n"
exit
fi

HOSTNAME=`hostname -f`

if [ "${HOSTNAME}" = "$CA_SERVER" ] || [ "${HOSTNAME}" = "$CA_SERVER1" ] || [ "${HOSTNAME}" = "$CA_SERVER2" ]; then

# Configure puppet to use a certificate autosign script (if it exists)
# AUTOSIGN=true|false|path_to_autosign.conf
  if test -n "${AUTOSIGN}" ; then
    puppet config set autosign "$AUTOSIGN" --section master
  fi
else
# Configs for non-CA Puppet masters
puppet config set CA false --section master
puppet config set server ${CA_SERVER} --section agent
puppet config set ca_server ${CA_SERVER} --section main
  if test -n "${CA_PORT}" ; then
    puppet config set ca_port ${CA_PORT} --section main
  else
  CA_PORT=8140
  fi

# Disable local CA
sed -i -e 's@^\(puppetlabs.services.ca.certificate-authority-service/certificate-authority-service\)@# \1@' -e 's@.*\(puppetlabs.services.ca.certificate-authority-disabled-service/certificate-authority-disabled-service\)@\1@' /etc/puppetlabs/puppetserver/services.d/ca.cfg

#Generate SSL certificates. Will need manual signing
# But first wait for CA server to be ready
while ! nc -z "$CA_SERVER" $CA_PORT; do
sleep 1
done

puppet agent -t --noop 


# Workaround fix on non-ca Puppetmasters. Default ssl-crl-path=/etc/puppetlabs/puppet/ssl/ca/ca_crl.pem
  if [ ! -d "/etc/puppetlabs/puppet/ssl/ca" ]; then
    mkdir /etc/puppetlabs/puppet/ssl/ca
    ln -s /etc/puppetlabs/puppet/ssl/crl.pem /etc/puppetlabs/puppet/ssl/ca/ca_crl.pem
  fi


fi

exec /opt/puppetlabs/bin/puppetserver "$@"
