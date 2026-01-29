FROM registry.access.redhat.com/ubi9/ubi:latest

RUN yum install -y python3.12 python3.12-pip
RUN alternatives --install /usr/bin/python3 python3 /usr/bin/python3.9 10
RUN alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 20
RUN alternatives --set python3 /usr/bin/python3.12
RUN curl -Lso /usr/local/bin/jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 && chmod +x /usr/local/bin/jq
RUN curl -Lso /usr/local/bin/yq https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64 && chmod +x /usr/local/bin/yq

ENV INSTALL_METHOD=helm
ENV ENABLE_ORCHESTRATOR=false
ENV GROUP_COUNT=10
ENV BACKSTAGE_USER_COUNT=10
ENV RBAC_POLICY_SIZE=10
ENV RBAC_POLICY=all_groups_admin
ENV WORKDIR=/tmp
ENV OUTPUT_PATH=/rbac-data/

COPY generate-rbac-policy-csv.sh $WORKDIR/generate-rbac-policy-csv.sh
COPY common.sh $WORKDIR/common.sh
COPY template/backstage/complex-rbac-config.yaml $WORKDIR/complex-rbac-config.yaml
COPY template/backstage/helm/orchestrator-rbac-patch.yaml $WORKDIR/orchestrator-rbac-patch.yaml
COPY template/backstage/helm/complex-orchestrator-rbac-patch.yaml $WORKDIR/complex-orchestrator-rbac-patch.yaml

WORKDIR $WORKDIR
RUN chmod +x $WORKDIR/generate-rbac-policy-csv.sh
RUN chmod +x $WORKDIR/common.sh

CMD ["./generate-rbac-policy-csv.sh"]

