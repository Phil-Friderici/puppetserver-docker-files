FROM ubuntu:16.04

ARG vcs_ref
ARG build_date
ENV PUPPET_SERVER_VERSION="5.3.1"
ENV PUPPETDB_TERMINUS_VERSION="5.2.2"
ENV DUMB_INIT_VERSION="1.2.1"
ENV UBUNTU_CODENAME="xenial"
ENV PUPPETSERVER_JAVA_ARGS="-Xms256m -Xmx256m"
ENV PATH=/opt/puppetlabs/server/bin:/opt/puppetlabs/puppet/bin:/opt/puppetlabs/bin:$PATH
ENV PUPPET_HEALTHCHECK_ENVIRONMENT="production"


LABEL org.label-schema.maintainer="Puppet Release Team <release@puppet.com>" \
      org.label-schema.vendor="Puppet" \
      org.label-schema.url="https://github.com/puppetlabs/puppetserver" \
      org.label-schema.name="Puppet Server" \
      org.label-schema.license="Apache-2.0" \
      org.label-schema.version=$PUPPET_SERVER_VERSION \
      org.label-schema.vcs-url="https://github.com/puppetlabs/puppetserver" \
      org.label-schema.vcs-ref=$vcs_ref \
      org.label-schema.build-date=$build_date \
      org.label-schema.schema-version="1.0" \
      org.label-schema.dockerfile="/Dockerfile"

RUN apt-get update && \
    apt-get install -y wget=1.17.1-1ubuntu1 && \
    wget https://apt.puppetlabs.com/puppet5-release-"$UBUNTU_CODENAME".deb && \
    wget https://github.com/Yelp/dumb-init/releases/download/v"$DUMB_INIT_VERSION"/dumb-init_"$DUMB_INIT_VERSION"_amd64.deb && \
    dpkg -i puppet5-release-"$UBUNTU_CODENAME".deb && \
    dpkg -i dumb-init_"$DUMB_INIT_VERSION"_amd64.deb && \
    rm puppet5-release-"$UBUNTU_CODENAME".deb dumb-init_"$DUMB_INIT_VERSION"_amd64.deb && \
    apt-get update && \
    apt-get install --no-install-recommends git -y puppetserver="$PUPPET_SERVER_VERSION"-1"$UBUNTU_CODENAME" && \
    apt-get install --no-install-recommends -y puppetdb-termini="$PUPPETDB_TERMINUS_VERSION"-1xenial && \
    apt-get install -y telnet vim iputils-ping netcat && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    gem install --no-rdoc --no-ri r10k

# Add configuration files into the image
COPY config/puppetserver /etc/default/puppetserver
COPY config/logback.xml /etc/puppetlabs/puppetserver/
COPY config/puppetserver.conf /etc/puppetlabs/puppetserver/conf.d/
COPY config/request-logging.xml /etc/puppetlabs/puppetserver/

COPY config/puppet.conf /etc/puppetlabs/puppet/



#The below line was moved to docker-entrypoint.sh
#RUN puppet config set autosign true --section master

##PuppetDB configs. Taken from Puppetserver Dockerfile
RUN puppet config set storeconfigs_backend puppetdb --section main && \
    puppet config set storeconfigs true --section main && \
    puppet config set reports puppetdb --section main && \
    cp -pr /etc/puppetlabs/puppet /var/tmp && \
    rm -rf /var/tmp/puppet/ssl

#COPY config/puppetdb.conf /etc/puppetlabs/puppet/
COPY config/puppetdb.conf /var/tmp/puppet/




COPY docker-entrypoint.sh /

EXPOSE 8140

ENTRYPOINT ["dumb-init", "/docker-entrypoint.sh"]
CMD ["foreground" ]


HEALTHCHECK --interval=10s --timeout=10s --retries=90 CMD \
  hostname=$(puppet config print certname) && \
  curl --fail -H 'Accept: pson' \
  --resolve "${hostname}:8140:127.0.0.1" \
  --cert   $(puppet config print hostcert) \
  --key    $(puppet config print hostprivkey) \
  --cacert $(puppet config print localcacert) \
  https://${hostname}:8140/${PUPPET_HEALTHCHECK_ENVIRONMENT}/status/test \
  |  grep -q '"is_alive":true' \
  || exit 1

COPY Dockerfile /
