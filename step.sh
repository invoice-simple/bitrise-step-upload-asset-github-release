#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

# Validate all required inputs
validate_inputs() {
    log_info "Validating inputs..."
    
    if [[ -z "${deploy_path:-}" ]]; then
        log_error "deploy_path is required but not set"
        exit 1
    fi
    
    if [[ -z "${github_repo:-}" ]]; then
        log_error "github_repo is required but not set"
        exit 1
    fi
    
    if [[ -z "${github_token:-}" ]]; then
        log_error "github_token is required but not set"
        exit 1
    fi
    
    if [[ -z "${tag_id:-}" ]]; then
        log_error "tag_id is required but not set"
        exit 1
    fi
    
    # Validate deploy_path exists and has content
    if [[ ! -e "${deploy_path}" ]]; then
        log_error "deploy_path '${deploy_path}' does not exist"
        exit 1
    fi
    
    # Check if deploy_path has files
    if [[ -d "${deploy_path}" ]]; then
        if [[ -z "$(find "${deploy_path}" -type f -print -quit)" ]]; then
            log_error "deploy_path '${deploy_path}' is a directory but contains no files"
            exit 1
        fi
    elif [[ ! -f "${deploy_path}" ]]; then
        log_error "deploy_path '${deploy_path}' is not a file or directory"
        exit 1
    fi
    
    # Validate github_repo format (owner/repo)
    if [[ ! "${github_repo}" =~ ^[^/]+/[^/]+$ ]]; then
        log_error "github_repo must be in format 'owner/repo', got: '${github_repo}'"
        exit 1
    fi
    
    log_success "All inputs validated successfully"
}

# Check if jq is available
check_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        log_error "jq is required but not installed. Please install jq to use this script."
        log_error "On macOS: brew install jq"
        log_error "On Ubuntu/Debian: apt-get install jq"
        log_error "On CentOS/RHEL: yum install jq"
        exit 1
    fi
    log_success "jq is installed"
}

# Fetch GitHub release ID by tag name
fetch_release_id() {
    local repo="$1"
    local tag="$2"
    local token="$3"
    
    log_info "Fetching release ID for tag '${tag}' from repo '${repo}'..." >&2
    
    local api_url="https://api.github.com/repos/${repo}/releases/tags/${tag}"
    local temp_file temp_headers
    temp_file=$(mktemp)
    temp_headers=$(mktemp)

    log_info "Temp file: ${temp_file}" >&2
    
    # Make API request and capture headers
    curl -s \
        -H "Authorization: Bearer ${token}" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -D "${temp_headers}" \
        -o "${temp_file}" \
        "${api_url}"
    
    local curl_exit_code=$?
    local http_code
    http_code=$(head -n1 "${temp_headers}" | cut -d' ' -f2)
    
    # Clean up temp files
    rm -f "${temp_headers}"
    
    # Check curl command success first
    if [[ ${curl_exit_code} -ne 0 ]]; then
        log_error "curl command failed with exit code: ${curl_exit_code}"
        rm -f "${temp_file}"
        exit 1
    fi
    
    if [[ "${http_code}" != "200" ]]; then
        log_error "Failed to fetch release. HTTP status: ${http_code}"
        
        # Try to parse error message from JSON response
        local error_message
        error_message=$(jq -r '.message // "Unknown error"' "${temp_file}" 2>/dev/null || echo "Unknown error")
        log_error "GitHub API Error: ${error_message}"
        
        if [[ "${http_code}" == "404" ]]; then
            log_error "Release with tag '${tag}' not found in repository '${repo}'"
        elif [[ "${http_code}" == "401" ]]; then
            log_error "Authentication failed. Please check your GitHub token"
        fi
        
        rm -f "${temp_file}"
        exit 1
    fi
    
    # Extract release ID from JSON response using jq
    local release_id
    release_id=$(jq -r '.id' "${temp_file}" 2>/dev/null)
    
    rm -f "${temp_file}"
    
    if [[ -z "${release_id}" || "${release_id}" == "null" ]]; then
        log_error "Could not extract release ID from response"
        exit 1
    fi
    
    echo "${release_id}"
}

