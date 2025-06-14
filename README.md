# RS School DevOps Course - Task 1: AWS Account Configuration & Terraform

This project is an implementation of Task 1 for the RS School DevOps course. The goal is to set up an AWS account, deploy basic infrastructure using Terraform, and automate this process using GitHub Actions.

## Infrastructure Overview

The infrastructure managed by Terraform in this task includes:

*   **S3 Bucket for Terraform Backend:** To securely store the Terraform state file (`terraform.tfstate`).
*   **S3 Bucket for Application Data:** An example bucket for application data.
*   **IAM Role for GitHub Actions (`GithubActionsRole`):** Enables GitHub Actions to securely authenticate with AWS using OIDC (OpenID Connect) and manage resources.

## Prerequisites

Before working with this project, ensure you have:

1.  **Installed Software:**
    *   AWS CLI (version 2 or later)
    *   Terraform (version 1.6.0 or later)
2.  **Configured AWS Account:**
    *   An IAM user (not root) created with the following AWS-managed policies attached:
        *   `AmazonEC2FullAccess`
        *   `AmazonRoute53FullAccess`
        *   `AmazonS3FullAccess`
        *   `IAMFullAccess`
        *   `AmazonVPCFullAccess`
        *   `AmazonSQSFullAccess`
        *   `AmazonEventBridgeFullAccess`
    *   MFA (Multi-Factor Authentication) configured for both the root user and the newly created IAM user.
    *   Access keys (Access Key ID and Secret Access Key) generated for the newly created IAM user.
    *   AWS CLI configured locally to use this user's credentials.
3.  **GitHub Repository:**
    *   A GitHub repository created (e.g., `rs-devops-course-tasks` or `rsschool-devops-course-tasks`).

## Infrastructure Details

### Terraform Backend

The Terraform state is stored in a dedicated S3 bucket. The backend configuration is located in the `backend.tf` file.

### S3 Buckets

*   **Terraform State Bucket:** Name defined in `backend.tf` and the `s3_backend_bucket_name` variable.
*   **Application Data Bucket:** Name defined in the `application_data_s3_bucket_name` variable.

### IAM Role for GitHub Actions (`GithubActionsRole`)

This role is crucial for secure integration between GitHub Actions and AWS.

*   **Purpose:** Allows GitHub Actions to assume this role via OIDC federation, eliminating the need to store long-lived AWS credentials as GitHub secrets.
*   **Trust Policy:**
    *   Trusts the GitHub OIDC provider (`token.actions.githubusercontent.com`).
    *   Includes conditions to restrict who can assume the role:
        *   **`sub` (Subject):** Specifies allowed repositories, branches (`main`, `task-1`), and events (`pull_request`).
        *   **`aud` (Audience):** Requires the token to be intended for `sts.amazonaws.com`.
*   **Attached Permissions:** As per task requirements, the role has the following AWS-managed policies attached (note: in a production environment, the principle of least privilege is recommended):
    *   `AmazonEC2FullAccess`
    *   `AmazonRoute53FullAccess`
    *   `AmazonS3FullAccess`
    *   `IAMFullAccess`
    *   `AmazonVPCFullAccess`
    *   `AmazonSQSFullAccess`
    *   `AmazonEventBridgeFullAccess`

## Configuration

### Terraform Variables (`variables.tf`)

Key variables that might need adjustment:

*   `aws_region`: The AWS region (default: `eu-west-1`).
*   `s3_backend_bucket_name`: A globally unique S3 bucket name for the Terraform state. **Must match the configuration in `backend.tf`**.
*   `application_data_s3_bucket_name`: A globally unique S3 bucket name for application data.
*   `github_actions_role_name`: The name of the IAM role for GitHub Actions (default: `GithubActionsRole`).
*   `github_org_or_user`: Your GitHub username or organization name (e.g., `AlanKowalzky`).
*   `github_repo_name`: Your GitHub repository name (e.g., `rs-devops-course-tasks`).

### GitHub Secrets

The following secret needs to be configured in your GitHub repository's Actions settings:

*   `AWS_ACCOUNT_ID`: Your AWS Account ID. This is used in the workflow to construct the IAM role ARN.

## Usage

### GitHub Actions Workflow (`.github/workflows/terraform.yml`)

The workflow is automatically triggered by the following events:

*   **Push** to the `main` and `task-1` branches.
*   **Pull Request** targeting the `main` branch.

The workflow consists of the following jobs:

1.  **`terraform-check`**:
    *   Checks the formatting of the Terraform code (`terraform fmt -check -recursive`). If the formatting is incorrect, the job will fail.
2.  **`terraform-plan`**:
    *   Authenticates to AWS using OIDC and the `GithubActionsRole`.
    *   Initializes Terraform (`terraform init`).
    *   Generates an execution plan (`terraform plan`) and saves it as an artifact.
    *   Includes steps to debug the OIDC token to verify its contents.
3.  **`terraform-apply`**:
    *   Runs **only** on push to the `main` branch.
    *   Downloads the plan artifact from the `terraform-plan` job.
    *   Authenticates to AWS using OIDC.
    *   Applies the Terraform plan (`terraform apply`), deploying changes to the AWS infrastructure.

### Local Terraform Usage (Optional)

You can also manage the infrastructure locally:

1.  **Initialize:**
    ```bash
    terraform init
    ```
2.  **Plan:**
    ```bash
    terraform plan
    ```
3.  **Apply:**
    ```bash
    terraform apply
    ```

Ensure your local AWS CLI is configured with appropriate permissions.

## Security Considerations

*   **MFA:** Always use MFA for all IAM users, including the root user.
*   **Principle of Least Privilege:** While this task requires the use of broad `*FullAccess` policies for the `GithubActionsRole`, in production environments, always apply the principle of least privilege by creating custom IAM policies with only the necessary actions.
*   **OIDC Conditions:** The IAM role's trust policy uses `sub` and `aud` conditions to restrict which GitHub Actions workflows can assume the role, enhancing security.
*   **Secrets:** Avoid storing long-lived credentials. OIDC federation is the preferred approach.



---
*Documentation prepared as part of Task 1 for the RS School DevOps Course.*