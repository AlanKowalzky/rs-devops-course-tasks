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
      values   = ["repo:${var.github_org_or_user}/${var.github_repo_name}:pull_request"] # Dla Pull Requestów
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

  # Dołączanie polityk zarządzanych przez AWS
  # UWAGA: Nadawanie pełnego dostępu (IAMFullAccess) jest ryzykowne dla automatyzacji.
  # Rozważ zawężenie uprawnień do absolutnie niezbędnych.
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonEC2FullAccess",
    "arn:aws:iam::aws:policy/AmazonRoute53FullAccess",
    "arn:aws:iam::aws:policy/AmazonS3FullAccess",
    "arn:aws:iam::aws:policy/IAMFullAccess", # Bądź ostrożny z tą polityką!
    "arn:aws:iam::aws:policy/AmazonVPCFullAccess",
    "arn:aws:iam::aws:policy/AmazonSQSFullAccess",
    "arn:aws:iam::aws:policy/AmazonEventBridgeFullAccess"
  ]

  tags = {
    Name        = "GitHubActionsRole"
    Description = "IAM role for GitHub Actions to deploy infrastructure via Terraform"
  }
}