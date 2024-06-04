#!/bin/bash

# Set the authorization token
AUTH_TOKEN="YOUR_ACCESS_TOKEN"

# Fetch user data and save it to response.json
curl -X POST https://graph.microsoft.com/beta/$batch \
  -H "Accept: application/json" \
  -H "Accept-Language: en-US" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Cache-Control: no-cache" \
  -H "Client-Request-Id: ---Replace---" \
  -H "Content-Type: application/json" \
  -H "Origin: https://sandbox-1.reactblade-portal-azure.net" \
  -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36" \
  -H "Sec-Fetch-Dest: empty" \
  -H "Sec-Fetch-Mode: cors" \
  -H "Sec-Fetch-Site: cross-site" \
  -H "Request-Id: ---Replace---" \
  -d '{
        "requests": [
          {
            "id": "1",
            "method": "GET",
            "url": "/users?$select=userPrincipalName,department&$top=20",
            "headers": {
              "ConsistencyLevel": "eventual"
            }
          }
        ]
      }' > response.json

# Check if the response.json file was created
if [[ ! -f "response.json" ]]; then
  echo "Failed to fetch data."
  exit 1
fi

# Use Python to parse the response and create the Excel file
python3 - <<EOF
import json
import pandas as pd

# Load JSON response from file
with open('response.json', 'r') as f:
    data = json.load(f)

# Extract user details
users = data['responses'][0]['body']['value']
emails_and_departments = [(user['userPrincipalName'], user.get('department', 'N/A')) for user in users]

# Create a DataFrame
df = pd.DataFrame(emails_and_departments, columns=['Email', 'Department'])

# Save DataFrame to Excel
df.to_excel('emails_and_departments.xlsx', index=False)
EOF

# Check if the Excel file was created
if [[ -f "emails_and_departments.xlsx" ]]; then
  echo "Excel file 'emails_and_departments.xlsx' created successfully."
else
  echo "Failed to create the Excel file."
fi
