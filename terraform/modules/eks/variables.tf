variable "env"            { type = string }
variable "cluster_name"   { type = string }
variable "aws_region"     { type = string }
variable "vpc_id"         { type = string }
variable "private_subnets" { type = list(string) }
variable "cluster_endpoint_public_access" { type = bool; default = true }
variable "system_node_group" {
  type = object({
    instance_types = list(string)
    desired_size   = number
  })
}
variable "tags" { type = map(string); default = {} }
