variable "region" {
  description = "Please state the region"
  default     = "us-east-1"

}

variable "subnet" {
  description = "Subnet ID of first zone"
  default     = ["subnet-05f9be0212c0694c6", "subnet-0f506f834442803d7"] #Edit it with your subnet ids

}

variable "security_groups" {
    description = "Security-groups for zone"
    default = ["sg-0136aaa0033aa6972"]
    
}

variable "environment" {
  description = "The environment for the deployment"
  type        = string
  default     = "test" # Default value (optional)
}

variable "github_repo" {
  default = "Riderajit/php-sample-app"

}

variable "github_branch" {
  default = "master"

}

variable "github_oauth_token" {
  default = "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"

}

resource "aws_security_group" "default" {
  vpc_id = data.aws_vpc.default.id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow HTTPS outbound
  }
}