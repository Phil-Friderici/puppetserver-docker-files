# Puppetserver-docker-files

This repo contains Docker Puppetserver images that are customized from the Puppetlabs' images (acknowledgement).
They can be used to setup a complete Puppetserver stack with all the components

# Setup guidelines

## 1. Prepare the hosts:


### 1.1. Ensure hostname command returns fqdn
```
check /etc/hosts & /etc/hostname
 &
reboot 
```
or
```
hostnamectl set-hostname hostname.fqdn
```
 
### 1.2. Install latest versions of docker

docker-ce-18.03.1.ce-1.el7.centos.x86_64

```
curl -SsL https://download.docker.com/linux/centos/docker-ce.repo -o /etc/yum.repos.d/docker-ce.repo
```

To install
```
yum --showduplicates list docker-ce
yum install -y docker-ce-18.03.1.ce-1.el7.centos.x86_64

enable/start docker
systemctl enable docker
systemctl start docker
```


### 1.3. initialize swarm enviornment in case Swarm environments are not already prepared.

Choose a system that will be a swarm manager (For redudancy and in production we shall have more than one swarm managers per swarm

```
docker swarm init
```

A swarm join token is gererated that can be used to join the other docker nodes to this swarm.

To recall the swarm token, run the following command:

```
docker swarm join-token worker
```

For our case, we shall have 2 separate SWARM environments
a. for PuppetCA
b. For the rest of the components including Puppet Compile masters and PuppetDB & PostgreSQL services

This is in order to separate PuppetCA traffic, from Puppet Compile Masters Traffic. 
Each service port is published to all swarm nodes by default, and that would make it impossible to separate PuppetCA and Compile Master's traffic.



Join the nodes to the docker swarm by running the previous command from Swarm manager.

```
docker swarm join --token SWMTKN-1-30sry8s4phyospw192bax9l9scri60pvtktjoplhbm1qq520sl-1ndd7z3h31kaob9nlqsxqbaoq 111.111.111.100:2377
```



# 2. Docker images

This step is only needed if using Custom build images. Otherwise docker images can be downloaed directly from Internet.

For now, the Puppetlabs' images seem to lack some configuration options that are necessary for our deployment. They are undergoing rapid enhancements and hopefully soon we would not need local customizations.

a. One such shortcoming is that each Puppetserver instance instantiates a Puppetca.
b. Puppetserver health check seems to be tied to the hostname "puppet". Send PR, and this is now fixed in upstream images



Good thing is that we can use Puppetlabs Dockerfile as a template to add our changes/ enhancements.


Adapt the Dockerfile to suit your requirements.

Build the adapted images, by changing into the directory containing Dockerfile.
Customised Build files are found in this directory (puppetserver & puppetdb)

such as (puppetserver)

```
cd /PATH/puppetserver-docker-files/puppetserver/docker/puppetserver
```

And run the following command, providing a tag to refer to the image

```
docker build -t puppet/puppetserver1-local .
```


Puppetdb

Puppetlabs puppetdb and postgresql docker images can be used directly without any customization
Latest version is 6.0.x , but a specific image version can be selected by specifying the image version such as

image: puppet/puppetdb:5.2.4




You then need to push these images to a registry server for easy access during stack deployment. Could be pushed to Internet registry, or local registry. In case local registry server is not available, please see the next step (3).

such as
Puppetserver image

```
docker tag puppet/puppetserver-local docker-registry.fqdn:5000/puppet/puppetserver-local
docker push docker-registry.fqdn:5000/puppet/puppetserver-local
```



# 3. Setup local registry server:

This step is not needed when using Internet docker images, such as from Puppetlabs. only necessary when using own customized local images.

Customized images could also be stripped of proprietary info and pushed to the public Internet registry.
 

Internal registry would be used. So this step is not necessary

## 3.1. For the swarm setup, images have to come from a central registry.

To create a local registry run the following command that will also start the registry automatically.



```
docker run -d -p 5000:5000 --restart=always --name registry registry:2
```

This is important If you want to use the registry as part of your permanent infrastructure, and sets it to restart automatically when Docker restarts or if it exits.
This example uses the --restart always flag to set a restart policy for the registry.


For one time registry service
```
docker service create --name registry --publish published=5000,target=5000 registry:2
```
This way, images can be pushed to localhost:5000

Registry is only useful if it can also be used across network. A registry can be created to be used with fqdn:5000/
And this requires SSL certificates to be setup on the Registry / and also on nodes.


## 3.2 Registry SSL certificate setup.

Configure TLS
 
Create Self-signed SSL certificates or use certificates provided by external CA
In our case, we could use PuppetCA signed certificates

domain.cert = registry.fqdn.cert found in $ssldir/certs/registry.fqdn.pem
domain.key  = registry.fqdn.private key in $ssldir/private_keys/registry.fqdn.pem

### 3.2.1. Create a Self Signed Certificate
You need to create a self signed certificate on your server to use it for the private Docker Registry.

```
mkdir registry_certs
openssl req -newkey rsa:4096 -nodes -sha256 \
        -keyout registry_certs/domain.key -x509 -days 356 \
        -out registry_certs/domain.cert
ls registry_certs/
```

Finally you have two files:

domain.cert  this file can be copied to the client using the private registry
domain.key  this is the private key which is necessary to run the private registry with TLS

### 3.2.2. Run the Private Docker Registry with TLS
Now we can start the registry with the local domain certificate and key file:

```
docker run -d -p 5000:5000 \
                -v $(pwd)/registry_certs:/certs \
                -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.cert \
                -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key \
                --restart=always --name registry registry:2
```


Now you can push your local image into the new registry after tagging it:

```
docker tag puppet/puppetserver-local docker-registry.fqdn:5000/puppet/puppetserver-local
docker push docker-registry.fqdn:5000/puppet/puppetserver-local
```



## 3.3. Access the Remote Registry form a remote node
Now as the private registry is started with TLS Support you can access the registry from any client which has the domain certificate. Therefor the certificate file domain.cert must be located on the client in a file

/etc/docker/certs.d/<registry_address>/ca.cert
Where <registry_address> is the server host name. After the certificate was updated you need to restart the local docker daemon:

```
mkdir -p /etc/docker/certs.d/docker.registry.fqdn:5000
cp domain.cert /etc/docker/certs.d/docker.registry.fqdn:5000/ca.crt
cp domain.cert /etc/docker/certs.d/docker.registry.fqdn:5000/domain.cert
cp domain.key /etc/docker/certs.d/docker.registry.fqdn:5000/domain.key


service docker restart
```

Now finally you can pull your images from the new private registry:

```
docker pull docker-registry.fqdn:5000/puppet/puppetserver-local
```




## 3.4. For secure networks/ Testing, we can skip SSL certificate setup by configuring an insecure registry as below.

Configure the following files on each swarm node that will pull docker images from the named registry server.



/etc/docker/daemon.json
{
"insecure-registries" : ["docker-registry.fqdn:5000"]
}


This allows images to be downloaded from the Private/internal registry.
To test on one of the swarm nodes:

```
docker pull docker-registry.fqdn:5000/puppet/puppetserver-local
```



# 4. docker-compose.yml

In this directory there's also a sample full stack docker-compose.yml
Please adapt it accordingly to fix the image names and node.label servers

NOTE: YOU MUST set CA_SERVER environment variable in puppet-docker service section

Note: this assumes the Docker swarm environment is already created.
If not,then please create the swarm as shown in 3.


Ensure labels are configured on container hosts appropriately because they are used in the docker-compose.yml file.


## 1. Add labels to Swarm nodes:
Run these commands on the swarm manager hosts.

```
docker node update --label-add type=puppetdb1_node <Node ID>
e.g.
docker node update --label-add type=fqdn_puppetdb_primary ja3c57gxcso6awtlp4obenih9
```

## 2. deploy the full stack with the following command

### Deploy PuppetCA
Puppet compile masters depend on availability of PuppetCA

```
$ docker stack deploy -c docker-compose.yml <stack-name>
such as
$ docker stack deploy -c docker-compose_ca.yml puppet
```




### Deploy Puppet Compile masters
When all the PuppetCA containers show health status, then you can deploy the rest of the Puppet compile master containers

```
docker stack deploy -c docker-compose.yml puppet
```

This has been tested to work with

Docker version 18.03.1-ce

See the stack services status on Swarm manager:

```
docker stack ps puppet

and on each node you can check the running service

docker ps
```



# 3. Sign Compile master SSL certificates

(For Puppet version 6, there's an option that allows automatic signing of certificates with alternate dns names)

/etc/puppetlabs/puppetserver/conf.d/puppetserver.conf

## settings related to the certificate authority
certificate-authority: {
    # allow CA to sign certificate requests that have subject alternative names.
    # allow-subject-alt-names: false
    allow-subject-alt-names: true


For deployment of Puppet Compile master servers for the first time, certificates need to be manually signed after running the above command to allow alternate dns names. Then
subsequent docker stack deploy would reuse the same certificates. We could automate these steps in future.

To sign certificates for Compile masters:

Run the following command on puppet ca container

```
docker ps
docker exec -it <puppetca-id-from-above>

and

puppet cert sign --allow-dns-alt-names <puppet1.fqdn>
```

In case a docker container fails, or to see progress check logs

```
docker ps
docker logs -f <container-id>
```


# Extra notes

https://medium.com/@gauravsj9/how-to-install-specific-docker-version-on-linux-machine-d0ec2d4095

Add labels to Swarm nodes:

This allows restricting docker containers on specific nodes. Useful for SSL certificates etc.

```
docker node update --label-add type=puppetdb1_node <Node ID>
docker node update --label-add type=fqdn_puppetdb_primary ja3c57gxcso6awtlp4obenih9
```
 
Use intuitive label_name. 
Node ID can be found from 1st column in the output of "docker node ls" command on the swarm manager.


## What's next

Improve Traefik setup


Check from the design document about setting up Floating IP FLIP on Swarm masters for HA
