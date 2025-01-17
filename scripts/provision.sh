#!/bin/bash

echo "###############################################################################"
echo "#  MAKE SURE YOU ARE LOGGED IN:                                               #"
echo "#  $ oc login http://console.your.openshift.com                               #"
echo "###############################################################################"

function usage() {
    echo
    echo "Usage:"
    echo " $0 [command] [options]"
    echo " $0 --help"
    echo
    echo "Example:"
    echo " $0 deploy --project-suffix mydemo"
    echo
    echo "COMMANDS:"
    echo "   deploy                   Set up the demo projects and deploy demo apps"
    echo "   delete                   Clean up and remove demo projects and objects"
    echo "   idle                     Make all demo services idle"
    echo "   unidle                   Make all demo services unidle"
    echo
    echo "OPTIONS:"
    echo "   --enable-quay              Optional    Enable integration of build and deployments with Quay"
    echo "   --quay-authuser            Optional    username authenticating against Quay registry."
    echo "   --quay-backend             Optional    quay backend pushing images to a Quay registry. Defaults to quay.io."
    echo "   --quay-username            Optional    quay username or organization pushing images to a Quay registry. Required if --enable-quay is set"
    echo "   --quay-password            Optional    quay password or token pushing images to a Quay registry. Required if --enable-quay is set"
    echo "   --user [username]          Optional    The admin user for the demo projects. Required if logged in as system:admin"
    echo "   --project-suffix [suffix]  Optional    Suffix to be added to demo project names e.g. ci-SUFFIX. If empty, user will be used as suffix"
    echo "   --ephemeral                Optional    Deploy demo without persistent storage. Default false"
    echo "   --enable-che               Optional    Deploy Eclipse Che as an online IDE for code changes. Default false"
    echo "   --oc-options               Optional    oc client options to pass to all oc commands e.g. --server https://my.openshift.com"
    echo
}

ARG_USERNAME=
ARG_PROJECT_SUFFIX=
ARG_COMMAND=
ARG_EPHEMERAL=false
ARG_OC_OPS=
ARG_DEPLOY_CHE=false
ARG_DEPLOY_CLAIR=false
ARG_ENABLE_QUAY=false
ARG_QUAY_AUTHUSER=
ARG_QUAY_HOSTNAME=quay.io
ARG_QUAY_USER=
ARG_QUAY_PASS=

if test "$http_proxy" -a -z "$HTTP_PROXY"; then
    HTTP_PROXY=$http_proxy
fi
if echo "$HTTP_PROXY" | grep http:// >/dev/null; then
    eval `echo "$HTTP_PROXY" | sed -e 's|http://||' -e 's|/*$||' | awk -F: '{print "PROXY_HOST="$1" PROXY_PORT="$2}'`
fi

while :; do
    case $1 in
        deploy)
            ARG_COMMAND=deploy
            ;;
        delete)
            ARG_COMMAND=delete
            ;;
        idle)
            ARG_COMMAND=idle
            ;;
        unidle)
            ARG_COMMAND=unidle
            ;;
        --user)
            if [ -n "$2" ]; then
                ARG_USERNAME=$2
                shift
            else
                printf 'ERROR: "--user" requires a non-empty value.\n' >&2
                usage
                exit 255
            fi
            ;;
        --project-suffix)
            if [ -n "$2" ]; then
                ARG_PROJECT_SUFFIX=$2
                shift
            else
                printf 'ERROR: "--project-suffix" requires a non-empty value.\n' >&2
                usage
                exit 255
            fi
            ;;
        --oc-options)
            if [ -n "$2" ]; then
                ARG_OC_OPS=$2
                shift
            else
                printf 'ERROR: "--oc-options" requires a non-empty value.\n' >&2
                usage
                exit 255
            fi
            ;;
        --proxy-host)
            PROXY_HOST=$2
            ;;
        --proxy-port)
            PROXY_PORT=$2
            ;;
        --proxy-exclude)
            PROXY_EXCLUDE=$2
            ;;
        --enable-quay)
            ARG_ENABLE_QUAY=true
            ;;
        --quay-backend)
            if [ -n "$2" ]; then
                ARG_QUAY_HOSTNAME=$2
                shift
            else
                printf 'ERROR: "--quay-backend" requires a non-empty value.\n' >&2
                usage
                exit 255
            fi
            ;;
        --quay-authuser)
            if [ -n "$2" ]; then
                ARG_QUAY_AUTHUSER=$2
                shift
            else
                printf 'ERROR: "--quay-authuser" requires a non-empty value.\n' >&2
                usage
                exit 255
            fi
            ;;
        --quay-username)
            if [ -n "$2" ]; then
                ARG_QUAY_USER=$2
                shift
            else
                printf 'ERROR: "--quay-username" requires a non-empty value.\n' >&2
                usage
                exit 255
            fi
            ;;
        --quay-password)
            if [ -n "$2" ]; then
                ARG_QUAY_PASS=$2
                shift
            else
                printf 'ERROR: "--quay-password" requires a non-empty value.\n' >&2
                usage
                exit 255
            fi
            ;;
        --ephemeral)
            ARG_EPHEMERAL=true
            ;;
        --enable-clair|--deploy-clair)
            ARG_DEPLOY_CLAIR=true
            ;;
        --enable-che|--deploy-che)
            ARG_DEPLOY_CHE=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -?*)
            printf 'WARN: Unknown option (ignored): %s\n' "$1" >&2
            shift
            ;;
        *) # Default case: If no more options then break out of the loop.
            break
    esac

    shift
