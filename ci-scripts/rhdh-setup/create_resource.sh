#/bin/bash

create_per_grp() {
  varname=$2
  obj_count=${!varname}
  if [[ -z ${!varname}  ]] ; then
    echo "$varname is not set: Skipping $1 ";
    exit 1
  fi
  local iter_count=`echo "(${obj_count}/${GROUP_COUNT})"|bc`
  local mod=`echo "(${obj_count}%${GROUP_COUNT})"|bc`

  if [[ ! ${mod} -eq 0 ]] ; then
    iter_count=`echo "${iter_count}+1"|bc`
  fi
  indx=0
  for i in `seq 1 $((${iter_count}))`; do
    for j in `seq 1 $((${GROUP_COUNT}))`; do
      indx=$((1+indx))
      [[  ${obj_count} -lt $indx ]] && break
      local out=$(${1} ${j} ${indx}) 
    done
  done
}

clone_and_upload() {
  export backstage_url="https://$(oc get routes ${RHDH_HELM_RELEASE_NAME}-developer-hub -n ${RHDH_NAMESPACE} -o jsonpath='{.spec.host}')"
  git_str="${GITHUB_USER}:${GITHUB_TOKEN}@github.com"
  base_name=`basename $GITHUB_REPO`
  git_dir=${base_name%%.*}
  git_repo=`echo $GITHUB_REPO|sed  -e "s/github.com/${git_str}/g"`
  [[ -d ${git_dir} ]] && rm -rf ${git_dir}
  git clone $git_repo
  cd $git_dir
  tmp_branch=`mktemp -u XXXXXXXXXX`
  git checkout -b $tmp_branch
  mv ../${1} .
  git add ${1}
  git commit -a -m "commit objects"
  git push -f --set-upstream origin $tmp_branch
  cd ..
  sleep 5
  upload_url=${GITHUB_REPO%.*}/blob/${tmp_branch}/${1}
  curl -k ${backstage_url}'/api/catalog/locations' -X POST -H 'Accept-Encoding: gzip, deflate, br' -H 'Content-Type: application/json' --data-raw '{"type":"url","target":"'"${upload_url}"'"}'
}

create_api() {
  export grp_indx=$1	
  export api_indx=$2
  cat template/component/api.template | envsubst '${grp_indx} ${api_indx}'>> api.yaml
}

create_cmp() {
  export grp_indx=$1	
  export cmp_indx=$2
  cat template/component/component.template | envsubst '${grp_indx} ${cmp_indx}'>> component.yaml
}

create_group() {
  token=`cat /tmp/token`
  curl -s -k --location --request POST ${keycloak_url}'/auth/admin/realms/backstage/groups' \
	  -H 'Content-Type: application/json' \
	   -H 'Authorization: Bearer '$token \
	   --data-raw '{"name": "group'"${0}"'"}'
}

create_groups() {
  echo "Creating Groups in Keycloak"
  export keycloak_url="https://$(oc get routes keycloak -n ${RHDH_NAMESPACE} -o jsonpath='{.spec.host}')"
  export keycloak_pass=$(oc -n ${RHDH_NAMESPACE} get secret credential-example-sso -o template --template='{{.data.ADMIN_PASSWORD}}'|base64  -d)
  export -f get_token
  nohup bash -c  'get_token' &
  refresh_pid=$!
  sleep 5
  export -f create_group
  seq 1 ${GROUP_COUNT}| xargs  -n1 -P10 bash -c 'create_group'
  kill $refresh_pid
}

create_user() {
  token=`cat /tmp/token`
  grp=`echo "${0}%${GROUP_COUNT}"|bc`
  [[ $grp -eq 0  ]]  && grp=${GROUP_COUNT}
  curl -s -k --location --request POST ${keycloak_url}'/auth/admin/realms/backstage/users' \
   -H 'Content-Type: application/json' \
   -H 'Authorization: Bearer '$token \
   --data-raw '{"firstName":"test'"${0}"'","lastName":"tester", "email":"test'"${0}"'@test.com", "enabled":"true", "username":"test'"${0}"'","groups":["/group'"${grp}"'"]}'
}

create_users() {
  echo "Creating Users in Keycloak"
  export keycloak_url="https://$(oc get routes keycloak -n ${RHDH_NAMESPACE} -o jsonpath='{.spec.host}')"
  export keycloak_pass=$(oc -n ${RHDH_NAMESPACE} get secret credential-example-sso -o template --template='{{.data.ADMIN_PASSWORD}}'|base64  -d)
  export -f get_token
  export GROUP_COUNT
  nohup bash -c  'get_token' &
  refresh_pid=$!
  sleep 5
  export -f create_user
  seq 1 ${BACKSTAGE_USER_COUNT}| xargs  -n1 -P10 bash -c 'create_user'
  kill $refresh_pid
}

get_token() {
  while true; do 
    echo -n $(curl -s  -k  ${keycloak_url}/auth/realms/master/protocol/openid-connect/token   -d "username=admin"  -d "password="${keycloak_pass} -d 'grant_type=password' -d 'client_id=admin-cli' | jq -r .access_token)>/tmp/token
    sleep 30
  done
}
