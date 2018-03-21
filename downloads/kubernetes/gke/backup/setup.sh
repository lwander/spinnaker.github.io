#!/usr/bin/env bash

bold() {
  echo ". $(tput bold)" "$*" "$(tput sgr0)";
}

err() {
  echo "$*" >&2;
}

source ./properties

if [ -z "$PROJECT_ID" ]; then
  err "Not running in a GCP project. Exiting."
  exit 1
fi

bold "Starting the setup process in project $PROJECT_ID..."

bold "Creating a service account $SERVICE_ACCOUNT_NAME..."

gcloud iam service-accounts create \
  $SERVICE_ACCOUNT_NAME \
  --display-name $SERVICE_ACCOUNT_NAME

SA_EMAIL=$(gcloud iam service-accounts list \
  --filter="displayName:$SERVICE_ACCOUNT_NAME" \
  --format='value(email)')

gcloud projects add-iam-policy-binding $PROJECT_ID \
	--member serviceAccount:$SA_EMAIL \
	--role roles/owner

gcloud projects add-iam-policy-binding $PROJECT_ID \
	--member serviceAccount:$SA_EMAIL \
	--role roles/pubsub.subscriber

bold "Using bucket $BUCKET_URI..."

gsutil mb $BUCKET_URI

bold "Configuring pub/sub from $GCS_TOPIC -> $GCS_SUB..."

gsutil notification create -t $GCS_TOPIC -f json $BUCKET_URI
gcloud pubsub subscriptions create $GCS_SUB --topic $GCS_TOPIC

bold "Creating your cluster $GKE_CLUSTER..."

gcloud container clusters create $GKE_CLUSTER --zone $ZONE \
  --service-account $SA_EMAIL \
	--username admin --cluster-version 1.8.8-gke.0 \
	--machine-type n1-standard-4 --image-type COS --disk-size 100 \
	--num-nodes 3 --enable-cloud-logging --enable-cloud-monitoring

gcloud container clusters get-credentials $GKE_CLUSTER --zone $ZONE

bold "Deploying spinnaker..."

sed -ie 's|{%SPIN_GCS_ACCOUNT%}|'$SPIN_GCS_ACCOUNT'|g' manifests.yml
sed -ie 's|{%SPIN_PUB_SUB%}|'$SPIN_PUB_SUB'|g' manifests.yml
sed -ie 's|{%GCS_SUB%}|'$GCS_SUB'|g' manifests.yml
sed -ie 's|{%PROJECT_ID%}|'$PROJECT_ID'|g' manifests.yml
sed -ie 's|{%BUCKET_URI%}|'$BUCKET_URI'|g' manifests.yml

kubectl apply -f manifests.yml

sleep 30

bold "Waiting for spinnaker setup to complete (this might take some time)..."

job_ready() {
  kubectl get job $1 -n spinnaker -o jsonpath="{.status.succeeded}"
}

while [[ "$(job_ready create-spinnaker-app)" != "1" ]]; do
  printf "."
  sleep 5
done

while [[ "$(job_ready create-spinnaker-pipeline)" != "1" ]]; do
  printf "."
  sleep 5
done

bold "Ready! run ./connect.sh to continue..."

