#!/usr/bin/env bash

DECK_POD=$(kubectl get po -n spinnaker -l "cluster=spin-deck" \
  -o jsonpath="{.items[0].metadata.name}")

kubectl port-forward $DECK_POD 8080:9000 -n spinnaker >> /dev/null &

echo "Port opened on 8080"
