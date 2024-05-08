#!/bin/bash

#
# variables
#
export AWS_PROFILE=default
export PROJECT_NAME=pandosec-plat-test
export AWS_REGION=us-east-1
export GIT_REPO=git@github.com:pandosec/gitops-infra.git
# the directory containing the script file
export PROJECT_DIR="$(cd "$(dirname "$0")"; pwd)"

#
# overwrite TF variables
#
export TF_VAR_project_name=$PROJECT_NAME
export TF_VAR_region=$AWS_REGION

log() { printf "\e[30;47m %s \e[0m %s\n" "$(echo $1 | tr '[:lower:]' '[:upper:]')" "${@:2}"; }          # $1 uppercase background white
info() { printf "\e[48;5;28m %s \e[0m %s\n" "$(echo $1 | tr '[:lower:]' '[:upper:]')" "${@:2}"; }       # $1 uppercase background green
warn() { printf "\e[48;5;202m %s \e[0m %s\n" "$(echo $1 | tr '[:lower:]' '[:upper:]')" "${@:2}" >&2; }  # $1 uppercase background orange
error() { printf "\e[48;5;196m %s \e[0m %s\n" "$(echo $1 | tr '[:lower:]' '[:upper:]')" "${@:2}" >&2; } # $1 uppercase background red

# export functions : https://unix.stackexchange.com/a/22867
export -f log info warn error

# log $1 in underline then $@ then a newline
under() {
    local arg=$1
    shift
    echo -e "\033[0;4m${arg}\033[0m ${@}"
    echo
}

usage() {
    under usage 'call the Makefile directly: make dev
      or invoke this file directly: ./make.sh dev'
}

# setup project + create S3 bucket
init() {
    bash scripts/init.sh
}

# terraform init the dev env
dev-init() {
    [[ ! -f "$PROJECT_DIR/.env_UUID" ]] && init
    export CHDIR="$PROJECT_DIR/terraform/dev"
    export S3_BUCKET=$(cat "$PROJECT_DIR/.env_S3_BUCKET")
    export CONFIG_KEY=dev/terraform.tfstate
    scripts/terraform-init.sh
}

# terraform init the prod env
prod-init() {
    [[ ! -f $PROJECT_DIR/.env_UUID ]] && init
    export CHDIR=$PROJECT_DIR/terraform/prod
    export S3_BUCKET=$(cat "$PROJECT_DIR/.env_S3_BUCKET")
    export CONFIG_KEY=prod/terraform.tfstate
    scripts/terraform-init.sh
}

# terraform validate the dev env
dev-validate() {
    export CHDIR="$PROJECT_DIR/terraform/dev"
    scripts/terraform-validate.sh
}

# terraform validate the prod env
prod-validate() {
    export CHDIR=$PROJECT_DIR/terraform/prod
    scripts/terraform-validate.sh
}

# terraform plan + apply the dev env
dev-apply() {
    export CHDIR="$PROJECT_DIR/terraform/dev"
    export TF_VAR_project_env=dev
    scripts/terraform-apply.sh
    # kubectl-eks-config
}

# terraform plan + apply the prod env
prod-apply() {
    export CHDIR="$PROJECT_DIR/terraform/prod"
    export TF_VAR_project_env=prod
    scripts/terraform-apply.sh
}

kubectl-eks-config() {
    OUTPUT=$(terraform -chdir="$CHDIR" output --json)
    NAME=$(echo "$OUTPUT" | jq --raw-output '.eks_cluster_id.value')
    log NAME $NAME
    REGION=$(echo "$OUTPUT" | jq --raw-output '.region.value')
    log REGION $REGION

    # setup kubectl config
    log KUBECTL update config ...
    aws eks update-kubeconfig \
        --name $NAME \
        --region $REGION

    KUBE_CONTEXT=$(kubectl config current-context)
    log KUBE_CONTEXT $KUBE_CONTEXT
    
    # wait for configmap availability
    while [[ -z $(kubectl get configmap aws-auth -n kube-system 2>/dev/null) ]]; do sleep 1; done

    log WRITE aws-auth-configmap.yaml
    # your current user or role does not have access to Kubernetes objects on this EKS cluster
    # https://stackoverflow.com/questions/70787520/your-current-user-or-role-does-not-have-access-to-kubernetes-objects-on-this-eks
    # https://stackoverflow.com/a/70980613
    kubectl get configmap aws-auth \
        --namespace kube-system \
        --output yaml > "$PROJECT_DIR/aws-auth-configmap.yaml"

    log WRITE aws-auth-configmap.json
    # convert to json
    yq aws-auth-configmap.yaml -o json > "$PROJECT_DIR/aws-auth-configmap.json"

    AWS_ID=$(cat "$PROJECT_DIR/.env_AWS_ID")
    log AWS_ID $AWS_ID

    # add mapUsers (use jq instead yq to add mapUsers because it's MUCH simpler and MORE clean)
    jq '.data += {"mapUsers": "- userarn: arn:aws:iam::'$AWS_ID':root\n  groups:\n  - system:masters\n"}' aws-auth-configmap.json \
    | yq --prettyPrint > "$PROJECT_DIR/aws-auth-configmap.yaml"

    # apply udated aws-auth-configmap.yaml
    kubectl apply --filename aws-auth-configmap.yaml --namespace kube-system
}

