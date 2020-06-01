#!/usr/bin/env bash
#
# STACK FUNCTIONS
#
stack_list_app () {
    # List all stacks of the same type as the app you are administering
    aws cloudformation describe-stacks \
        --region ${AWS_REGION} \
        --query "Stacks[?contains (StackName, '${APP_NAME}')].StackName" \
        --output text
    return $?
}

stack_list_all () {
    aws cloudformation describe-stacks \
        --region ${AWS_REGION} \
        | jq -r '.Stacks[].StackName' \
        | sort
}

stack_list_all_parents () {
    aws cloudformation list-stacks \
        --region ${AWS_REGION} \
        --stack-status-filter UPDATE_COMPLETE CREATE_COMPLETE ROLLBACK_COMPLETE \
        --query "StackSummaries[?not_null(TemplateDescription)].StackName" \
        | jq -r '.[]' \
        | sort
}

stack_list_others () {
    # List every stack in an account, except the one we are administering..
    local stack_name=$1
    local all_stacks=($(stack_list_all))

    local stack
    for stack in ${all_stacks[@]/^$stack_name$}; do
        echo "${stack}"
    done
}

stack_name_from_vpc_id () {
    # Return the ${stack_name} of ${vpc_id}
    local vpc_id=$1

    local stack_name=$(aws ec2 describe-vpcs \
        --region ${AWS_REGION} \
        --filters Name=vpc-id,Values=${vpc_id} \
        --query "Vpcs[].Tags[?Key=='aws:cloudformation:stack-name'].Value" \
        --output text)

    if [[ ! ${stack_name-} ]]; then
        echoerr "ERROR: Could not resolve 'aws:cloudformation:stack-name' from vpc '${vpc_id}"
        return 1
    else
        echo ${stack_name}
        return 0
    fi
}

stack_parameter_file () {
    local environment=$1
    echo "params/${environment}.sh"
}

stack_parameter_file_convert () {
    local environment=$1

    local yaml_file="moonshot/params/${environment}.yml"
    local param_file="$(stack_parameter_file ${environment})"

    # TODO Remove this after moonshot is gone
    # This is dirty if the source yaml file contains anything other than key
    # value pairs, but for us, this is not a thing, so should be fine, right?
    if [[ -f ${yaml_file} ]] && [[ ! -f ${param_file} ]]; then
        echoerr "INFO: Converting '${yaml_file}'"
        mkdir -p params
        sed \
            -e '/---/d' \
            -e "s/'//g" \
            -e 's/^\([a-zA-Z0-9]*\):[ ]*/\1\="/g' \
            -e 's/$/"/g' \
            ${yaml_file} >${param_file}
    fi
}