# Upload a single file to GitHub release
# Upload a single file to GitHub release
# Upload a single file to GitHub release
upload_file() {
    local file_path="$1"
    local repo="$2"
    local release_id="$3"
    local token="$4"
    
    local filename
    filename=$(basename "${file_path}")
    
    log_info "Uploading file: ${filename}"
    
    # Validate inputs
    if [[ -z "${repo}" ]]; then
        log_error "Repository parameter is empty"
        return 1
    fi
    
    if [[ -z "${release_id}" ]]; then
        log_error "Release ID parameter is empty"
        return 1
    fi
    
    # URL encode the filename to handle special characters
    local encoded_filename
    encoded_filename=$(printf '%s' "${filename}" | sed 's/ /%20/g' | sed 's/#/%23/g' | sed 's/&/%26/g' | sed 's/?/%3F/g' | sed 's/+/%2B/g')
    
    local upload_url="https://uploads.github.com/repos/${repo}/releases/${release_id}/assets?name=${encoded_filename}"
    
    log_info "Upload URL: ${upload_url}"
    log_info "Original filename: '${filename}'"
    log_info "Encoded filename: '${encoded_filename}'"
    
    local temp_file temp_headers
    temp_file=$(mktemp)
    temp_headers=$(mktemp)
    
    # Upload file and capture headers
    curl -s \
        -X POST \
        -H "Authorization: Bearer ${token}" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -H "Content-Type: application/octet-stream" \
        --data-binary "@${file_path}" \
        -D "${temp_headers}" \
        -o "${temp_file}" \
        "${upload_url}"
    
    local curl_exit_code=$?
    
    # Debug: show what curl actually tried to do
    if [[ ${curl_exit_code} -ne 0 ]]; then
        log_error "curl command failed with exit code: ${curl_exit_code}"
        log_error "URL attempted: ${upload_url}"
        log_error "Repository: '${repo}'"
        log_error "Release ID: '${release_id}'"
        log_error "File path: '${file_path}'"
        log_error "Original filename: '${filename}'"
        log_error "Encoded filename: '${encoded_filename}'"
        
        case ${curl_exit_code} in
            3) log_error "URL malformation error - check repository format, release ID, and filename" ;;
            6) log_error "Couldn't resolve host - check internet connection" ;;
            7) log_error "Failed to connect to host" ;;
            22) log_error "HTTP error occurred" ;;
            26) log_error "Read error - could not read file" ;;
            *) log_error "Unknown curl error" ;;
        esac
        
        rm -f "${temp_file}" "${temp_headers}"
        return 1
    fi
    
    local http_code
    http_code=$(head -n1 "${temp_headers}" | cut -d' ' -f2 2>/dev/null || echo "000")
    
    # Clean up temp files
    rm -f "${temp_headers}"
    
    if [[ "${http_code}" != "201" ]]; then
        log_error "Failed to upload file '${filename}'. HTTP status: ${http_code}"
        
        # Try to parse error message from JSON response using jq
        local error_message
        error_message=$(jq -r '.message // "Unknown error"' "${temp_file}" 2>/dev/null || echo "Unknown error")
        log_error "GitHub API Error: ${error_message}"
        
        # Check for specific error details in the response
        local errors
        errors=$(jq -r '.errors[]?.message // empty' "${temp_file}" 2>/dev/null)
        if [[ -n "${errors}" ]]; then
            log_error "Additional errors: ${errors}"
        fi
        
        if [[ "${http_code}" == "422" ]]; then
            log_error "File '${filename}' may already exist in the release or validation failed"
        elif [[ "${http_code}" == "401" ]]; then
            log_error "Authentication failed. Please check your GitHub token permissions"
        elif [[ "${http_code}" == "404" ]]; then
            log_error "Release not found. Please verify the release ID and repository"
        fi
        
        rm -f "${temp_file}"
        return 1
    fi
    
    # Parse successful response to get asset information
    local asset_name asset_size
    asset_name=$(jq -r '.name // "unknown"' "${temp_file}" 2>/dev/null)
    asset_size=$(jq -r '.size // 0' "${temp_file}" 2>/dev/null)

    rm -f "${temp_file}"
    
    log_success "Successfully uploaded: ${asset_name} (${asset_size} bytes)"
    return 0
}

# Upload all files from deploy_path to GitHub release
upload_files() {
    local deploy_path="$1"
    local repo="$2"
    local release_id="$3"
    local token="$4"
    
    log_info "Starting file upload process..."
    
    local files_to_upload=()
    local failed_uploads=()
    
    # Collect files to upload
    if [[ -f "${deploy_path}" ]]; then
        files_to_upload=("${deploy_path}")
    elif [[ -d "${deploy_path}" ]]; then
        # Find all files in directory (not recursive)
        while IFS= read -r -d '' file; do
            files_to_upload+=("$file")
        done < <(find "${deploy_path}" -maxdepth 1 -type f -print0)
    fi
    
    if [[ ${#files_to_upload[@]} -eq 0 ]]; then
        log_error "No files found to upload"
        exit 1
    fi
    
    log_info "Found ${#files_to_upload[@]} file(s) to upload"
    
    # Upload each file
    for file in "${files_to_upload[@]}"; do
        if ! upload_file "${file}" "${repo}" "${release_id}" "${token}"; then
            failed_uploads+=("$(basename "${file}")")
        fi
    done
    
    # Report results
    local successful_uploads=$((${#files_to_upload[@]} - ${#failed_uploads[@]}))
    
    if [[ ${#failed_uploads[@]} -eq 0 ]]; then
        log_success "All ${#files_to_upload[@]} file(s) uploaded successfully"
    else
        log_error "${#failed_uploads[@]} file(s) failed to upload: ${failed_uploads[*]}"
        log_info "${successful_uploads} file(s) uploaded successfully"
        exit 1
    fi
}

# Main function
main() {
    log_info "Starting GitHub Release Asset Uploader"
    
    # Check if jq is available
    check_jq
    
    # Validate inputs
    validate_inputs
    
    # Fetch release ID
    local release_id
    release_id=$(fetch_release_id "${github_repo}" "${tag_id}" "${github_token}")

    # Upload files
    upload_files "${deploy_path}" "${github_repo}" "${release_id}" "${github_token}"
    
    log_success "GitHub release asset upload completed successfully"
}

# Run main function
main "$@"