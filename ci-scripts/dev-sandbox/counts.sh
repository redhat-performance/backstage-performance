#!/bin/bash

for i in backstages secrets configmaps pods jobs; do
    echo "$i,$(oc get "$i" -A -o name | wc -l)"
done
