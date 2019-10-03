DEV_PROJECT = dev
STAGE_PROJECT = stage
CICD_PROJECT = acoss

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
		NO_PROXY="$$NO_PROXY,*.cluster.local,*.local"; \
	    fi; \
	    oc process -f cicd-template.yaml -p DEV_PROJECT=$(DEV_PROJECT) -p STAGE_PROJECT=$(STAGE_PROJECT) \
		-p PROXY_HOST="$$PROXY_HOST" -p PROXY_PORT="$$PROXY_PORT" -p PROXY_EXCLUDE_NAMES="$$NO_PROXY" \
		| oc apply -n $(CICD_PROJECT) -f-; \
	fi

reset:
	oc delete -n $(CICD_PROJECT) \
	    deployment/che pvc/che-data-volume rolebinding/che svc/che-host \
	    rolebinding/che-workspace-exec rolebinding/che-workspace-view \
	    route/che sa/che sa/che-workspace role/exec role/workspace-view \
	    dc/gogs pvc/gogs-data cm/gogs-config routes/gogs svc/gogs is/gogs \
	    dc/gogs-postgresql pvc/gogs-postgres-data svc/gogs-postgresql  \
	    dc/nexus pvc/nexus-pv svc/nexus routes/nexus is/nexus \
	    route/jenkins cm/jenkins-conf dc/jenkins svc/jenkins-jnlp svc/jenkins \
	    sa/jenkins rolebinding/jenkins_edit cm/jenkins-slaves \
	    dc/sonarqube pvc/sonardb routes/sonarqube svc/sonarqube is/sonarqube cm/sonarqube \
	    dc/sonardb pvc/sonarqube-data secret/sonardb secret/sonar-ldap-bind-dn svc/sonardb \
	    dc/clair-postgres secret/clair-postgres pvc/clair-postgres svc/clair-postgres \
	    dc/clair secret/clair svc/clair route/clair is/clair \
	    rolebinding/default_admin job/cicd-demo-installer bc/tasks-pipeline || true
	oc delete -n $(DEV_PROJECT) bc/tasks dc/tasks svc/tasks route/tasks is/tasks || true
	oc delete -n $(STAGE_PROJECT) dc/tasks svc/tasks route/tasks || true

#dev-*, stage-*
