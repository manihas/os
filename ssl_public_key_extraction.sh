#!/bin/bash

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <privateKeyString>"
  exit 1
fi

privateKeyString="$1"

timestamp=$(date +"%Y-%m-%d-%H%M%S")
certsFolder="certs_$timestamp"
mkdir -p "$certsFolder"

cleanedString=$(echo "$privateKeyString" | tr -d '\r')

sanitizedPrivateKey="$certsFolder/sanitized_private_key.pem"
echo -e "$cleanedString" > "$sanitizedPrivateKey"
echo "Processed private key saved to $sanitizedPrivateKey"

publicKey="$certsFolder/extracted_public_key.pem"
openssl rsa -in "$sanitizedPrivateKey" -pubout -out "$publicKey"
echo "Public key generated and saved to $publicKey"

processedPublicKeyOneLine=$(sed '1d;$d' "$publicKey" | tr '\n' ' ' | sed 's/ *$//')
processedPublicKey="$certsFolder/processed_public_key.pem"
echo -n "$processedPublicKeyOneLine" > "$processedPublicKey"
echo "Public key processed and saved in one line to $processedPublicKey"