# setup kubectl config + aws-auth configmap for dev env
eks-dev-config() {
    export CHDIR="$PROJECT_DIR/terraform/dev"
    kubectl-eks-config

    log KUBE rename context to $PROJECT_NAME-dev
    kubectl config rename-context arn:aws:eks:$REGION:$AWS_ID:cluster/$PROJECT_NAME-dev $PROJECT_NAME-dev

    KUBE_CONTEXT=$(kubectl config current-context)
    log KUBE_CONTEXT $KUBE_CONTEXT
}

# setup kubectl config + aws-auth configmap for prod env
eks-prod-config() {
    export CHDIR="$PROJECT_DIR/terraform/prod"
    kubectl-eks-config

    log KUBE rename context to $PROJECT_NAME-prod
    kubectl config rename-context arn:aws:eks:$REGION:$AWS_ID:cluster/$PROJECT_NAME-prod $PROJECT_NAME-prod

    KUBE_CONTEXT=$(kubectl config current-context)
    log KUBE_CONTEXT $KUBE_CONTEXT
}

dev-destroy() {
    kubectl config use-context $PROJECT_NAME-dev
    kubectl config current-context

    kubectl delete ns gitops-platform --ignore-not-found --wait

    export TF_VAR_project_env=dev
    terraform -chdir=$PROJECT_DIR/terraform/dev destroy -auto-approve
}

prod-destroy() {
    kubectl config use-context $PROJECT_NAME-prod
    kubectl config current-context

    kubectl delete ns gitops-platform --ignore-not-found --wait

    export TF_VAR_project_env=prod
    terraform -chdir=$PROJECT_DIR/terraform/prod destroy -auto-approve
}

