#!/bin/bash

set -euxo pipefail

DIRNAME="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $DIRNAME

INSTANCE_SUFFIX=${1:-instance0}
INSTANCE_NAME="lighthouse-collection-$INSTANCE_SUFFIX"
CLOUDSDK_CORE_PROJECT=${LIGHTHOUSE_COLLECTION_GCLOUD_PROJECT:-lighthouse-lantern-collect}
LIGHTHOUSE_GIT_REF=${TARGET_GIT_REF:-master}
NUMBER_OF_RUNS=${TARGET_RUNS:-1}
ZONE=us-central1-a

gcloud --project="$CLOUDSDK_CORE_PROJECT" compute instances create $INSTANCE_NAME \
  --image-family=ubuntu-1804-lts --image-project=ubuntu-os-cloud \
  --zone="$ZONE" \
  --boot-disk-size=200GB \
  --machine-type=n1-standard-2

cat > .tmp_env <<EOF
export NUMBER_OF_RUNS=$NUMBER_OF_RUNS
export LIGHTHOUSE_GIT_REF=$LIGHTHOUSE_GIT_REF
export BASE_LIGHTHOUSE_FLAGS="--max-wait-for-load=90000"
EOF

# Instance needs time to start up.
until gcloud --project="$CLOUDSDK_CORE_PROJECT" compute scp ./.tmp_env $INSTANCE_NAME:/tmp/lhenv --zone="$ZONE"
do
  echo "Waiting for start up ..."
  sleep 10
done
rm .tmp_env

gcloud --project="$CLOUDSDK_CORE_PROJECT" compute scp ./gcp-setup.sh $INSTANCE_NAME:/tmp/setup-machine.sh --zone="$ZONE"
gcloud --project="$CLOUDSDK_CORE_PROJECT" compute scp ./urls.txt $INSTANCE_NAME:/tmp/urls.txt --zone="$ZONE"
gcloud --project="$CLOUDSDK_CORE_PROJECT" compute scp ./gcp-run.sh $INSTANCE_NAME:/tmp/run.sh --zone="$ZONE"
gcloud --project="$CLOUDSDK_CORE_PROJECT" compute scp ./gcp-run-on-url.sh $INSTANCE_NAME:/tmp/run-on-url.sh --zone="$ZONE"
gcloud --project="$CLOUDSDK_CORE_PROJECT" compute ssh $INSTANCE_NAME --command="bash /tmp/setup-machine.sh" --zone="$ZONE"
gcloud --project="$CLOUDSDK_CORE_PROJECT" compute ssh lighthouse@$INSTANCE_NAME --command="sh -c 'nohup /home/lighthouse/run.sh > /home/lighthouse/collect.log 2>&1 < /dev/null &'" --zone="$ZONE"

set +x

echo "Collection has started."
echo "Check-in on progress anytime by running..."
echo "  $ gcloud --project="$CLOUDSDK_CORE_PROJECT" compute ssh lighthouse@$INSTANCE_NAME --command='tail -f collect.log' --zone=$ZONE"

echo "When complete run..."
echo "  For LHR + trace data for -A replication"
echo "  $ gcloud --project="$CLOUDSDK_CORE_PROJECT" compute scp $INSTANCE_NAME:/home/lighthouse/trace-data.tar.gz ./trace-data.tar.gz"
echo "  For LHR data for smaller transfer sizes replication"
echo "  $ gcloud --project="$CLOUDSDK_CORE_PROJECT" compute scp $INSTANCE_NAME:/home/lighthouse/lhr-data.tar.gz ./lhr-data.tar.gz"
echo "  To delete the instance"
echo "  $ gcloud --project="$CLOUDSDK_CORE_PROJECT" compute instances delete $INSTANCE_NAME"
