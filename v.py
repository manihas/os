import sys

def extract_subdomain(branch_name):
    # Split the branch name by slashes and get the last segment
    segments = branch_name.strip().split('/')
    subdomain = segments[-1]  # Last segment
    return subdomain

if __name__ == "__main__":
    # Get branch name from command line arguments
    if len(sys.argv) != 2:
        print("Usage: python extract_subdomain.py <branch_name>")
        sys.exit(1)
    
    branch_name = sys.argv[1]
    subdomain = extract_subdomain(branch_name)
    print(subdomain)
    
---
extract-subdomain:
  stage: prepare
  script:
    - python extract_subdomain.py $CI_COMMIT_REF_NAME > subdomain.txt
  artifacts:
    paths:
      - subdomain.txt
    
---

deploy-dev:
  stage: deploy
  script:
    - export SUB_DOMAIN=$(cat subdomain.txt)
    - echo "Deploying to: $CI_PROJECT_NAME-$SUB_DOMAIN"
    # Your deployment commands go here
  variables:
    conducktor_app_url: "$CI_PROJECT_NAME-$SUB_DOMAIN"