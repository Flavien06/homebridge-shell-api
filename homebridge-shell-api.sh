#!/bin/bash

HOME_BRIDGE_IP="localhost:8581"
USERNAME="$homebridge_username"
PASSWORD="$homebridge_password"
TOKEN_FILE="$HOME/.homebridge_login"
JSON_FILE="$HOME/.homebridge.json"
MAX_FILE_AGE=30  # 30 days

# Function to obtain a new authentication token
get_new_token() {
    local new_token
    new_token=$(curl -s -X POST -H "accept: */*" -H "Content-Type: application/json" -d "{\"username\": \"$USERNAME\", \"password\": \"$PASSWORD\", \"otp\": \"string\"}" http://$HOME_BRIDGE_IP/api/auth/login | jq -r '.access_token')
    if [ -z "$new_token" ]; then
        echo "Failed to obtain the authentication token."
        exit 1
    else
		echo "$new_token" > "$TOKEN_FILE"
    fi
}

# Function to check the validity of the token
check_token_validity() {
    local token_to_check="$1"
    if ! curl -sSf -H "Authorization: Bearer $token_to_check" http://$HOME_BRIDGE_IP/api/auth/check > /dev/null; then
        return 1
    fi
    return 0
}

get_jsonfile() {
    # Retrieving the list of accessories
    curl_output=$(curl -s -X GET -H "Authorization: Bearer $AUTH_TOKEN" http://$HOME_BRIDGE_IP/api/accessories)
	# Saving the response in a temporary file
	echo "$curl_output" | jq '.' > "$JSON_FILE"
}

get_uniqueid() {
    # Retrieving the uniqueId from the AID
    UNIQUE_ID=$(jq -r --argjson aid "$AID" '.[] | select(.aid == $aid) | .uniqueId' "$JSON_FILE")
    if [ -z "$UNIQUE_ID" ]; then
        echo "AID not found in the JSON file."
        exit 1
    fi
	# echo "$UNIQUE_ID"
}

get_help() {
    echo "Usage: $0"
    echo -e "\t[put <UNIQUE_ID> <CHARACTERISTIC_TYPE> <NEW_VALUE>]:\tModify a characteristic"
    echo -e "\t[get <UNIQUE_ID>]:\tGet the value of a characteristic"
    echo -e "\t[info <UNIQUE_ID>]:\tGet detailed information about a device"
    echo -e "\t[jsonid <UNIQUE_ID>]:\tGet JSON details specific to a device"
    echo -e "\t[json]:\t\t\tGet all accessories in JSON format"
    echo -e "\t[id <AID>]:\t\tGet information about a specific accessory via its AID"
    exit 1
}


# Checking if the token file exists and loading the token if present
if [ -f "$TOKEN_FILE" ]; then
    AUTH_TOKEN=$(cat "$TOKEN_FILE")
    if ! check_token_validity "$AUTH_TOKEN"; then
        echo "The token is no longer valid. Obtaining a new token..."
        get_new_token
        AUTH_TOKEN=$(cat "$TOKEN_FILE")
    fi
else
    get_new_token
    AUTH_TOKEN=$(cat "$TOKEN_FILE")
fi


# Checking if the JSON file exists and has been modified more than $MAX_FILE_AGE days ago
if [ ! -f "$JSON_FILE" ] || [ $(find "$JSON_FILE" -mtime +$MAX_FILE_AGE 2>/dev/null) ]; then
    echo "The JSON file does not exist or has not been modified in more than $MAX_FILE_AGE days. Retrieving new data..."
	get_jsonfile
# else
    # echo "The JSON file has been modified less than $MAX_FILE_AGE days ago."
fi


case "$1" in
	"json")
		get_jsonfile
		echo "$curl_output" | jq '.'
        ;;	
	"jsonid")
		[ -z "$2" ] && get_help
		AID="$2"
		get_uniqueid
		# Retrieving information for the device
		curl_output=$(curl -s -X GET -H "Authorization: Bearer $AUTH_TOKEN" http://$HOME_BRIDGE_IP/api/accessories/$UNIQUE_ID)
		# Displaying information in JSON
		echo "$curl_output" | jq '.'
		;;
		
	"id")
		[ -z "$2" ] && get_help
		AID="$2"
		RESULT=$(jq -r ".[] | select(.aid == $AID) | {uniqueId: .uniqueId, serviceName: .serviceName, aid: .aid}" "$JSON_FILE")
		if [ ! -z "$RESULT" ]; then
			serviceName=$(echo "$RESULT" | jq -r '.serviceName')
			serviceName=$(echo "$RESULT" | jq -r '.serviceName')
			aid=$(echo "$RESULT" | jq -r '.aid')
			uniqueId=$(echo "$RESULT" | jq -r '.uniqueId')
			echo "serviceName: $serviceName"
			echo "aid: $aid"
			echo "uniqueId: $uniqueId"
		else
			echo "No information found for AID $2."
		fi
		;;
		
	"get_value") #To get the value from the description name
		[ -z "$2" ] || [ -z "$3" ] && get_help
		AID="$2"
		CHARACTERISTIC_TYPE="$3"
		get_uniqueid
		# Retrieving information for the device
		curl_output=$(curl -s -X GET -H "Authorization: Bearer $AUTH_TOKEN" http://$HOME_BRIDGE_IP/api/accessories/$UNIQUE_ID)
		# Getting the value for the specified characteristic type
		VALUE=$(echo "$curl_output" | jq -r --arg type "$CHARACTERISTIC_TYPE" '.serviceCharacteristics[] | select(.description == $type) | .value')
		# Displaying the value
		echo "$VALUE"
		;;
	
	"info")
        [ -z "$2" ] && get_help
        AID="$2"
        get_uniqueid
        # Retrieving information for the device
        curl_output=$(curl -s -X GET -H "Authorization: Bearer $AUTH_TOKEN" http://$HOME_BRIDGE_IP/api/accessories/$UNIQUE_ID)
		service_name=$(echo "$curl_output" | jq -r '.serviceName')
		# Displaying information for the device
		echo "Information for device $service_name [AID $AID] :"
		echo "$curl_output" | jq --tab '.values | to_entries[] | "\(.key): \(.value)"'
		;;
	
     "get")
        [ -z "$2" ] || [ -z "$3" ] && get_help
        AID="$2"
        CHARACTERISTIC_TYPE="$3"
        get_uniqueid
        # Retrieving information for the device
        curl_output=$(curl -s -X GET -H "Authorization: Bearer $AUTH_TOKEN" http://$HOME_BRIDGE_IP/api/accessories/$UNIQUE_ID)
        # Getting the value for the specified characteristic type
        VALUE=$(echo "$curl_output" | jq -r --arg type "$CHARACTERISTIC_TYPE" '.values[$type]')
        # Displaying the value
		if [ "$VALUE" != "null" ]; then
			echo "$VALUE"
		else
			# Retrieving the JSON structure of the values
			values_structure=$(echo "$curl_output" | jq -r '.values')
			# Extracting keys (names of characteristics) from the JSON structure
			valid_characteristic=$(echo "$values_structure" | jq -r 'keys_unsorted[]')
			echo "Error: Invalid characteristic Type. Valid types are:"
			echo "$valid_characteristic"
			exit 0
		fi
        ;;
			
	"put" | "set" )
		[ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] && get_help
		AID="$2"
		CHARACTERISTIC_TYPE="$3"
		NEW_VALUE="$4"
		get_uniqueid
        # Retrieving information for the device
        curl_output=$(curl -s -X GET -H "Authorization: Bearer $AUTH_TOKEN" http://$HOME_BRIDGE_IP/api/accessories/$UNIQUE_ID)
        
        # Checking the ability to write (canWrite) for the specific characteristic
        # CAN_WRITE=$(echo "$curl_output" | jq -r --arg type "$CHARACTERISTIC_TYPE" '.serviceCharacteristics[] | select(.type == $type) | .canWrite')
		# if [ -z "$CAN_WRITE" ]; 			then echo "The characteristic $CHARACTERISTIC_TYPE does not exist." && exit 1
		# elif [ "$CAN_WRITE" != "true" ]; 	then echo "The characteristic $CHARACTERISTIC_TYPE cannot be modified." && exit 1
		# fi

        response=$(curl -s -X PUT -H "Content-Type: application/json" -H "Authorization: Bearer $AUTH_TOKEN" -d "{\"characteristicType\": \"$CHARACTERISTIC_TYPE\", \"value\": \"$NEW_VALUE\"}" http://$HOME_BRIDGE_IP/api/accessories/$UNIQUE_ID)
		# Checking for the presence of the "error" field in the response
		if ! echo "$response" | grep '.error' >/dev/null; then
			echo "Successful modification: $CHARACTERISTIC_TYPE to the value $NEW_VALUE"
		else
			error_message=$(echo "$response" | jq -r '.message')
			echo "$error_message"
		fi
		;;
	*)
        get_help
        ;;
esac
