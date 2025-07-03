# Publiczna tablica routingu
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-public-rt"
    }
  )
}

# Powiązanie publicznej tablicy routingu z publicznymi podsieciami
resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public # Używamy mapy zdefiniowanej w aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# Prywatne tablice routingu (po jednej na AZ dla elastyczności z NAT Gateway w przyszłości)
resource "aws_route_table" "private" {
  for_each = {
    for i, az in var.availability_zones : az => {
      name_suffix = i + 1
    }
  }
  vpc_id = aws_vpc.main.id

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-private-rt-${each.value.name_suffix}"
    }
  )
}

# Powiązanie prywatnych tablic routingu z odpowiednimi prywatnymi podsieciami
resource "aws_route_table_association" "private" {
  # Zakładamy, że aws_subnet.private jest mapą z kluczami AZ, tak jak aws_route_table.private
  for_each       = aws_subnet.private
  subnet_id      = each.value.id # each.value to obiekt podsieci
  # Musimy znaleźć odpowiednią tablicę routingu dla AZ tej podsieci
  # Kluczem w aws_route_table.private jest AZ (np. "eu-central-1a")
  # Kluczem w aws_subnet.private również jest AZ
  route_table_id = aws_route_table.private[each.key].id
}

# Dodanie trasy do instancji NAT w każdej prywatnej tablicy routingu
resource "aws_route" "private_nat_instance" {
  for_each = aws_route_table.private

  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat.primary_network_interface_id
}
