data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "github_actions_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      # TYMCZASOWO: Uproszczony warunek do testów
      values   = ["repo:${var.github_org_or_user}/${var.github_repo_name}:*"]
    }

    # Opcjonalnie, można dodać warunek na audience, jeśli jest to wymagane przez politykę bezpieczeństwa
    # condition {
    #   test     = "StringEquals"
    #   variable = "token.actions.githubusercontent.com:aud"
    #   values   = ["sts.amazonaws.com"] # Domyślna audience dla AWS
    # }
  }
}

resource "aws_iam_role" "github_actions_role" {
  name               = var.github_actions_role_name
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role_policy.json

  tags = {
    Name        = "GitHubActionsRole"
    Description = "IAM role for GitHub Actions to deploy infrastructure via Terraform"
  }
}

# Dołączanie polityk zarządzanych przez AWS przy użyciu dedykowanego zasobu
# UWAGA: Nadawanie pełnego dostępu (IAMFullAccess) jest ryzykowne dla automatyzacji.
# Rozważ zawężenie uprawnień do absolutnie niezbędnych.

resource "aws_iam_role_policy_attachment" "github_actions_ec2_full" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

resource "aws_iam_role_policy_attachment" "github_actions_route53_full" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRoute53FullAccess"
}

resource "aws_iam_role_policy_attachment" "github_actions_s3_full" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "github_actions_iam_full" { # Bądź ostrożny z tą polityką!
  role       = aws_iam_role.github_actions_role.name
  policy_arn = "arn:aws:iam::aws:policy/IAMFullAccess"
}

resource "aws_iam_role_policy_attachment" "github_actions_vpc_full" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonVPCFullAccess"
}

resource "aws_iam_role_policy_attachment" "github_actions_sqs_full" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSQSFullAccess"
}

resource "aws_iam_role_policy_attachment" "github_actions_eventbridge_full" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEventBridgeFullAccess"
}