argo-install() {
    log wait kubectl config context must be defined
    while [[ -z $(kubectl config current-context 2>/dev/null) ]]; do sleep 1; done

    log delete kubectl delete previous argocd namespace
    kubectl delete ns argocd --ignore-not-found --wait

    log create kubectl create argocd namespace
    kubectl create namespace argocd

    log install kubectl install argocd
    kubectl apply \
        --namespace argocd \
        --filename https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

    log wait kubectl argocd-server must be deployed
    kubectl wait deploy argocd-server \
        --timeout=180s \
        --namespace argocd \
        --for=condition=Available=True

    # Check if port forwarding is already running on port 8080
    if ! lsof -i :8080 | grep -q LISTEN; then
        # Start port-forwarding in the background
        kubectl port-forward svc/argocd-server -n argocd 8080:443 &
        PORT_FORWARD_PID=$!
        log "Port forwarding started on PID $PORT_FORWARD_PID"
    else
        log "Port forwarding already running on port 8080"
    fi

    log info Port-forwarding running on localhost:8080

    # Wait for the port-forwarding to be ready using curl
    log wait Checking for port-forwarding readiness
    while [[ -z $(curl -k https://localhost:8080 2>/dev/null) ]]; do sleep 1; done

    ARGO_PASSWORD=$(kubectl get secret argocd-initial-admin-secret \
        --namespace argocd \
        --output jsonpath="{.data.password}" |
        base64 --decode)
    log ARGO_PASSWORD $ARGO_PASSWORD

    # Automatically login to Argo CD
    argocd login localhost:8080 \
        --insecure \
        --username admin \
        --password $ARGO_PASSWORD

    log ACTION open localhost:8080 + accept self-signed risk
    log argocd login with ...
    log username admin
    log password $ARGO_PASSWORD
}



argo-login() {
    # Check if port forwarding is already running on port 8080
    if ! lsof -i :8080 | grep -q LISTEN; then
        # Start port-forwarding in the background
        kubectl port-forward svc/argocd-server -n argocd --context $PROJECT_NAME-dev 8080:443 &
        PORT_FORWARD_PID=$!
        log "Port forwarding started on PID $PORT_FORWARD_PID"
    else
        log "Port forwarding already running on port 8080"
    fi

    log SERVER localhost:8080

    log USERNAME admin

    PASSWORD=$(kubectl get secret argocd-initial-admin-secret \
        --context $PROJECT_NAME-dev \
        --namespace argocd \
        --output jsonpath="{.data.password}" |
        base64 --decode)
    log PASSWORD $PASSWORD

    # Wait for the port-forwarding to be ready using curl
    log "Checking for port-forwarding readiness"
    while [[ -z $(curl -k https://localhost:8080 2>/dev/null) ]]; do sleep 1; done

    argocd login localhost:8080 \
        --insecure \
        --username=admin \
        --password=$PASSWORD
}



argo-add-repo() {
    if [[ ! -f ~/.ssh/$PROJECT_NAME.pem ]];
    then
        log CREATE "$PROJECT_NAME.pem keypair (without passphrase)"
        # -t ➜ Specifies the type of key to create.
        # -N ➜ Provides the new passphrase.
        # -f ➜ Specifies the filename of the key file.
        ssh-keygen -t ed25519 -N "" -f ~/.ssh/$PROJECT_NAME.pem

        mv ~/.ssh/$PROJECT_NAME.pem.pub ~/.ssh/$PROJECT_NAME.pub
        info CREATED "~/.ssh/$PROJECT_NAME.pem"
        info CREATED "~/.ssh/$PROJECT_NAME.pub"
    fi

    if [[ -z $(gh ssh-key list | grep ^$PROJECT_NAME) ]];
    then
        log ADD $PROJECT_NAME.pub to Github
        gh ssh-key add ~/.ssh/$PROJECT_NAME.pub --title $PROJECT_NAME
    fi

    log ADD git repository to argocd
    argocd repo add $GIT_REPO \
        --insecure-ignore-host-key \
        --ssh-private-key-path ~/.ssh/$PROJECT_NAME.pem
}

argo-add-cluster() {
    argocd cluster add --yes $PROJECT_NAME-prod
}

argo-dev-app() {
    export NAMESPACE=dev
    export SERVER=https://kubernetes.default.svc
    # /!\ switch to the dev cluster for the next commands
    kubectl config use-context $PROJECT_NAME-dev
    cat argocd/argocd-app.yaml | envsubst | kubectl apply -f -

    log wait namespace gitops-platform must be defined
    while [[ -z $(kubectl get ns gitops-platform 2>/dev/null) ]]; do sleep 1; done

    log wait website load balancer must be defined
    # sleep here
    while true; do
        WEBSITE_LOAD_BALANCER=$(kubectl get svc website \
            --namespace gitops-platform \
            --output json |
            jq --raw-output '.status.loadBalancer.ingress[0].hostname')
        [[ "$WEBSITE_LOAD_BALANCER" != 'null' ]] && break;
    done
    log WEBSITE_LOAD_BALANCER $WEBSITE_LOAD_BALANCER

    log wait website load balancer must be available
    # sleep here
    while [[ -z $(curl $WEBSITE_LOAD_BALANCER 2>/dev/null) ]]; do sleep 1; done

    info READY "http://$WEBSITE_LOAD_BALANCER" is available
}

argo-prod-app() {
    export NAMESPACE=prod
    CLUSTER_ENDPOINT=$(terraform -chdir="$PROJECT_DIR/terraform/prod" output \
        -raw eks_cluster_endpoint)
    log CLUSTER_ENDPOINT $CLUSTER_ENDPOINT
    export SERVER=$CLUSTER_ENDPOINT
    # /!\ switch to the dev cluster for the next commands
    kubectl config use-context $PROJECT_NAME-prod
    cat argocd/argocd-app.yaml | envsubst | kubectl apply -f -

    log wait namespace gitops-platform must be defined
    while [[ -z $(kubectl get ns gitops-platform 2>/dev/null) ]]; do sleep 1; done

    log wait website load balancer must be defined
    # sleep here
    while true; do
        WEBSITE_LOAD_BALANCER=$(kubectl get svc website \
            --namespace gitops-platform \
            --output json |
            jq --raw-output '.status.loadBalancer.ingress[0].hostname')
        [[ "$WEBSITE_LOAD_BALANCER" != 'null' ]] && break;
    done
    log WEBSITE_LOAD_BALANCER $WEBSITE_LOAD_BALANCER

    log wait website load balancer must be available
    # sleep here
    while [[ -z $(curl $WEBSITE_LOAD_BALANCER 2>/dev/null) ]]; do sleep 1; done

    info READY "http://$WEBSITE_LOAD_BALANCER" is available
}

argo-destroy() {
    argocd app delete app-prod --yes
    kubectl delete ns gitops-platform --context $PROJECT_NAME-prod --wait

    argocd app delete app-dev --yes
    kubectl delete ns gitops-platform --context $PROJECT_NAME-dev --wait
    
    kubectl delete ns argocd --context $PROJECT_NAME-dev --ignore-not-found --wait
}

# if `$1` is a function, execute it. Otherwise, print usage
# compgen -A 'function' list all declared functions
# https://stackoverflow.com/a/2627461
FUNC=$(compgen -A 'function' | grep $1)
[[ -n $FUNC ]] && {
    info execute $1
    eval $1
} || usage
exit 0