done
if $ARG_ENABLE_QUAY; then
    if test -z "$ARG_QUAY_AUTHUSER"; then
	ARG_QUAY_AUTHUSER="$ARG_QUAY_USERNAME"
    fi
fi
if test -z "$PROXY_HOST"; then
    PROXY_PORT= PROXY_EXCLUDE=
fi


################################################################################
# CONFIGURATION                                                                #
################################################################################

LOGGEDIN_USER=$(oc $ARG_OC_OPS whoami)
OPENSHIFT_USER=${ARG_USERNAME:-$LOGGEDIN_USER}
PRJ_SUFFIX=${ARG_PROJECT_SUFFIX:-`echo $OPENSHIFT_USER | sed -e 's/[-@].*//g'`}
GITHUB_ACCOUNT=${GITHUB_ACCOUNT:-faust64}
GITHUB_REF=${GITHUB_REF:-ocp-4.1}

function deploy() {
  oc $ARG_OC_OPS new-project dev-$PRJ_SUFFIX   --display-name="Tasks - Dev"
  oc $ARG_OC_OPS new-project stage-$PRJ_SUFFIX --display-name="Tasks - Stage"
  oc $ARG_OC_OPS new-project cicd-$PRJ_SUFFIX  --display-name="CI/CD"

  sleep 2

  oc $ARG_OC_OPS policy add-role-to-group edit system:serviceaccounts:cicd-$PRJ_SUFFIX -n dev-$PRJ_SUFFIX
  oc $ARG_OC_OPS policy add-role-to-group edit system:serviceaccounts:cicd-$PRJ_SUFFIX -n stage-$PRJ_SUFFIX

  if [ $LOGGEDIN_USER == 'system:admin' ] ; then
    oc $ARG_OC_OPS adm policy add-role-to-user admin $ARG_USERNAME -n dev-$PRJ_SUFFIX >/dev/null 2>&1
    oc $ARG_OC_OPS adm policy add-role-to-user admin $ARG_USERNAME -n stage-$PRJ_SUFFIX >/dev/null 2>&1
    oc $ARG_OC_OPS adm policy add-role-to-user admin $ARG_USERNAME -n cicd-$PRJ_SUFFIX >/dev/null 2>&1

    oc $ARG_OC_OPS annotate --overwrite namespace dev-$PRJ_SUFFIX   demo=openshift-cd-$PRJ_SUFFIX >/dev/null 2>&1
    oc $ARG_OC_OPS annotate --overwrite namespace stage-$PRJ_SUFFIX demo=openshift-cd-$PRJ_SUFFIX >/dev/null 2>&1
    oc $ARG_OC_OPS annotate --overwrite namespace cicd-$PRJ_SUFFIX  demo=openshift-cd-$PRJ_SUFFIX >/dev/null 2>&1

    oc $ARG_OC_OPS adm pod-network join-projects --to=cicd-$PRJ_SUFFIX dev-$PRJ_SUFFIX stage-$PRJ_SUFFIX >/dev/null 2>&1
  fi

  sleep 2

  oc new-app jenkins-ephemeral -n cicd-$PRJ_SUFFIX

  sleep 2

  local template=https://raw.githubusercontent.com/$GITHUB_ACCOUNT/openshift-cd-demo/$GITHUB_REF/cicd-template.yaml
  if test "$ARG_EPHEMERAL" = true; then
    template=https://raw.githubusercontent.com/$GITHUB_ACCOUNT/openshift-cd-demo/$GITHUB_REF/cicd-demo-template.yaml
  fi
  echo "Using template $template"
  oc $ARG_OC_OPS new-app -f $template \
      -p DEV_PROJECT=dev-$PRJ_SUFFIX -p STAGE_PROJECT=stage-$PRJ_SUFFIX \
      -p DEPLOY_CLAIR=$ARG_DEPLOY_CLAIR -p DEPLOY_CHE=$ARG_DEPLOY_CHE \
      -p EPHEMERAL=$ARG_EPHEMERAL -p ENABLE_QUAY=$ARG_ENABLE_QUAY \
      -p "PROXY_HOST=$PROXY_HOST" -p "PROXY_PORT=$PROXY_PORT" -p "PROXY_EXCLUDE_NAMES=$PROXY_EXCLUDE" \
      -p "QUAY_HOSTNAME=$ARG_QUAY_HOSTNAME" -p "QUAY_AUTHUSER=$ARG_QUAY_AUTHUSER" \
      -p "QUAY_USERNAME=$ARG_QUAY_USER" -p "QUAY_PASSWORD=$ARG_QUAY_PASS" -n cicd-$PRJ_SUFFIX
  if test "$ENABLE_QUAY" = false -a "$QUAY_PASSWORD"; then
    template=https://raw.githubusercontent.com/$GITHUB_ACCOUNT/openshift-cd-demo/$GITHUB_REF/sync2quay.yaml
    oc process -f $template -p "QUAY_HOSTNAME=$ARG_QUAY_HOSTNAME" -p "QUAY_AUTHUSER=$ARG_QUAY_AUTHUSER" \
      -p "QUAY_USERNAME=$ARG_QUAY_USER" -p "QUAY_PASSWORD=$ARG_QUAY_PASS" -n cicd-$PRJ_SUFFIX | oc apply -f-
  elif test "$ENABLE_QUAY" = false -a "$DEPLOY_CLAIR" = true; then
    template=https://raw.githubusercontent.com/$GITHUB_ACCOUNT/openshift-cd-demo/$GITHUB_REF/scan-template.yaml
    oc process -f $template | oc apply -f-
  fi
}

