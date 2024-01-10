# Homebridge Shell API

## Overview

This script provides a convenient way to interact with the Homebridge API using shell commands. It allows you to perform various actions like retrieving accessory information, modifying characteristics, and obtaining JSON details.

## Prerequisites

- **Homebridge**: Make sure you have Homebridge installed and running on your local machine.
- **jq**: The script relies on `jq` for parsing JSON responses. Ensure it is installed on your system.

## Configuration

1. Clone this repository to your local machine:

    ```bash
    git clone https://github.com/your-username/homebridge-shell-api.git
    ```

2. Navigate to the script's directory:

    ```bash
    cd homebridge-shell-api
    ```

3. In the script configure:

    ```bash
    homebridge_username="your_username"
    homebridge_password="your_password"
    ```

## Usage

```bash
./homebridge-shell-api.sh [command] [arguments1] [arguments2] [arguments...]
 ```

## Commands
    json: Retrieve the list of accessories in JSON format.
    jsonid [UNIQUE_ID]: Get JSON details specific to a device using its UNIQUE_ID.
    id [AID]: Get information about a specific accessory using its AID.
    get [UNIQUE_ID] [CHARACTERISTIC_TYPE]: Get the value of a specific characteristic for a device.
    info [UNIQUE_ID]: Get detailed information about a device.
    put [UNIQUE_ID] [CHARACTERISTIC_TYPE] [NEW_VALUE]: Modify a characteristic for a device.
