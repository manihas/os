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