#!/bin/bash

# Variables (passed as environment variables from the pipeline)
PROGRAMID=$1
CONTENTSETID=$2
ENVIRONMENTID=$3
DESTENVIRONMENTID=$4
INCLUDEACL=$5

# Set Program ID
echo "—Set Program ID—"
aio config set cloudmanager.programid "$PROGRAMID"

# Start Content Copy
echo "- Start Content Copy -"
aio cloudmanager:content-flow:create "$ENVIRONMENTID" "$CONTENTSETID" "$DESTENVIRONMENTID" "$INCLUDEACL" -json > flow_id.json

# Extract Content Flow ID
CONTENTFLOWID=$(jq -r '.contentFlowId' flow_id.json)
if [ -z "$CONTENTFLOWID" ]; then
  echo "Failed to start content flow."
  exit 1
fi

# Function to print status
print_status() {
  local status=$1
  local phase=$2
  local progress=$3
  echo "Status: $status, Phase: $phase, Transfer Progress: $progress%"
}

# Check Content Flow Status Continuously
while true; do
  echo "- Get Content Flow Status -"
  aio cloudmanager:content-flow:get "$CONTENTFLOWID" -json > flow_info.json
  
  STATUS=$(jq -r '.status' flow_info.json)
  PHASE=$(jq -r '.resultDetails.phase' flow_info.json)
  TRANSFER_PROGRESS=$(jq -r '.transferProgress' flow_info.json)

  print_status "$STATUS" "$PHASE" "$TRANSFER_PROGRESS"

  # Check for errors in specific phases
  if [ "$PHASE" == "EXPORTING" ]; then
    export_error=$(jq -r '.resultDetails.exportResult.errorCode' flow_info.json)
    if [ "$export_error" != "null" ]; then
      echo "Export error: $export_error"
      exit 1
    fi
  elif [ "$PHASE" == "IMPORTING" ]; then
    import_error=$(jq -r '.resultDetails.importResult.errorCode' flow_info.json)
    if [ "$import_error" != "null" ]; then
      echo "Import error: $import_error"
      exit 1
    fi
  fi

  if [ "$STATUS" == "FAILED" ]; then
    echo "Content flow failed."
    exit 1
  elif [ "$STATUS" == "COMPLETED" ]; then
    echo "Content flow completed successfully."
    exit 0
  fi

  # Wait for a while before checking again
  sleep 30
done
