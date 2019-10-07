# CI/CD Demo - OpenShift Container Platform 3.11

This repository includes the infrastructure and pipeline definition for continuous delivery using Jenkins, Nexus, SonarQube, CoreOS Clair and Eclipse Che on OpenShift.

* [Introduction](#introduction)
* [Prerequisites](#prerequisites)
* [Automated Deploy on OpenShift](#automatic-deploy-on-openshift)
* [Manual Deploy on OpenShift](#manual-deploy-on-openshift)
* [Troubleshooting](#troubleshooting)
* [Demo Guide](#demo-guide)
* [Using Eclipse Che for Editing Code](#using-eclipse-che-for-editing-code)


## Introduction

On every pipeline execution, the code goes through the following steps:

1. Code is cloned from Gogs, built, tested and analyzed for bugs and bad patterns
2. The WAR artifact is pushed to Nexus Repository manager
3. A container image (_tasks:latest_) is built based on the _Tasks_ application WAR artifact deployed on WildFly
4. If CoreOS is enabled, the resulting image is scanned
4. If Quay.io is enabled, the Tasks app container image is pushed to Quay (self-hosted or Quay.io) image registry and a security scan is scheduled
5. The _Tasks_ container image is deployed in a fresh new container in DEV project (pulled form Quay, if enabled)
6. If tests successful, the pipeline is paused for the release manager to approve the release to STAGE
7. If approved, the DEV image is tagged in the STAGE project. If Quay is enabled, the image is tagged in the Quay image repository using [Skopeo](https://github.com/containers/skopeo)
8. The staged image is deployed in a fresh new container in the STAGE project (pulled form Quay, if enabled)

The following diagram shows the steps included in the deployment pipeline:

![](images/pipeline.svg)

The application used in this pipeline is a JAX-RS application which is available on GitHub and is imported into Gogs during the setup process:
[https://github.com/OpenShiftDemos/openshift-tasks](https://github.com/OpenShiftDemos/openshift-tasks/tree/eap-7)

## Prerequisites
* 10+ GB memory

## Automated Deploy on OpenShift
You can se the `scripts/provision.sh` script provided to deploy the entire demo:

  ```
  ./scripts/provision.sh --help
  ./scripts/provision.sh deploy --enable-che --ephemeral # with Eclipse Che
  ./scripts/provision.sh delete
  ```
If you want to use Quay.io as an external registry with this demo, Go to quay.io and register for free. Then deploy the demo providing your
quay.io credentials:

  ```
  ./provision.sh deploy --enable-quay --quay-username quay_username --quay-password quay_password
  ```
In that case, the pipeline would create an image repository called `tasks-app` (default name but configurable)
on your Quay.io account and use that instead of the integrated OpenShift
registry, for pushing the built images and also pulling images for deployment.

If you want to deploy Quay on OpenShift, then as a cluster-admin, use the following:

  ```
  make quay
  ```
Once quay is started, we may log in to `registry.<OPENSHIFT-APPS-DOMAIN>` (user: quayadmin, pass: redhat42).

Then, we may deploy our demo pipeline:
  ```
  ./provision.sh deploy --enable-quay --quay-backend registry.<OPENSHIFT-APPS-DOMAIN> --quay-authuser='$app' --quay-username cicd --quay-password <auth-token>
  ```

## Manual Deploy on OpenShift
Follow these [instructions](docs/local-cluster.md) in order to create a local OpenShift cluster.

And then deploy the demo:

  ```
  # Deploy Demo
  make start
  ```

To use custom project names, change `cicd`, `dev` and `stage` in the above commands to
your own names and use the following to create the demo:

  ```
  make -e CICD_PROJECT=cicd -e DEV_PROJECT=dev -e STAGE_PROJECT=stage start
  ```

Clean up assets with:

  ```
  make -e CICD_PROJECT=cicd reset
  ```

# JBoss EAP vs WildFly

This demo by default uses the WildFly community image. You can use the JBoss EAP enterprise images provide by Red Hat by simply editing the
`tasks` build config in the _Tasks - Dev_ project and changing the builder image from `wildfly` to `jboss-eap70-openshift:1.5`. The demo would work exactly the same and would build the images using the JBoss EAP builder image. If using Quay, be sure not to leave the JBoss EAP images on a publicly accessible image repository.

## Troubleshooting

* If Maven fails with `/opt/rh/rh-maven33/root/usr/bin/mvn: line 9:   298 Killed` (e.g. during static analysis), you are running out of memory and need more memory for OpenShift.

* If running into `Permission denied` issues on minishift or CDK, run the following to adjust minishift persistent volume permissions:
  ```
  minishift ssh
  chmod 777 -R /var/lib/minishift/
  ```

* If Jenkins fails to start with an error `java: command not found`, start a debug Pod (`oc debug <jenkins-pod-name>`) then locate the java binary (`find / -name java`), and edit fix the `PATH` environment variable for Jenkins:
   ```
  oc env -n cicd dc/jenkins PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/lib/jvm/java-11-openjdk-VV.W.X.YY-Z.el7_7.x86_64/bin
   ```

* Scanning images for vulnerabilities, if your score shows all 0s, right after deploying Clair, it is not unlikely Clair is not yet done initializing its database. RHEL repos may take longer.
   ```
   {"Event":"Start fetching vulnerabilities","Level":"info","Location":"rhel.go:92","Time":"2019-10-03 17:13:17.513592","package":"RHEL"}
   {"Event":"Start fetching vulnerabilities","Level":"info","Location":"ubuntu.go:85","Time":"2019-10-03 17:13:17.513666","package":"Ubuntu"}
   {"Event":"Start fetching vulnerabilities","Level":"info","Location":"alpine.go:52","Time":"2019-10-03 17:13:17.524607","package":"Alpine"}
   {"Event":"Start fetching vulnerabilities","Level":"info","Location":"amzn.go:84","Time":"2019-10-03 17:13:17.543121","package":"Amazon Linux 2018.03"}
   {"Event":"Start fetching vulnerabilities","Level":"info","Location":"amzn.go:84","Time":"2019-10-03 17:13:17.543449","package":"Amazon Linux 2"}
   {"Event":"Start fetching vulnerabilities","Level":"info","Location":"debian.go:63","Time":"2019-10-03 17:13:17.543538","package":"Debian"}
   {"Event":"Start fetching vulnerabilities","Level":"info","Location":"oracle.go:119","Time":"2019-10-03 17:13:17.543788","package":"Oracle Linux"}
   [...]
   {"Event":"finished fetching","Level":"info","Location":"updater.go:253","Time":"2019-10-03 17:13:21.102030","updater name":"alpine"}
   {"Event":"finished fetching","Level":"info","Location":"updater.go:253","Time":"2019-10-03 17:13:25.257204","updater name":"amzn1"}
   {"Event":"finished fetching","Level":"info","Location":"updater.go:253","Time":"2019-10-03 17:13:28.521377","updater name":"debian"}
   {"Event":"finished fetching","Level":"info","Location":"updater.go:253","Time":"2019-10-03 17:54:46.413008","updater name":"rhel"}
   ```

other gotchas could involve proxies using whistlists filtering on DNS names or URL regexprs.


## Demo Guide

* Take note of these credentials and then follow the demo guide below:

  * Gogs: `gogs/gogs`
  * Nexus: `admin/admin123`
  * SonarQube: `admin/admin`

* A Jenkins pipeline is pre-configured which clones Tasks application source code from Gogs (running on OpenShift), builds, deploys and promotes the result through the deployment pipeline. In the CI/CD project, click on _Builds_ and then _Pipelines_ to see the list of defined pipelines.

    Click on _tasks-pipeline_ and _Configuration_ and explore the pipeline definition.

    You can also explore the pipeline job in Jenkins by clicking on the Jenkins route url, logging in with the OpenShift credentials and clicking on _tasks-pipeline_ and _Configure_.

* Run an instance of the pipeline by starting the _tasks-pipeline_ in OpenShift or Jenkins.

* During pipeline execution, verify a new Jenkins slave pod is created within _CI/CD_ project to execute the pipeline.

* If you have enabled Quay, after image build completes go to quay.io and show that a image repository is created and contains the Tasks app image

![](images/quay-pushed.png?raw=true)

* Pipelines pauses at _Deploy STAGE_ for approval in order to promote the build to the STAGE environment. Click on this step on the pipeline and then _Promote_.

* After pipeline completion, demonstrate the following:
  * Explore the _snapshots_ repository in Nexus and verify _openshift-tasks_ is pushed to the repository
  * Explore SonarQube and show the metrics, stats, code coverage, etc
  * Explore _Tasks - Dev_ project in OpenShift console and verify the application is deployed in the DEV environment
  * Explore _Tasks - Stage_ project in OpenShift console and verify the application is deployed in the STAGE environment
  * If Quay enabled, click on the image tag in quay.io and show the security scannig results

![](images/sonarqube-analysis.png?raw=true)

![](images/quay-claire.png?raw=true)

* Clone and checkout the _eap-7_ branch of the _openshift-tasks_ git repository and using an IDE (e.g. JBoss Developer Studio), remove the ```@Ignore``` annotation from ```src/test/java/org/jboss/as/quickstarts/tasksrs/service/UserResourceTest.java``` test methods to enable the unit tests. Commit and push to the git repo.

* Check out Jenkins, a pipeline instance is created and is being executed. The pipeline will fail during unit tests due to the enabled unit test.

* Check out the failed unit and test ```src/test/java/org/jboss/as/quickstarts/tasksrs/service/UserResourceTest.java``` and run it in the IDE.

* Fix the test by modifying ```src/main/java/org/jboss/as/quickstarts/tasksrs/service/UserResource.java``` and uncommenting the sort function in _getUsers_ method.

* Run the unit test in the IDE. The unit test runs green.

* Commit and push the fix to the git repository and verify a pipeline instance is created in Jenkins and executes successfully.

![](images/openshift-pipeline.png?raw=true)

## Using Eclipse Che for Editing Code

If you deploy the demo template using `DEPLOY_CHE=true` paramter, or the deploy script and use `--deploy-che` flag, then an [Eclipse Che](https://www.eclipse.org/che/) instances will be deployed within the CI/CD project which allows you to use the Eclipse Che web-based IDE for editing code in this demo.

Follow these [instructions](docs/using-eclipse-che.md) to use Eclipse Che for editing code in the above demo flow.

# Watch on YouTube

[![Continuous Delivery with OpenShift](images/youtube.png?raw=true)](https://youtu.be/_xh4XPkdXe0)
