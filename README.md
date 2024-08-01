[![MIT License](https://img.shields.io/github/license/bcgov/quickstart-openshift.svg)](/LICENSE.md)
[![Lifecycle](https://img.shields.io/badge/Lifecycle-Experimental-339999)](https://github.com/bcgov/repomountie/blob/master/doc/lifecycle-badges.md)

[![Merge](https://github.com/bcgov/quickstart-openshift/actions/workflows/merge.yml/badge.svg)](https://github.com/bcgov/quickstart-openshift/actions/workflows/merge.yml)
[![Analysis](https://github.com/bcgov/quickstart-openshift/actions/workflows/analysis.yml/badge.svg)](https://github.com/bcgov/quickstart-openshift/actions/workflows/analysis.yml)
[![Scheduled](https://github.com/bcgov/quickstart-openshift/actions/workflows/scheduled.yml/badge.svg)](https://github.com/bcgov/quickstart-openshift/actions/workflows/scheduled.yml)


# River Forecast Centre Postgres Analytical Database

Using the quickstart openshift template, this repository contains a pull request based
deployment pipeline for configuration and setup of a hydrological analytical database.

This is a work in progress, and is in early days for development.

Initially its attempting to implement similar functionality as the [Yukon Governments 
github repo](https://github.com/YukonWRB/AquaCache)


# Functionality Overview

Includes:

* docker-compose file for setting up an environment locally for development.
* pull request pipeline with dev/test deployments

# Requirements

1. Windows subsystem for linux, ideally running ubuntu
1. Docker and Docker compose
1. Openshift cli tools
1. Access to an openshift namespace

[A link to how I configure WSL / Docker / Docker compose](https://gist.github.com/franTarkenton/3a290442e13189908a959d942a172db3#install-docker), don't bother with 
the brew or anything other than WSL / Docker / Docker comose sections

The openshift CLI tools can be downloaded from the [openshift console](https://console.apps.silver.devops.gov.bc.ca), then go to the `?` icon at the top right, and select 
the option `command line tools`

[Access to openshift](https://just-ask.developer.gov.bc.ca/)

Other optional installs that are likely to help:
1. VSCode
1. VSCode docker extension

# Local Development

Create the database and run the migrations:

`docker compose up migrations`

Once the command has completed, you should be able to connect to the database using the credentals
described in the docker-compose.yaml file.

The docker compose will create a postgres database, and run the migrations using flyway.

Migration files are stored in the directory: /migrations/sql

To add more migrations simply follow the naming convention.  V<number>__<description>.sql
Note: there are two underscore characters between number and description.


# Working with the 'Dev' deployed version

1. go to [openshift web app](https://console.apps.silver.devops.gov.bc.ca/) and login
1. authenticate your cli by clicking your username icon at the top right corner and selecting `copy login command`
1. having copied the login command, paste it into a wsl terminal to authenticate
1. make sure you are in the correct namespace
    `oc projects`
1. list the running pods
    `oc get pods`
1. create a ssl tunnel to the openshift database
    `oc port-forward <pod with bitnami-pg name in it> <localport>:<remote port>`

    usually I change the local port to something like 5433 in case i already have a 
    postgres instance running via docker compose on port 5432.  In this scenario the 
    command would look something like:

    `oc port-forward nr-rfc-db-3-bitnami-pg-0 5433:5432`


