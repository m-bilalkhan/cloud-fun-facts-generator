# -----------------------------
# Terraform backend config
# -----------------------------
terraform {
  backend "s3" {
    bucket         = "cloud-fun-facts-generator-bucket"
    key            = "state/terraform.tfstate"
    use_lockfile   = true
    encrypt        = true
    region         = "ap-south-1"
  }
}