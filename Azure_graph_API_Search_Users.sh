#!/bin/bash

#Dependencies
#sudo apt-get install jq
#pip install xlsx2csv csv2xlsx

# File paths
EMAIL_XLFILE="emails.xlsx"
EMAIL_FILE="emails.csv"
OUTPUT_FILE="updated_emails.csv"
AUTH_TOKEN="your_authorization_token_here"

#Convert the Excel file to CSV
xlsx2csv emails.xlsx emails.csv

# Create output file and write header
echo "Email,Department" > "$OUTPUT_FILE"

# Read each email from the CSV file (skipping the header)
tail -n +2 "$EMAIL_FILE" | while IFS=, read -r EMAIL
do
  # Perform the curl command for each email
  RESPONSE=$(curl -s -X POST https://graph.microsoft.com/beta/\$batch \
    -H "Accept: application/json" \
    -H "Accept-Language: en-US" \
    -H "Authorization: Bearer $AUTH_TOKEN" \
    -H "Cache-Control: no-cache" \
    -H "Client-Request-Id: 27468fe1-3716-4703-a117-34760c94be38" \
    -H "Content-Type: application/json" \
    -H "Origin: https://sandbox-1.reactblade-portal-azure.net" \
    -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36" \
    -H "Sec-Fetch-Dest: empty" \
    -H "Sec-Fetch-Mode: cors" \
    -H "Sec-Fetch-Site: cross-site" \
    -H "Request-Id: 27468fe1-3716-4703-a117-34760c94be38" \
    -d "{
          \"requests\": [
            {
              \"id\": \"1\",
              \"method\": \"GET\",
              \"url\": \"/users?\$select=userPrincipalName,department&\$search=\\\"mail:$EMAIL\\\"&\$top=20&\$count=true\",
              \"headers\": {
                \"ConsistencyLevel\": \"eventual\"
              }
            }
          ]
        }")

  # Extract the department from the response
  DEPARTMENT=$(echo "$RESPONSE" | jq -r '.responses[0].body.value[0].department // "Not Found"')

  # Write the email and department to the output file
  echo "$EMAIL,$DEPARTMENT" >> "$OUTPUT_FILE"
done

# Convert the updated CSV back to Excel
csv2xlsx "$OUTPUT_FILE" emails_updated.xlsx
