# Octopus K8s Vagrant Box

This project creates a VM using Vagrant that:

* Runs a local copy of Kubernetes
* Installs the Octopus K8s Agent
* Installs Argo CD
* Installs an Octopus Argo agent
* Adds a sample Argo application using the Mock Git Repo

## Prerequisites

You need an access token to your Octopus instance.

Install the [Access Token Chrome Extension](https://github.com/mcasperson/AccessTokenChromeExtension) to easily generate Octopus access tokens.

## Running

```bash
OCTOPUS_TEMPK8S_GRPC_HOSTNAME=mattc.octopus.app:8443 \
OCTOPUS_TEMPK8S_HOSTNAME=mattc.octopus.app \
OCTOPUS_TEMPK8S_POLLING_HOSTNAME=polling.mattc.octopus.app \
OCTOPUS_TEMPK8S_SPACE=Scratchpad \
OCTOPUS_TEMPK8S_SPACE_ID=Spaces-### \
OCTOPUS_TEMPK8S_BEARER_TOKEN=token \
vagrant up
```

This must be run as Administrator in Windows:

```powershell
$env:OCTOPUS_TEMPK8S_GRPC_HOSTNAME="mattc.octopus.app:8443"
$env:OCTOPUS_TEMPK8S_HOSTNAME="mattc.octopus.app"
$env:OCTOPUS_TEMPK8S_POLLING_HOSTNAME="polling.mattc.octopus.app"
$env:OCTOPUS_TEMPK8S_SPACE="Scratchpad"
$env:OCTOPUS_TEMPK8S_SPACE_ID="Spaces-###"
$env:OCTOPUS_TEMPK8S_BEARER_TOKEN="token"
vagrant up --provider=hyperv
```

If you have more than one Virtual Switch, you will be prompted for which one to use when vagrant starts.