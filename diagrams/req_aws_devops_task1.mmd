Task 1: AWS Account Configuration
task_1 schema

Objective
In this task, you will:

Install and configure the required software on your local computer
Set up an AWS account with the necessary permissions and security configurations
Deploy S3 buckets for Terraform states
Create a Github Actions workflow to deploy infrastructure in AWS
Additional tasks:

Create a federation with your AWS account for Github Actions
Create an IAM role for Github Actions
Steps
Install AWS CLI and Terraform

Follow the instructions to install AWS CLI 2.
Follow the instructions to install Terraform 1.6+.
optional Configuring Terraform version manager tfenv
Create IAM User and Configure MFA

In your AWS account, navigate to IAM and create a new user with the following policies attached:
AmazonEC2FullAccess
AmazonRoute53FullAccess
AmazonS3FullAccess
IAMFullAccess
AmazonVPCFullAccess
AmazonSQSFullAccess
AmazonEventBridgeFullAccess
Configure MFA for both the new user and the root user.
Generate a new pair of Access Key ID and Secret Access Key for the user.
Configure AWS CLI

Configure AWS CLI to use the new user's credentials.
Verify the configuration by running the command: aws ec2 describe-instance-types --instance-types t4g.nano.
Create a Github repository for your Terraform code

Using your personal account create a repository rsschool-devops-course-tasks
Create a bucket for Terraform states

Locking terraform state via DynamoDB is not required in this task, but recommended by the best practices. vvvv
Managing Terraform states Best Practices
Terraform backend S3
Create an IAM role for Github Actions(Additional task)💫

Create an IAM role GithubActionsRole with the same permissions as in step 2:
AmazonEC2FullAccess
AmazonRoute53FullAccess
AmazonS3FullAccess
IAMFullAccess
AmazonVPCFullAccess
AmazonSQSFullAccess
AmazonEventBridgeFullAccess
Terraform resource
Configure an Identity Provider and Trust policies for Github Actions(Additional task)💫

Update the GithubActionsRole IAM role with a Trust policy following the next guides
IAM roles terms and concepts
Github tutorial
AWS documentation on OIDC providers
GitHubOrg is a Github username in this case
Create a Github Actions workflow for deployment via Terraform

The workflow should have 3 jobs that run on pull request and push to the default branch:
terraform-check with format checking using terraform fmt
terraform-plan for planning deployments terraform plan
terraform-apply for deploying terraform apply
terraform init
Github actions reference
Setup terraform
Configure AWS Credentials
Submission
Create a branch task_1 from main branch in your repository.
Create a Pull Request (PR) from task_1 branch to main.
Provide the code for Terraform and GitHub Actions in the PR.
Provide screenshots of aws --version and terraform version in the PR description.
Provide a link to the Github Actions workflow run in the PR description.
Provide the Terraform plan output with S3 bucket (and possibly additional resources) creation in the PR description.
Evaluation Criteria (100 points for covering all criteria)
MFA User configured (10 points)

Screenshot of the non-root account secured by MFA (ensure sensitive information is not shared) is presented
Bucket and GithubActionsRole IAM role configured (20 points)

Terraform code is created and includes:
Provider initialization
Creation of S3 Bucket
Github Actions workflow is created (30 points)

Workflow includes all jobs
Code Organization (10 points)

Variables are defined in a separate variables file.
Resources are separated into different files for better organization.
Verification (10 points)

Terraform plan is executed successfully
Additional Tasks (20 points)💫

Documentation (5 points)
Document the infrastructure setup and usage in a README file.
Submission (5 points)
A GitHub Actions (GHA) pipeline is passing
Secure authorization (10 points)
IAM role with correct Identity-based and Trust policies used to connect GitHubActions to AWS.