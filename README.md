# Bitrise Action - GitHub Release Asset Upload

[![Step changelog](https://shields.io/github/v/release/invoice-simple/bitrise-step-upload-asset-github-release?include_prereleases&label=changelog&color=blueviolet)](https://github.com/invoice-simple/bitrise-step-upload-asset-github-release/releases)

Upload your mobile app assets (.apk and .ipa files) to an existing GitHub Release.
Useful when you're triggering GitHub Releases outside of Bitrise (via a tool such as [semantic-release](https://github.com/semantic-release/semantic-release)) but still wants your assets to be available on the release tab.

<details>
<summary>Description</summary>

The Step uploads your mobile app binaries and other assets to an existing GitHub Release. By default, it automatically filters for APK (Android) and IPA (iOS) files, but you can specify custom file patterns to upload any files you need.

Please note that this Step requires an **existing GitHub Release** to be created beforehand. The Step will upload assets to the release identified by the provided tag name. If you need to create a new release with the assets, use the [GitHub Release](https://www.bitrise.io/integrations/steps/github-release) step instead of this.

### Key Features

- **Smart File Filtering**: Automatically uploads .apk and .ipa files by default
- **Custom File Selection**: Support for file patterns and exact paths
- **Dry Run Mode**: Preview files before uploading
- **Cross-Platform**: Works on macOS, Linux, and CI/CD environments
- **Pattern Matching**: Supports wildcards and subdirectory patterns
- **Comprehensive Logging**: Detailed progress and error reporting

### Configuring the Step

The Step uses GitHub's API, so you need to set up proper authentication and permissions:

#### Setting up GitHub API Access

1. **Create a Personal Access Token**:

   - Go to [GitHub Settings > Developer settings > Personal access tokens](https://github.com/settings/tokens)
   - Generate a new token with `repo` scope (for private repositories) or `public_repo` scope (for public repositories)
   - Store the token securely as a [Secret Environment Variable](https://devcenter.bitrise.io/builds/env-vars-secret-env-vars/) in Bitrise

2. **Ensure Release Exists**:
   - The GitHub Release must already exist with the specified tag
   - You can create releases manually via GitHub's web interface or use GitHub's API/CLI tools
   - The Step will fail if the specified tag/release doesn't exist

#### Required Permissions

Your GitHub token must have the following permissions:

- **Contents**: Write (to upload release assets)
- **Metadata**: Read (to access repository information)

For private repositories, ensure the token has full `repo` access.

### Step Configuration

To deploy your app assets with the Step:

1. **GitHub Repository Path**: Set this to your repository in `owner/repo` format (e.g., `mycompany/myapp`)
2. **GitHub Personal Access Token**: Add the Secret Environment Variable containing your GitHub token
3. **Deploy directory or file path**: Specify the path to your built assets (defaults to `$BITRISE_DEPLOY_DIR`)
4. **Release Tag**: Provide the tag name of the existing GitHub Release where assets should be uploaded (defaults to `$BITRISE_GIT_TAG`)
5. **Files to upload** (Optional): Customize which files to upload using patterns or exact paths
6. **Dry Run** (Optional): Preview files that would be uploaded without actually uploading

### File Selection Options

#### Default Behavior

When no custom files are specified, the Step automatically uploads only **Android** (`.apk`) and **iOS** (`.ipa`) files. Other files in the deploy directory are automatically skipped.

#### Custom File Selection

Use the `files_to_upload` parameter to specify exactly which files to upload:

**File Patterns:**

- `*.apk` - All APK files
- `*.ipa` - All IPA files
- `app-*.apk` - APK files starting with "app-"
- `outputs/*.aab` - All AAB files in outputs directory

**Exact Paths:**

- `app-release.apk` - Specific file
- `MyApp.ipa` - Specific IPA file

**Mixed Examples:**

```
*.apk
MyApp.ipa
mapping.txt
outputs/*.aab
debug/symbols.zip
```

### Dry Run Mode

Use dry run mode to preview which files would be uploaded:

- Set `dry_run: "true"` in your workflow
- No actual uploads are performed
- No GitHub API calls are made
- Files are validated and listed with sizes
- Perfect for testing file patterns

### Troubleshooting

If the Step fails, check the following:

- **Authentication**: Verify your GitHub token is valid and has the correct permissions
- **Release Existence**: Ensure a release with the specified tag already exists in the repository
- **Repository Path**: Check the repository path format is correct (`owner/repo`)
- **File Permissions**: Verify the deploy path contains readable files
- **File Patterns**: Use dry run mode to test your file patterns
- **Network**: Ensure the build environment has internet access to reach GitHub's API

Common error scenarios:

- **404 Not Found**: Release with the specified tag doesn't exist
- **401 Unauthorized**: Invalid or expired GitHub token
- **422 Unprocessable Entity**: Asset may already exist with the same name
- **Pattern No Match**: File patterns don't match any files (use dry run to debug)

### Useful links

- [GitHub REST API - Release Assets](https://docs.github.com/en/rest/releases/assets)
- [Creating GitHub Personal Access Tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token)
- [Bitrise Secret Environment Variables](https://devcenter.bitrise.io/builds/env-vars-secret-env-vars/)

### Related Steps

- [Deploy to Bitrise.io](https://www.bitrise.io/integrations/steps/deploy-to-bitrise-io)
- [Google Play Deploy](https://www.bitrise.io/integrations/steps/google-play-deploy)
- [App Store Connect Deploy](https://www.bitrise.io/integrations/steps/deploy-to-itunesconnect-application-loader)
</details>

## 🧩 Get started

Add this step directly to your workflow in the [Bitrise Workflow Editor](https://devcenter.bitrise.io/steps-and-workflows/steps-and-workflows-index/).

You can also run this step directly with [Bitrise CLI](https://github.com/bitrise-io/bitrise).

### Basic Example

Build your mobile apps and upload them to an existing GitHub Release:

```yaml
steps:
  # Build Android APK
  - android-build:
      inputs:
        - variant: release
        - build_type: apk
  - sign-apk:
      inputs:
        - android_app: $BITRISE_APK_PATH

  # Build iOS IPA
  - xcode-archive:
      inputs:
        - scheme: MyApp
  - export-xcarchive:
      inputs:
        - export_method: app-store

  # Upload assets to GitHub Release (default: .apk and .ipa files only)
  - git::https://github.com/invoice-simple/bitrise-step-upload-asset-github-release.git@latest:
      inputs:
        - github_repo: mycompany/myapp
        - github_token: $GITHUB_ACCESS_TOKEN # Set this as a Secret Environment Variable
        - tag_id: v1.0.0 # Must be an existing release tag
        - deploy_path: $BITRISE_DEPLOY_DIR
```

### Custom File Selection

Upload specific files using patterns:

```yaml
- git::https://github.com/invoice-simple/bitrise-step-upload-asset-github-release.git@latest:
    inputs:
      - files_to_upload: |
          *.apk
          *.ipa
          mapping.txt
          outputs/*.aab
          symbols/*.zip
```

### Dry Run Testing

Test your file patterns before actual upload:

```yaml
- git::https://github.com/invoice-simple/bitrise-step-upload-asset-github-release.git@latest:
    inputs:
      - deploy_path: ./build
      - files_to_upload: |
          app-release-*.apk
          MyApp.ipa
          debug/*.txt
      - dry_run: "true" # Preview files without uploading
```

### Advanced Example

Complete workflow with custom paths and validation:

```yaml
steps:
  - upload-asset-github-release:
      inputs:
        - github_repo: mycompany/myapprepo
        - github_token: $GITHUB_ACCESS_TOKEN
        - tag_id: v1.0.0
        - deploy_path: $BITRISE_DEPLOY_DIR
        - files_to_upload: |
            mobile/*.apk
            mobile/*.ipa
            /absolute/path/changelog.md
            docs/*.pdf
```

## ⚙️ Configuration

<details>
<summary>Inputs</summary>

| Key               | Description                                                                                                                                                                                                                                                 | Flags               | Default                   |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------- | ------------------------- |
| `deploy_path`     | Path to the directory or file containing assets to deploy. If a directory is specified, files will be selected based on the `files_to_upload` parameter or default .apk/.ipa filtering.                                                                     | required            | `$BITRISE_DEPLOY_DIR`     |
| `github_repo`     | GitHub repository in owner/repo format where the release is located. Example: `mycompany/myproject`                                                                                                                                                         | required            | `$GITHUB_REPOSITORY_PATH` |
| `github_token`    | Personal Access Token for GitHub API authentication. The token must have 'repo' scope to access private repositories and upload release assets. Store this as a Secret Environment Variable.                                                                | required, sensitive | `$GITHUB_ACCESS_TOKEN`    |
| `tag_id`          | The tag name of the existing GitHub release where assets will be uploaded. The release must already exist with this tag. Examples: `v1.0.0`, `release-2023.1`                                                                                               | required            | `$BITRISE_GIT_TAG`        |
| `files_to_upload` | Optional: Specify files to upload using patterns or exact paths, one per line. Supports wildcards (`*.apk`), exact files (`app.apk`), subdirectory patterns (`outputs/*.aab`), and absolute paths. If empty, defaults to uploading all .apk and .ipa files. | optional            | `""`                      |
| `dry_run`         | Preview files that would be uploaded without actually performing the upload. When set to "true", shows file list with sizes but makes no API calls. Useful for testing file patterns.                                                                       | optional            | `"false"`                 |

</details>

<details>
<summary>Outputs</summary>

This step does not generate any output environment variables. Success or failure is indicated by the step's exit code and log messages.

</details>

## 🙋 Contributing

We welcome [pull requests](https://github.com/invoice-simple/bitrise-step-upload-asset-github-release/pulls) and [issues](https://github.com/invoice-simple/bitrise-step-upload-asset-github-release/issues) against this repository.

For pull requests, work on your changes in a forked repository and use the Bitrise CLI to [run step tests locally](https://devcenter.bitrise.io/bitrise-cli/run-your-first-build/).

Learn more about developing steps:

- [Create your own step](https://devcenter.bitrise.io/contributors/create-your-own-step/)
- [Testing your Step](https://devcenter.bitrise.io/contributors/testing-and-versioning-your-steps/)