stack_parameter_file_parse () {
    local param_file=$1
    local param_var=$2

    if ! typeset -Ap ${param_var} >&/dev/null; then
        echoerr "ERROR: '${param_var}' is not an associative array"
        return 1
    fi

    local line param_key param_value
    while read line; do
        param_key=${line%%=*}
        param_value=${line#*=}
        eval ${param_var}[${param_key}]=${param_value}
    done <${param_file}
}

stack_parameter_set () {
    local stack_name=$1
    local parameter_key=$2
    local parameter_value=$3

    local parameters=($(aws cloudformation get-template-summary \
        --region ${AWS_REGION} \
        --stack-name ${stack_name}  \
        | jq -r '.Parameters[].ParameterKey'))

    if ! contains ${parameter_key} ${parameters[@]}; then
        echoerr "ERROR: Can not update non-existant parameter '${parameter_key}' with '${parameter_value}'"
        return 1
    fi

    local parameter parameter_json
    for parameter in ${parameters[@]}; do
        if [[ ${parameter} == ${parameter_key} ]]; then
            parameter_json+=",{\"ParameterKey\":\"${parameter}\",\"ParameterValue\":\"${parameter_value}\"}"
        else
            parameter_json+=",{\"ParameterKey\":\"${parameter}\",\"UsePreviousValue\":true}"
        fi
    done

    aws cloudformation update-stack \
        --region ${AWS_REGION} \
        --stack-name ${stack_name} \
        --parameters "[${parameter_json#,}]" \
        --use-previous-template \
        --capabilities CAPABILITY_IAM \
        >/dev/null

    return $?
}

stack_resource_id () {
    # Return a string of the ${resource_id} inside ${stack_name}
    local stack_name=$1
    local resource=$2

    local resource_id=$(aws cloudformation describe-stack-resource \
        --region ${AWS_REGION} \
        --stack-name ${stack_name} \
        --logical-resource-id ${resource} \
        --query "StackResourceDetail.PhysicalResourceId" \
        --output text)

    if [[ ${resource_id-} ]]; then
        echo ${resource_id}
        return 0
    else
        echoerr "ERROR: Could not resolve resource '${resource}' from stack '${stack_name}'"
        return 1
    fi
}

stack_resource_type_id () {
    # Return an array of resource ids of type ${resource_type}.
    local stack_name=$1
    local resource_type=$2

    local -a resource_ids=($(aws cloudformation list-stack-resources \
        --region ${AWS_REGION} \
        --stack-name "${stack_name}" \
        --query "StackResourceSummaries[?ResourceType=='${resource_type}'].PhysicalResourceId" \
        --output text))

    if [[ -z ${resource_ids[@]-} ]]; then
        echoerr "WARNING: No resources of type ${resource_type} found"
        return 1
    else
        echo ${resource_ids[@]}
        return 0
    fi
}
# TODO: Remove this once all the things have been updated to not need it.
alias stack_resource_type=stack_resource_type_id

stack_resource_type_name () {
    # Return an array of resource names of type ${resource_type}.
    local stack_name=$1
    local resource_type=$2

    local -a resource_names=($(aws cloudformation list-stack-resources \
        --region ${AWS_REGION} \
        --stack-name "${stack_name}" \
        --query "StackResourceSummaries[?ResourceType=='${resource_type}'].LogicalResourceId" \
        --output text))

    if [[ -z ${resource_names[@]-} ]]; then
        echoerr "WARNING: No resources of type ${resource_type} found"
        return 1
    else
        echo ${resource_names[@]}
        return 0
    fi
}

stack_status_ok () {
    local -a status_complete=(
        UPDATE_COMPLETE
        CREATE_COMPLETE
        ROLLBACK_COMPLETE
        UPDATE_ROLLBACK_COMPLETE
    )
    echo ${status_complete[@]}
}

stack_value () {
    # Return the ${resource_id} as string for the {Input,Parameter,Output} of a
    # named ${resource}
    local stack_name=$1
    local resource=$2
    local param=$3

    local resource_id=$(aws cloudformation describe-stacks \
        --region ${AWS_REGION} \
        --stack-name ${stack_name} \
        --query "Stacks[].${param}s[?${param}Key=='${resource}'].${param}Value" \
        --output text)

    if [[ ${resource_id-} ]]; then
        echo "${resource_id}"
        return 0
    else
        echoerr "ERROR: Could not resolve '${param}' resource '${resource}' from stack '${stack_name}'"
        return 1
    fi
}

stack_value_input () {
    # Return resource_id for the Input ${resource} in ${stack_name}
    local stack_name=$1
    local resource=$2
    stack_value "${stack_name}" "${resource}" Input
    return $?
}

stack_value_parameter () {
    # Return resource_id for the Parameter ${resource} in ${stack_name}
    local stack_name=$1
    local resource=$2
    stack_value "${stack_name}" "${resource}" Parameter
    return $?
}

stack_value_output () {
    # Return resource_id for the Output ${resource} in ${stack_name}
    local stack_name=$1
    local resource=$2
    stack_value "${stack_name}" "${resource}" Output
    return $?
}

