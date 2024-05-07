.SILENT:
.PHONY: vote metrics

help:
	{ grep --extended-regexp '^[a-zA-Z_-]+:.*#[[:space:]].*$$' $(MAKEFILE_LIST) || true; } \
	| awk 'BEGIN { FS = ":.*#[[:space:]]*" } { printf "\033[1;32m%-22s\033[0m%s\n", $$1, $$2 }'


init: # setup project + create S3 bucket
	./make.sh init

dev-init: # terraform init the dev env
	./make.sh dev-init

dev-validate: # terraform validate the dev env
	./make.sh dev-validate

dev-apply: # terraform plan + apply the dev env
	./make.sh dev-apply

dev-destroy: # terraform destroy the dev env
	./make.sh dev-destroy

prod-init: # terraform init the prod env
	./make.sh prod-init

prod-validate: # terraform validate the prod env
	./make.sh prod-validate

prod-apply: # terraform plan + apply the prod env
	./make.sh prod-apply

prod-destroy: # terraform destroy the prod env
	./make.sh prod-destroy

eks-dev-config: # setup kubectl config + aws-auth configmap for dev env
	./make.sh eks-dev-config

eks-prod-config: # setup kubectl config + aws-auth configmap for prod env
	./make.sh eks-prod-config

argo-install: # install argocd in dev env
	./make.sh argo-install

argo-login: # argocd cli login + show access data
	./make.sh argo-login

argo-add-repo: # add git repo connection + create ssh key + add ssh key to github
	./make.sh argo-add-repo

argo-add-cluster: # argocd add prod cluster
	./make.sh argo-add-cluster

argo-dev-app: # create argocd dev app
	./make.sh argo-dev-app

argo-prod-app: # create argocd prod app
	./make.sh argo-prod-app

argo-destroy: # delete argocd apps then argocd
	./make.sh argo-destroy