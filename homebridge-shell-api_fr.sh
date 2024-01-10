#!/bin/bash
HOME_BRIDGE_IP="localhost:8581"
USERNAME="$homebridge_username"
PASSWORD="$homebridge_password"
TOKEN_FILE="$HOME/.homebridge_login"
JSON_FILE="$HOME/.homebridge.json"
MAX_FILE_AGE=30  # 30 jours

# Fonction pour obtenir un nouveau token d'authentification
get_new_token() {
    local new_token
    new_token=$(curl -s -X POST -H "accept: */*" -H "Content-Type: application/json" -d "{\"username\": \"$USERNAME\", \"password\": \"$PASSWORD\", \"otp\": \"string\"}" http://$HOME_BRIDGE_IP/api/auth/login | jq -r '.access_token')
    if [ -z "$new_token" ]; then
        echo "Échec de l'obtention du token d'authentification."
        exit 1
    else
		echo "$new_token" > "$TOKEN_FILE"
    fi
}

# Fonction pour vérifier la validité du token
check_token_validity() {
    local token_to_check="$1"
    if ! curl -sSf -H "Authorization: Bearer $token_to_check" http://$HOME_BRIDGE_IP/api/auth/check > /dev/null; then
        return 1
    fi
    return 0
}

get_jsonfile() {
    # Récupération de la liste des accessoires
    curl_output=$(curl -s -X GET -H "Authorization: Bearer $AUTH_TOKEN" http://$HOME_BRIDGE_IP/api/accessories)
	# Enregistrement de la réponse dans un fichier temporaire
	echo "$curl_output" | jq '.' > "$JSON_FILE"
}

get_uniqueid() {
    # Récupération du uniqueId à partir de l'AID
    UNIQUE_ID=$(jq -r --argjson aid "$AID" '.[] | select(.aid == $aid) | .uniqueId' "$JSON_FILE")
    if [ -z "$UNIQUE_ID" ]; then
        echo "AID non trouvé dans le fichier JSON."
        exit 1
    fi
	# echo "$UNIQUE_ID"
}

get_help() {
    echo "Usage: $0"
    echo -e "\t[put <UNIQUE_ID> <CHARACTERISTIC_TYPE> <NEW_VALUE>]:\tModifier une caractéristique"
    echo -e "\t[get <UNIQUE_ID>]:\tObtenir la valeur d'une caractéristique"
    echo -e "\t[info <UNIQUE_ID>]:\tObtenir des informations détaillées sur un dispositif"
    echo -e "\t[jsonid <UNIQUE_ID>]:\tObtenir des détails JSON spécifiques à un dispositif"
    echo -e "\t[json]:\t\t\tObtenir l'ensemble des accessoires au format JSON"
    echo -e "\t[id <AID>]:\t\tObtenir des informations sur un accessoire spécifique via son AID"
    exit 1
}


# Vérification si le fichier du token existe et charge le token s'il est présent
if [ -f "$TOKEN_FILE" ]; then
    AUTH_TOKEN=$(cat "$TOKEN_FILE")
    if ! check_token_validity "$AUTH_TOKEN"; then
        echo "Le token n'est plus valide. Obtention d'un nouveau token..."
        get_new_token
        AUTH_TOKEN=$(cat "$TOKEN_FILE")
    fi
else
    get_new_token
    AUTH_TOKEN=$(cat "$TOKEN_FILE")
fi


# Vérifie si le fichier JSON existe et a été modifié il y a plus de $MAX_FILE_AGE jours
if [ ! -f "$JSON_FILE" ] || [ $(find "$JSON_FILE" -mtime +$MAX_FILE_AGE 2>/dev/null) ]; then
    echo "Le fichier JSON n'existe pas ou n'a pas été modifié depuis plus de $MAX_FILE_AGE jours. Récupération des nouvelles données..."
	get_jsonfile
# else
    # echo "Le fichier JSON a été modifié il y a moins de $MAX_FILE_AGE jours."
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
		# Récupération des informations pour le dispositif
		curl_output=$(curl -s -X GET -H "Authorization: Bearer $AUTH_TOKEN" http://$HOME_BRIDGE_IP/api/accessories/$UNIQUE_ID)
		# Affichage des informations en JSON
		echo "$curl_output" | jq '.'
		;;
		
	"id")
		[ -z "$2" ] && get_help
		AID="$2"
		RESULT=$(jq -r ".[] | select(.aid == $AID) | {uniqueId: .uniqueId, serviceName: .serviceName, aid: .aid}" "$JSON_FILE")
		if [ ! -z "$RESULT" ]; then
			serviceName=$(echo "$RESULT" | jq -r '.serviceName')
													   
			aid=$(echo "$RESULT" | jq -r '.aid')
			uniqueId=$(echo "$RESULT" | jq -r '.uniqueId')
			echo "serviceName: $serviceName"
			echo "aid: $aid"
			echo "uniqueId: $uniqueId"
		else
			echo "Aucune information trouvée pour l'AID $2."
		fi
		;;
		
	"get_value") #Pour avoir la valeur à partire du non de la description 
		[ -z "$2" ] || [ -z "$3" ] && get_help
		AID="$2"
		CHARACTERISTIC_TYPE="$3"
		get_uniqueid
		# Récupération des informations pour le dispositif
		curl_output=$(curl -s -X GET -H "Authorization: Bearer $AUTH_TOKEN" http://$HOME_BRIDGE_IP/api/accessories/$UNIQUE_ID)
		# Obtention de la valeur pour le type de caractéristique spécifié
		VALUE=$(echo "$curl_output" | jq -r --arg type "$CHARACTERISTIC_TYPE" '.serviceCharacteristics[] | select(.description == $type) | .value')
		# Affichage de la valeur
		echo "$VALUE"
		;;
	
	"info")
        [ -z "$2" ] && get_help
        AID="$2"
        get_uniqueid
        # Récupération des informations pour le dispositif
        curl_output=$(curl -s -X GET -H "Authorization: Bearer $AUTH_TOKEN" http://$HOME_BRIDGE_IP/api/accessories/$UNIQUE_ID)
		service_name=$(echo "$curl_output" | jq -r '.serviceName')
		# Affichage des informations pour le dispositif
		echo "Informations pour le dispositif $service_name [AID $AID] :"
		echo "$curl_output" | jq --tab '.values | to_entries[] | "\(.key): \(.value)"'
		;;
	
     "get")
        [ -z "$2" ] || [ -z "$3" ] && get_help
        AID="$2"
        CHARACTERISTIC_TYPE="$3"
        get_uniqueid
        # Récupération des informations pour le dispositif
        curl_output=$(curl -s -X GET -H "Authorization: Bearer $AUTH_TOKEN" http://$HOME_BRIDGE_IP/api/accessories/$UNIQUE_ID)
        # Obtention de la valeur pour le type de caractéristique spécifié
        VALUE=$(echo "$curl_output" | jq -r --arg type "$CHARACTERISTIC_TYPE" '.values[$type]')
        # Affichage de la valeur
		if [ "$VALUE" != "null" ]; then
			echo "$VALUE"
		else
			# Récupération de la structure JSON des valeurs
			values_structure=$(echo "$curl_output" | jq -r '.values')
			# Extraction des clés (noms des caractéristiques) de la structure JSON
			valid_characteristic=$(echo "$values_structure" | jq -r 'keys_unsorted[]')
			echo "Erreur : Invalid characteristic Type. Valid types are:"
			echo "$valid_characteristic"
		 
		fi
        ;;
			
	"put" | "set" )
		[ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] && get_help
		AID="$2"
		CHARACTERISTIC_TYPE="$3"
		NEW_VALUE="$4"
		get_uniqueid
        # Récupération des informations pour le dispositif
        curl_output=$(curl -s -X GET -H "Authorization: Bearer $AUTH_TOKEN" http://$HOME_BRIDGE_IP/api/accessories/$UNIQUE_ID)
        
        # Vérification de la possibilité d'écrire (canWrite) pour la caractéristique spécifique
        # CAN_WRITE=$(echo "$curl_output" | jq -r --arg type "$CHARACTERISTIC_TYPE" '.serviceCharacteristics[] | select(.type == $type) | .canWrite')
		# if [ -z "$CAN_WRITE" ]; 			then echo "La caractéristique $CHARACTERISTIC_TYPE n'existe pas." && exit 1
		# elif [ "$CAN_WRITE" != "true" ]; 	then echo "La caractéristique $CHARACTERISTIC_TYPE ne peut pas être modifiée." && exit 1
		# fi

        response=$(curl -s -X PUT -H "Content-Type: application/json" -H "Authorization: Bearer $AUTH_TOKEN" -d "{\"characteristicType\": \"$CHARACTERISTIC_TYPE\", \"value\": \"$NEW_VALUE\"}" http://$HOME_BRIDGE_IP/api/accessories/$UNIQUE_ID)
		# Vérification de la présence du champ "error" dans la réponse
		if ! echo "$response" | grep '.error' >/dev/null; then
			echo "Modification réussie: $CHARACTERISTIC_TYPE à la valeur $NEW_VALUE"
		else
			error_message=$(echo "$response" | jq -r '.message')
			echo "$error_message"
		fi
		;;
	*)
        get_help
        ;;
esac
