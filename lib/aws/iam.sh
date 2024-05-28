#!/usr/bin/env bash
#
# Identity and Access Management
#

_iam_test_group () {
    if [[ $# -lt 1 ]] ;then
        echoerr "Usage: ${FUNCNAME[0]} IAM_GROUP"
        return 1
    fi
    local iam_group="$1"

    [[ -z ${iam_user} ]] \
        && echoerr "ERROR: IAM group must be provided" \
        && return 1

    if contains ${iam_group} $(iam_groups); then
        return 0
    else
        return 1
    fi
}

_iam_test_user () {
    if [[ $# -lt 1 ]] ;then
        echoerr "Usage: ${FUNCNAME[0]} IAM_USER"
        return 1
    fi
    local iam_user="$1"

    [[ -z ${iam_user} ]] \
        && echoerr "ERROR: IAM username must be provided" \
        && return 1

    if contains ${iam_user} $(iam_users); then
        return 0
    else
        return 1
    fi
}

iam_access_key_create () {
    if [[ $# -lt 1 ]] ;then
        echoerr "Usage: ${FUNCNAME[0]} IAM_USER"
        return 1
    fi
    local iam_user="$1"

    if _iam_test_user ${iam_user-}; then
        echoerr "INFO: Creating API key and secret for: ${iam_user}"
        aws iam create-access-key \
            --user-name ${iam_user} \
            --query "AccessKey.{AccessKeyId:AccessKeyId,SecretAccessKey:SecretAccessKey}"
    fi
}

iam_access_key_delete () {
    if [[ $# -lt 2 ]] ;then
        echoerr "Usage: ${FUNCNAME[0]} IAM_USER ACCESS_KEY_ID"
        return 1
    fi
    local iam_user="$1"
    local access_key="$2"

    if ! _iam_test_user ${iam_user-}; then
        return 1
    elif [[ -z ${access_key-} ]]; then
        return 1
    fi

    aws iam delete-access-key \
        --user-name ${iam_user} \
        --access-key-id ${access_key}
}

iam_access_key_list () {
    if [[ $# -lt 1 ]] ;then
        echoerr "Usage: ${FUNCNAME[0]} IAM_USER"
        return 1
    fi
    local iam_user="$1"

    if ! _iam_test_user ${iam_user-}; then
        return 1
    fi

    aws iam list-access-keys \
        --user-name ${iam_user} \
        --query "AccessKeyMetadata[].AccessKeyId" \
        --output text
}

iam_group_users () {
    if [[ $# -lt 1 ]] ;then
        echoerr "Usage: ${FUNCNAME[0]} GROUP_NAME"
        return 1
    fi
    local group_name="$1"

    aws iam get-group \
        --group-name ${group_name} \
        | jq -r '.Users.[].UserName'
}

iam_groups () {
    aws iam list-groups \
        --query "Groups[].GroupName" \
        --output text
}

iam_policy_get () {
    if [[ $# -lt 1 ]] ;then
        echoerr "Usage: ${FUNCNAME[0]} STACK_NAME POLICY_NAME"
        return 1
    fi
    local stack_name="$1"
    local policy_name="$2"

    local policy=$(iam_policy_list_name ${stack_name} ${policy_name})

    if [[ -z ${policy-} ]]; then
        echoerr "ERROR: Can not find policy in stack: ${policy_name}"
        return 1
    fi

    local policy_arn=$(echo ${policy} \
        | jq -r '.Arn')

    local policy_version=$(echo ${policy} \
        | jq -r '.DefaultVersionId')

    aws iam get-policy-version \
        --policy-arn ${policy_arn} \
        --version-id ${policy_version}
}

iam_policy_list_aws () {
    aws iam list-policies \
        --scope AWS \
        | jq -r '.Policies | sort | .[].PolicyName'
}

iam_policy_list_customer () {
    aws iam list-policies \
        --scope Local \
        | jq -r '.Policies | sort | .[].PolicyName'
}

iam_policy_list_name () {
    if [[ $# -lt 2 ]] ;then
        echoerr "Usage: ${FUNCNAME[0]} STACK_NAME POLICY_NAME"
        return 1
    fi
    local stack_name="$1"
    local policy_name="$2"

    aws iam list-policies \
        --path-prefix "/${stack_name}/" \
        --scope Local \
        | jq ".Policies[] | select(.PolicyName == \"${policy_name}\")"
}

iam_policy_list_path () {
    if [[ $# -lt 1 ]] ;then
        echoerr "Usage: ${FUNCNAME[0]} STACK_NAME"
        return 1
    fi
    local stack_name=$1

    aws iam list-policies \
        --path-prefix "/${STACK_NAME}/" \
        --scope Local \
        | jq -r '.Policies | sort | .[].PolicyName'
}

iam_user_arn () {
    if [[ $# -lt 1 ]] ;then
        echoerr "Usage: ${FUNCNAME[0]} IAM_USER"
        return 1
    fi
    local iam_user="$1"

    aws iam get-user \
        --user-name ${iam_user} \
        --query "User.Arn" \
        --output text
}

iam_user_create () {
    if [[ $# -lt 1 ]] ;then
        echoerr "Usage: ${FUNCNAME[0]} IAM_USER"
        return 1
    fi
    local iam_user="$1"

    if ! _iam_test_user ${iam_user-}; then
        echoerr "INFO: Creating user '${iam_user}'"
        aws iam create-user --user-name ${iam_user}
    fi

    return $?
}

iam_user_exists () {
    if [[ $# -lt 1 ]] ;then
        echoerr "Usage: ${FUNCNAME[0]} IAM_USER"
        return 1
    fi
    local iam_user="$1"

    _iam_test_user ${iam_user-}

    return $?
}

iam_user_group_add () {
    if [[ $# -lt 2 ]] ;then
        echoerr "Usage: ${FUNCNAME[0]} IAM_USER IAM_GROUP"
        return 1
    fi
    local iam_user="$1"
    local iam_group="$2"

    if _iam_test_group ${iam_group-}; then
        aws iam add-user-to-group \
            --group-name ${iam_group} \
            --user-name ${iam_user}
        return $?
    else
        return 1
    fi
}

iam_user_group_del () {
    if [[ $# -lt 2 ]] ;then
        echoerr "Usage: ${FUNCNAME[0]} IAM_USER IAM_GROUP"
        return 1
    fi
    local iam_user="$1"
    local iam_group="$2"

    if _iam_test_group ${iam_group-}; then
        aws iam remove-user-from-group \
            --group-name ${iam_group} \
            --user-name ${iam_user}
        return $?
    else
        return 1
    fi
}

iam_user_group_list () {
    if [[ $# -lt 1 ]] ;then
        echoerr "Usage: ${FUNCNAME[0]} IAM_USER"
        return 1
    fi
    local iam_user="$1"

    aws iam list-groups-for-user \
        --user-name ${iam_user} \
        --query "Groups[].GroupName" \
        --output text

    return $?
}

iam_user_mfa_devices () {
    if [[ $# -lt 1 ]] ;then
        echoerr "Usage: ${FUNCNAME[0]} IAM_USER"
        return 1
    fi
    local iam_user="$1"

    aws iam list-mfa-devices \
        --user-name ${iam_user} \
        --query 'MFADevices[].SerialNumber' \
        --output text
}

iam_user_policies () {
    if [[ $# -lt 1 ]] ;then
        echoerr "Usage: ${FUNCNAME[0]} IAM_USER"
        return 1
    fi
    local iam_user="$1"

    aws iam list-attached-user-policies \
        --user-name ${iam_user} \
        --query 'AttachedPolicies[].PolicyArn' \
        --output text
}

iam_user_ssc () {
    if [[ $# -lt 1 ]] ;then
        echoerr "Usage: ${FUNCNAME[0]} IAM_USER"
        return 1
    fi
    local iam_user="$1"

    aws iam list-service-specific-credentials \
        --user-name ${iam_user} \
        --query 'ServiceSpecificCredentials[].ServiceSpecificCredentialId' \
        --output text
}

iam_user_ssh_keys () {
    if [[ $# -lt 1 ]] ;then
        echoerr "Usage: ${FUNCNAME[0]} IAM_USER"
        return 1
    fi
    local iam_user="$1"

    aws iam list-ssh-public-keys \
        --user-name ${iam_user} \
        --query 'SSHPublicKeys[].SSHPublicKeyId' \
        --output text
}

iam_users () {
    aws iam list-users \
        --query "Users[].UserName" \
        --output text
}