function make_idle() {
  echo_header "Idling Services"
  oc $ARG_OC_OPS idle -n dev-$PRJ_SUFFIX --all
  oc $ARG_OC_OPS idle -n stage-$PRJ_SUFFIX --all
  oc $ARG_OC_OPS idle -n cicd-$PRJ_SUFFIX --all
}

function make_unidle() {
  echo_header "Unidling Services"
  local _DIGIT_REGEX="^[[:digit:]]*$"

  for project in dev-$PRJ_SUFFIX stage-$PRJ_SUFFIX cicd-$PRJ_SUFFIX
  do
    for dc in $(oc $ARG_OC_OPS get dc -n $project -o=custom-columns=:.metadata.name); do
      local replicas=$(oc $ARG_OC_OPS get dc $dc --template='{{ index .metadata.annotations "idling.alpha.openshift.io/previous-scale"}}' -n $project 2>/dev/null)
      if [[ $replicas =~ $_DIGIT_REGEX ]]; then
        oc $ARG_OC_OPS scale --replicas=$replicas dc $dc -n $project
      fi
    done
  done
}

function set_default_project() {
  if [ $LOGGEDIN_USER == 'system:admin' ] ; then
    oc $ARG_OC_OPS project default >/dev/null
  fi
}

function remove_storage_claim() {
  local _DC=$1
  local _VOLUME_NAME=$2
  local _CLAIM_NAME=$3
  local _PROJECT=$4
  oc $ARG_OC_OPS volumes dc/$_DC --name=$_VOLUME_NAME --add -t emptyDir --overwrite -n $_PROJECT
  oc $ARG_OC_OPS delete pvc $_CLAIM_NAME -n $_PROJECT >/dev/null 2>&1
}

function echo_header() {
  echo
  echo "########################################################################"
  echo $1
  echo "########################################################################"
}

################################################################################
# MAIN: DEPLOY DEMO                                                            #
################################################################################

if [ "$LOGGEDIN_USER" == 'system:admin' ] && [ -z "$ARG_USERNAME" ] ; then
  # for verify and delete, --project-suffix is enough
  if [ "$ARG_COMMAND" == "delete" ] || [ "$ARG_COMMAND" == "verify" ] && [ -z "$ARG_PROJECT_SUFFIX" ]; then
    echo "--user or --project-suffix must be provided when running $ARG_COMMAND as 'system:admin'"
    exit 255
  # deploy command
  elif [ "$ARG_COMMAND" != "delete" ] && [ "$ARG_COMMAND" != "verify" ] ; then
    echo "--user must be provided when running $ARG_COMMAND as 'system:admin'"
    exit 255
  fi
fi

pushd ~ >/dev/null
START=`date +%s`

echo_header "OpenShift CI/CD Demo ($(date))"

case "$ARG_COMMAND" in
    delete)
        echo "Delete demo..."
        oc $ARG_OC_OPS delete project dev-$PRJ_SUFFIX stage-$PRJ_SUFFIX cicd-$PRJ_SUFFIX
        echo
        echo "Delete completed successfully!"
        ;;

    idle)
        echo "Idling demo..."
        make_idle
        echo
        echo "Idling completed successfully!"
        ;;

    unidle)
        echo "Unidling demo..."
        make_unidle
        echo
        echo "Unidling completed successfully!"
        ;;

    deploy)
        echo "Deploying demo..."
        deploy
        echo
        echo "Provisioning completed successfully!"
        ;;

    *)
        echo "Invalid command specified: '$ARG_COMMAND'"
        usage
        ;;
esac

set_default_project
popd >/dev/null

END=`date +%s`
echo "(Completed in $(( ($END - $START)/60 )) min $(( ($END - $START)%60 )) sec)"
echo
