#!/bin/bash

chown -R puppet:puppet /etc/puppetlabs/puppet/
chown -R puppet:puppet /opt/puppetlabs/server/data/puppetserver/

# During build, pristine config files get copied to this directory. If
# they are not in the current container, use these templates as the
# default
TEMPLATES=/var/tmp/puppet

cd /etc/puppetlabs/puppet
for f in auth.conf hiera.yaml puppet.conf puppetdb.conf
do
    if ! test -f $f ; then
        cp -p $TEMPLATES/$f .
    fi
done
cd /

if test -n "${PUPPETDB_SERVER_URLS}" ; then
  sed -i "s@^server_urls.*@server_urls = ${PUPPETDB_SERVER_URLS}@" /etc/puppetlabs/puppet/puppetdb.conf
fi

if test -n "${PUPPETSERVER_HOSTNAME}"; then
  /opt/puppetlabs/bin/puppet config set certname "$PUPPETSERVER_HOSTNAME"
  /opt/puppetlabs/bin/puppet config set server "$PUPPETSERVER_HOSTNAME"
fi


#Set Puppet ENVIRONMENT in the stack yaml file: SERVER_ENVIRONMENT
# Maybe faster to use special environment without modules for builds
if test -n "${SERVER_ENVIRONMENT}" ; then
  SERVER_ENVIRONMENT="${SERVER_ENVIRONMENT}"
else
  SERVER_ENVIRONMENT="production"  # default environment
fi

# Set modulepath if provided
if test -n "${BASEMODULEPATH}" ; then
  puppet config set basemodulepath "${BASEMODULEPATH}" --section main
fi

# Allow setting the dns_alt_names for the server's certificate. This
# setting will only have an effect when the container is started without
# an existing certificate on the /etc/puppetlabs/puppet volume
if test -n "${DNS_ALT_NAMES}"; then
    fqdn=$(facter fqdn)
    if test ! -f "/etc/puppetlabs/puppet/ssl/certs/$fqdn.pem" ; then
        #puppet config set dns_alt_names "${DNS_ALT_NAMES}" --section master
        puppet config set dns_alt_names "${DNS_ALT_NAMES}" --section main
    else
        actual=$(puppet config print dns_alt_names --section master)
        if test "${DNS_ALT_NAMES}" != "${actual}" ; then
            echo "Warning: DNS_ALT_NAMES has been changed from the value in puppet.conf"
            echo "         Remove/revoke the old certificate for this to become effective"
        fi
    fi
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

  
  # Configure CA_SERVER as main Puppet server for all Puppet masters
  puppet config set server ${CA_SERVER} --section agent

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

puppet agent -t --noop --environment=$SERVER_ENVIRONMENT --server=$CA_SERVER

fi



# Workaround fix on non-ca Puppetmasters. Default ssl-crl-path=/etc/puppetlabs/puppet/ssl/ca/ca_crl.pem
  if [ ! -d "/etc/puppetlabs/puppet/ssl/ca" ]; then
    mkdir /etc/puppetlabs/puppet/ssl/ca
    ln -s /etc/puppetlabs/puppet/ssl/crl.pem /etc/puppetlabs/puppet/ssl/ca/ca_crl.pem
  fi

#Add cron
if test -n "${CRON_ENTRY}"; then
echo "${CRON_ENTRY}" >> /var/spool/cron/crontabs/root
# Seems like empty line needed
echo "" >> /var/spool/cron/crontabs/root
service cron restart
fi


ln -s /etc/puppetlabs/code/auth.conf /etc/puppetlabs/puppet/auth.conf
ln -s /etc/puppetlabs/code/fileserver.conf /etc/puppetlabs/puppet/fileserver.conf


exec /opt/puppetlabs/bin/puppetserver "$@"
