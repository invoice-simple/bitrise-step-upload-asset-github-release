#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_dry_run() {
    echo -e "${BLUE}[DRY RUN]${NC} $1"
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
    
    # Only validate GitHub token and tag if not in dry run mode
    if [[ "${dry_run:-false}" != "true" ]]; then
        if [[ -z "${github_token:-}" ]]; then
            log_error "github_token is required but not set"
            exit 1
        fi
        
        if [[ -z "${tag_id:-}" ]]; then
            log_error "tag_id is required but not set"
            exit 1
        fi
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

# Check if jq is available (only required for actual uploads)
check_jq() {
    if [[ "${dry_run:-false}" == "true" ]]; then
        log_dry_run "Skipping jq check in dry run mode"
        return 0
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        log_error "jq is required but not installed. Please install jq to use this script."
        log_error "On macOS: brew install jq"
        log_error "On Ubuntu/Debian: apt-get install jq"
        log_error "On CentOS/RHEL: yum install jq"
        exit 1
    fi
    log_success "jq is installed"
}

# Collect files to upload based on parameters
collect_files_to_upload() {
    local deploy_path="$1"
    local files_to_upload_param="$2"
    local -n files_array_ref="$3"  # Pass array by reference
    
    files_array_ref=()  # Clear the array
    
    if [[ -n "${files_to_upload_param:-}" ]]; then
        # Custom file list/patterns provided - use exactly what user specified
        log_info "Using custom file list from files_to_upload parameter" >&2
        
        # Determine the base directory for pattern resolution
        local base_dir
        if [[ -d "${deploy_path}" ]]; then
            base_dir="${deploy_path}"
        else
            # deploy_path is a file, use its directory
            base_dir="$(dirname "${deploy_path}")"
        fi
        
        while IFS= read -r file_spec; do
            # Skip empty lines
            [[ -z "${file_spec// /}" ]] && continue
            
            local matched_files=()
            
            if [[ "${file_spec}" = /* ]]; then
                # Absolute path - could be a pattern or exact file
                if [[ "${file_spec}" == *"*"* || "${file_spec}" == *"?"* || "${file_spec}" == *"["* ]]; then
                    # It's a pattern with absolute path
                    while IFS= read -r -d '' file; do
                        matched_files+=("$file")
                    done < <(find "$(dirname "${file_spec}")" -maxdepth 1 -name "$(basename "${file_spec}")" -type f -print0 2>/dev/null)
                else
                    # Exact absolute path
                    if [[ -f "${file_spec}" ]]; then
                        matched_files=("${file_spec}")
                    fi
                fi
            else
                # Relative path - resolve from base_dir
                if [[ "${file_spec}" == *"*"* || "${file_spec}" == *"?"* || "${file_spec}" == *"["* ]]; then
                    # It's a pattern
                    local pattern_dir="${base_dir}"
                    local pattern_name="${file_spec}"
                    
                    # Handle patterns with subdirectories (e.g., "outputs/*.apk")
                    if [[ "${file_spec}" == *"/"* ]]; then
                        pattern_dir="${base_dir}/$(dirname "${file_spec}")"
                        pattern_name="$(basename "${file_spec}")"
                    fi
                    
                    if [[ -d "${pattern_dir}" ]]; then
                        while IFS= read -r -d '' file; do
                            matched_files+=("$file")
                        done < <(find "${pattern_dir}" -maxdepth 1 -name "${pattern_name}" -type f -print0 2>/dev/null)
                    fi
                else
                    # Exact relative path
                    local file_path="${base_dir}/${file_spec}"
                    if [[ -f "${file_path}" ]]; then
                        matched_files=("${file_path}")
                    fi
                fi
            fi
            
            # Add matched files to upload list
            if [[ ${#matched_files[@]} -gt 0 ]]; then
                for matched_file in "${matched_files[@]}"; do
                    files_array_ref+=("${matched_file}")
                    log_info "Added file: ${matched_file}" >&2
                done
            else
                log_error "No files found matching pattern/path: ${file_spec}"
                return 1
            fi
            
        done <<< "${files_to_upload_param}"
        
    else
        # Default behavior - filter for .apk and .ipa files only
        log_info "Using default behavior: filtering for .apk and .ipa files" >&2
        
        if [[ -f "${deploy_path}" ]]; then
            # Check if single file has the right extension
            if [[ "${deploy_path}" == *.apk || "${deploy_path}" == *.ipa ]]; then
                files_array_ref=("${deploy_path}")
            else
                log_info "Skipping file '$(basename "${deploy_path}")' - only .apk and .ipa files are supported by default" >&2
            fi
        elif [[ -d "${deploy_path}" ]]; then
            # Find only .apk and .ipa files in directory (not recursive)
            while IFS= read -r -d '' file; do
                files_array_ref+=("$file")
            done < <(find "${deploy_path}" -maxdepth 1 -type f \( -name "*.apk" -o -name "*.ipa" \) -print0)
        fi
    fi
    
    return 0
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
    
    # Build upload URL matching GitHub docs format exactly
    local upload_url="https://uploads.github.com/repos/${repo}/releases/${release_id}/assets?name=${encoded_filename}"
    
    local temp_file temp_headers
    temp_file=$(mktemp)
    temp_headers=$(mktemp)
    
    # Upload file following GitHub docs format exactly
    curl -L \
        -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${token}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -H "Content-Type: application/octet-stream" \
        -D "${temp_headers}" \
        -o "${temp_file}" \
        "${upload_url}" \
        --data-binary "@${file_path}"
    
    local curl_exit_code=$?
    local http_code
    http_code=$(head -n1 "${temp_headers}" | cut -d' ' -f2 2>/dev/null || echo "000")
    
    # Clean up temp files
    rm -f "${temp_headers}"
    
    # Check curl command success first
    if [[ ${curl_exit_code} -ne 0 ]]; then
        log_error "curl command failed with exit code: ${curl_exit_code}"
        log_error "Failed to upload file '${filename}'"
        rm -f "${temp_file}"
        return 1
    fi
    
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
    
    # Collect files to upload using the dedicated function
    if ! collect_files_to_upload "${deploy_path}" "${files_to_upload:-}" files_to_upload; then
        exit 1
    fi
    
    if [[ ${#files_to_upload[@]} -eq 0 ]]; then
        log_error "No files found to upload"
        exit 1
    fi
    
    log_info "Found ${#files_to_upload[@]} file(s) to upload"
    
    # Check if this is a dry run
    if [[ "${dry_run:-false}" == "true" ]]; then
        log_dry_run "Dry run mode enabled - listing files that would be uploaded:"
        echo ""
        for i in "${!files_to_upload[@]}"; do
            local file="${files_to_upload[$i]}"
            local filename=$(basename "${file}")
            local filesize=$(stat -f%z "${file}" 2>/dev/null || stat -c%s "${file}" 2>/dev/null || echo "unknown")
            log_dry_run "$(printf "%2d. %-40s (%s bytes)" $((i+1)) "${filename}" "${filesize}")"
        done
        echo ""
        log_dry_run "Total files: ${#files_to_upload[@]}"
        log_dry_run "No actual upload performed (dry run mode)"
        return 0
    fi
    
    # Actual upload process
    local failed_uploads=()
    
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
    if [[ "${dry_run:-false}" == "true" ]]; then
        log_dry_run "GitHub Release Asset Uploader (DRY RUN MODE)"
    else
        log_info "Starting GitHub Release Asset Uploader"
    fi
    
    # Check if jq is available (skip in dry run)
    check_jq
    
    # Validate inputs
    validate_inputs
    
    # Skip GitHub API calls in dry run mode
    if [[ "${dry_run:-false}" == "true" ]]; then
        log_dry_run "Skipping GitHub API calls in dry run mode"
        upload_files "${deploy_path}" "${github_repo}" "dummy_release_id" "dummy_token"
        log_dry_run "Dry run completed successfully"
    else
        # Fetch release ID
        local release_id
        release_id=$(fetch_release_id "${github_repo}" "${tag_id}" "${github_token}")
        
        # Upload files
        upload_files "${deploy_path}" "${github_repo}" "${release_id}" "${github_token}"
        
        log_success "GitHub release asset upload completed successfully"
    fi
}

# Run main function
main "$@"