resource "aws_subnet" "public" {
  for_each = {
    for i, az in var.availability_zones : az => {
      cidr_block = var.public_subnet_cidr_blocks[i]
      az         = az
      name_suffix = i + 1 # Dla nazewnictwa np. public-1, public-2
    }
  }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr_block
  availability_zone       = each.value.az
  map_public_ip_on_launch = true # Ważne dla podsieci publicznych

  tags = merge(
    local.common_tags,
    {
      Name                                = "${var.project_name}-public-subnet-${each.value.name_suffix}"
      "kubernetes.io/role/elb"            = "1" # Tag dla AWS Load Balancer Controller (przydatne dla K8s)
      "kubernetes.io/cluster/${var.project_name}" = "shared" # Tag dla klastra K8s (przydatne dla K8s)
    }
  )
}

resource "aws_subnet" "private" {
  for_each = {
    for i, az in var.availability_zones : az => {
      cidr_block = var.private_subnet_cidr_blocks[i]
      az         = az
      name_suffix = i + 1 # Dla nazewnictwa np. private-1, private-2
    }
  }

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.az

  tags = merge(
    local.common_tags,
    {
      Name                                = "${var.project_name}-private-subnet-${each.value.name_suffix}"
      "kubernetes.io/role/internal-elb"   = "1" # Tag dla AWS Load Balancer Controller (przydatne dla K8s)
      "kubernetes.io/cluster/${var.project_name}" = "shared" # Tag dla klastra K8s (przydatne dla K8s)
    }
  )
}