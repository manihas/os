#!/bin/bash

# Brightcove API credentials
CLIENT_ID="YOUR_CLIENT_ID"
CLIENT_SECRET="YOUR_CLIENT_SECRET"
ACCOUNT_ID="YOUR_ACCOUNT_ID"
VIDEO_TITLE="Your Video Title"
VIDEO_DESCRIPTION="Your Video Description"
VIDEO_FILE_PATH="path/to/your/video.mp4"

# Authenticate and obtain access token
access_token=$(curl -s -X POST \
  -d "grant_type=client_credentials" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" \
  "https://oauth.brightcove.com/v4/access_token" | jq -r '.access_token')

# Upload video
response=$(curl -s -X POST \
  -H "Authorization: Bearer $access_token" \
  -H "Content-Type: application/json" \
  -F "video=@$VIDEO_FILE_PATH" \
  -d '{
        "name": "'"$VIDEO_TITLE"'",
        "description": "'"$VIDEO_DESCRIPTION"'",
        "schedule": {
            "starts_at": "2024-04-05T12:00:00.000Z"
        },
        "state": "INACTIVE"
    }' \
  "https://cms.api.brightcove.com/v1/accounts/$ACCOUNT_ID/videos")

echo "Response: $response"
