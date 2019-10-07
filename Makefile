DEV_PROJECT = dev
STAGE_PROJECT = stage
CICD_PROJECT = cicd

.PHONY: init
init:
	@@if ! oc describe project $(DEV_PROJECT) >/dev/null 2>&1; then \
	    oc new-project $(DEV_PROJECT) --display-name="Tasks - Dev"; \
	fi
	@@if ! oc describe project $(STAGE_PROJECT) >/dev/null 2>&1; then \
	    oc new-project $(STAGE_PROJECT) --display-name="Tasks - Stage"; \
	fi
	@@if ! oc describe project $(CICD_PROJECT) >/dev/null 2>&1; then \
	    oc new-project $(CICD_PROJECT) --display-name="CI/CD"; \
	else \
	    if oc describe resourcequota -n $(CICD_PROJECT) | grep [a-zA-Z] >/dev/null 2>&1; then \
		oc delete resourcequota -n $(CICD_PROJECT) --all; \
	    fi; \
	    if oc describe limitrange -n $(CICD_PROJECT) | grep [a-zA-Z] >/dev/null 2>&1; then \
		oc delete limitrange -n $(CICD_PROJECT) --all; \
	    fi; \
	fi
	@@if ! oc get rolebindings -n $(DEV_PROJECT) 2>/dev/null | grep edit | grep system:serviceaccounts:$(CICD_PROJECT) >/dev/null; then \
	    oc policy add-role-to-group edit system:serviceaccounts:$(CICD_PROJECT) -n $(DEV_PROJECT); \
	fi
	@@if ! oc get rolebindings -n $(STAGE_PROJECT) 2>/dev/null | grep edit | grep system:serviceaccounts:$(CICD_PROJECT) >/dev/null; then \
	    oc policy add-role-to-group edit system:serviceaccounts:$(CICD_PROJECT) -n $(STAGE_PROJECT); \
	fi

.PHONY: start
start: init
	@@if test -z "$$HTTP_PROXY"; then \
	    oc process -f cicd-template.yaml -p DEV_PROJECT=$(DEV_PROJECT) -p STAGE_PROJECT=$(STAGE_PROJECT) \
		| oc apply -n $(CICD_PROJECT) -f-; \
	else \
	    PROXY_PORT=8080; \
	    PROXY_HOST=`echo $$HTTP_PROXY | sed 's|.*://||'`; \
	    if echo "$$PROXY_HOST" | grep : >/dev/null; then \
		PROXY_PORT=`echo $$PROXY_HOST | cut -d: -f2`; \
		PROXY_HOST=`echo $$PROXY_HOST | cut -d: -f1`; \
	    fi; \
	    if test "$$NO_PROXY"; then \
		NO_PROXY="$$NO_PROXY,.cluster.local,.local"; \
	    fi; \
	    oc process -f cicd-template.yaml -p DEV_PROJECT=$(DEV_PROJECT) -p STAGE_PROJECT=$(STAGE_PROJECT) \
		-p PROXY_HOST="$$PROXY_HOST" -p PROXY_PORT="$$PROXY_PORT" -p PROXY_EXCLUDE_NAMES="$$NO_PROXY" \
		| oc apply -n $(CICD_PROJECT) -f-; \
	fi

.PHONY: quay
quay:
	@@if ! test -d quay-operator; then \
	    git clone https://github.com/redhat-cop/quay-operator; \
	fi
	@@if ! oc describe project quay-enterprise >/dev/null 2>&1; then \
	    oc new-project quay-operator; \
	    oc project cicd; \
	fi
	@@if test -d quay-operator; then \
	    ( \
		cd quay-operator/; \
		oc apply -n quay-enterprise -f deploy/crds/redhatcop_v1alpha1_quayecosystem_crd.yaml; \
		oc apply -n quay-enterprise -f deploy/service_account.yaml; \
		oc apply -n quay-enterprise -f deploy/cluster_role.yaml; \
		oc apply -n quay-enterprise -f deploy/cluster_role_binding.yaml; \
		oc apply -n quay-enterprise -f deploy/role.yaml; \
		oc apply -n quay-enterprise -f deploy/role_binding.yaml; \
		oc apply -n quay-enterprise -f deploy/operator.yaml; \
	    ); \
	fi
	@@if ! oc describe quay-ecosystem demo >/dev/null 2>&1; then \
	    ROUTE_DOMAIN=`oc get route console -n openshift-console -o template --template='{{.spec.host}}' | sed 's|^console\.||'`; \
	    if test "$$HTTP_PROXY"; then \
		if test "$$NO_PROXY"; then \
		    NO_PROXY="$$NO_PROXY,.cluster.local,.local"; \
		else
		    NO_PROXY=".cluster.local,.local"; \
		fi; \
		oc process -f quay-enterprise.yaml -p HTTP_PROXY="$$HTTP_PROXY" \
		    -p PROXY_EXCLUDE_NAMES="$$NO_PROXY" -p ROUTE_DOMAIN=$$ROUTE_DOMAIN; \
	    else \
		oc process -f quay-deployment.yaml -p ROUTE_DOMAIN=$$ROUTE_DOMAIN; \
	    fi | oc apply -n quay-enterprise -f-; \
	fi

.PHONY: reset
reset:
	oc delete -n $(CICD_PROJECT) \
	    deployment/che pvc/che-data-volume rolebinding/che svc/che-host \
	    rolebinding/che-workspace-exec rolebinding/che-workspace-view \
	    route/che sa/che sa/che-workspace role/exec role/workspace-view \
	    dc/gogs pvc/gogs-data cm/gogs-config routes/gogs svc/gogs is/gogs \
	    dc/gogs-postgresql pvc/gogs-postgres-data svc/gogs-postgresql  \
	    dc/nexus pvc/nexus-pv svc/nexus routes/nexus is/nexus \
	    route/jenkins cm/jenkins-conf dc/jenkins svc/jenkins-jnlp svc/jenkins \
	    sa/jenkins rolebinding/jenkins_edit cm/jenkins-slaves pvc/jenkins-data \
	    bc/jenkins-agent-klar is/jenkins-agent-klar is/jenkins \
	    dc/sonarqube pvc/sonardb routes/sonarqube svc/sonarqube is/sonarqube cm/sonarqube \
	    dc/sonardb pvc/sonarqube-data secret/sonardb secret/sonar-ldap-bind-dn svc/sonardb \
	    dc/clair-postgres secret/clair-postgres pvc/clair-postgres svc/clair-postgres \
	    dc/clair secret/clair svc/clair route/clair is/clair \
	    rolebinding/default_admin job/cicd-demo-installer bc/tasks-pipeline \
	    secrets/quay-cicd-secret || true
	oc delete -n $(DEV_PROJECT) bc/tasks dc/tasks svc/tasks route/tasks is/tasks || true
	oc delete -n $(STAGE_PROJECT) dc/tasks svc/tasks route/tasks || true
